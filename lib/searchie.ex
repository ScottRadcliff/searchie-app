defmodule Searchie do
  @moduledoc """
  Search utilities for finding matching lines in text files.
  """

  @type modifier :: {String.t(), String.t() | boolean()}
  @type match :: %{
          required(:file_path) => Path.t(),
          required(:line_number) => pos_integer(),
          required(:line_text) => String.t(),
          optional(:context) => [{pos_integer(), String.t()}]
        }
  @type file_error :: %{file_path: Path.t(), reason: term()}
  @type result :: %{matches: [match()], modifiers: [modifier()], errors: [file_error()]}
  @type scan_result(accumulator) :: %{
          value: accumulator,
          count: non_neg_integer(),
          errors: [file_error()]
        }

  @doc """
  Filters `path` for lines containing `query`.

  Supports both files and directories. Directory searches are recursive and
  include file and line metadata for each match. If `query` is wrapped in `/.../`,
  it is treated as a regular expression.

  Modifiers are string-keyed tuples. `{"ignore-case", true}` enables
  case-insensitive matching; `{"include", "*.ex"}` and `{"exclude", "_build"}`
  filter files. Repeat includes to select their union; exclusions take priority.
  Patterns without `/` match at any depth, while other patterns are relative to
  the search directory (or a single file's parent). Hidden files are included.
  Presentation modifiers are returned unchanged for the caller to render.
  Scalar options use the last value; boolean false or "false" disables a flag.
  Files are read line by line. This convenience API collects matching lines;
  use `scan/6` for incremental results. Filesystem errors are returned in `errors`.
  Empty files have no lines, and a final newline does not add a synthetic empty line.
  """
  @spec filter(Path.t(), String.t(), [modifier()]) ::
          {:ok, result()} | {:error, term()}
  def filter(path, query, modifiers \\ []) do
    case scan(path, query, modifiers, [], fn match, acc -> [match | acc] end) do
      {:ok, result} ->
        {:ok, %{matches: Enum.reverse(result.value), modifiers: modifiers, errors: result.errors}}

      error ->
        error
    end
  end

  @doc """
  Reduces matches as they are read, without retaining all matches or file contents.

  Returns `{:ok, %{value: accumulator, count: count, errors: errors}}`. Filesystem
  failures during traversal or reading are reported in `errors`; successful matches
  are retained. Root-path and query validation failures return `{:error, reason}`.

  With positive `context`, each match includes a `context` list of `{line, text}`
  tuples. A bounded window delays delivery until the following context is read.
  File-content memory depends on context, the longest line, and the caller's
  accumulator; filters and errors also retain path metadata.
  Nested directory symlinks are not followed, preventing cycles.
  """
  @spec scan(
          Path.t(),
          String.t(),
          [modifier()],
          accumulator,
          (match(), accumulator -> accumulator),
          non_neg_integer()
        ) :: {:ok, scan_result(accumulator)} | {:error, term()}
        when accumulator: term()
  def scan(path, query, modifiers, initial, reducer, context \\ 0)
      when is_binary(path) and is_binary(query) and is_integer(context) and context >= 0 do
    with {:ok, regex} <- compile_query(query, modifiers),
         :ok <- validate_patterns(modifiers),
         {:ok, stat} <- root_stat(path) do
      root =
        if stat.type == :directory, do: Path.expand(path), else: Path.dirname(Path.expand(path))

      with {:ok, includes} <- matching_paths(root, modifiers, "include"),
           {:ok, excludes} <- matching_paths(root, modifiers, "exclude") do
        filters = %{
          includes: includes,
          excludes: excludes,
          has_includes: Enum.any?(modifiers, fn {key, _} -> key == "include" end)
        }

        state = %{value: initial, count: 0, errors: []}
        state = walk(path, stat, regex, filters, reducer, context, state)
        {:ok, %{state | errors: Enum.reverse(state.errors)}}
      end
    end
  end

  defp validate_patterns(modifiers) do
    Enum.reduce_while(modifiers, :ok, fn
      {name, value}, :ok when name in ["include", "exclude"] ->
        if is_binary(value) and value != "" do
          {:cont, :ok}
        else
          {:halt, {:error, {:invalid_pattern, name}}}
        end

      _, :ok ->
        {:cont, :ok}
    end)
  end

  defp root_stat(path) do
    case File.stat(path) do
      {:ok, %{type: type} = stat} when type in [:regular, :directory] -> {:ok, stat}
      {:ok, _} -> {:error, :unsupported_path}
      {:error, :enoent} -> {:error, :enoent}
      {:error, reason} -> {:error, {:file_error, path, reason}}
    end
  end

  defp walk(path, stat, regex, filters, reducer, context, state) do
    expanded = Path.expand(path)

    cond do
      MapSet.member?(filters.excludes, expanded) ->
        state

      stat.type == :directory ->
        walk_directory(path, regex, filters, reducer, context, state)

      stat.type == :regular ->
        if not filters.has_includes or MapSet.member?(filters.includes, expanded) do
          scan_file(path, regex, reducer, context, state)
        else
          state
        end

      true ->
        add_error(state, path, :unsupported_path)
    end
  end

  defp walk_directory(path, regex, filters, reducer, context, state) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.reduce(state, fn entry, acc ->
          child = Path.join(path, entry)

          if MapSet.member?(filters.excludes, Path.expand(child)) do
            acc
          else
            case File.lstat(child) do
              {:ok, %{type: :symlink}} ->
                case File.stat(child) do
                  {:ok, %{type: :directory}} -> acc
                  {:ok, stat} -> walk(child, stat, regex, filters, reducer, context, acc)
                  {:error, reason} -> add_error(acc, child, reason)
                end

              {:ok, stat} ->
                walk(child, stat, regex, filters, reducer, context, acc)

              {:error, reason} ->
                add_error(acc, child, reason)
            end
          end
        end)

      {:error, reason} ->
        add_error(state, path, reason)
    end
  end

  defp scan_file(path, regex, reducer, context, state) do
    case File.open(path, [:read, :binary], fn device ->
           read_lines(device, path, regex, reducer, context, state, 0, :queue.new(), :queue.new())
         end) do
      {:ok, result} -> result
      {:error, reason} -> add_error(state, path, reason)
    end
  end

  defp read_lines(device, path, regex, reducer, context, state, number, buffer, pending) do
    case IO.binread(device, :line) do
      :eof ->
        emit_ready(pending, buffer, number, context, reducer, state, true) |> elem(1)

      {:error, reason} ->
        {_, state} = emit_ready(pending, buffer, number, context, reducer, state, true)
        add_error(state, path, reason)

      line ->
        text =
          if String.ends_with?(line, "\n"),
            do: binary_part(line, 0, byte_size(line) - 1),
            else: line

        if String.valid?(text) do
          number = number + 1
          buffer = :queue.in({number, text}, buffer)
          buffer = if number > 2 * context + 1, do: :queue.drop(buffer), else: buffer

          pending =
            if Regex.match?(regex, text) do
              :queue.in(%{file_path: path, line_number: number, line_text: text}, pending)
            else
              pending
            end

          {pending, state} = emit_ready(pending, buffer, number, context, reducer, state, false)
          read_lines(device, path, regex, reducer, context, state, number, buffer, pending)
        else
          {_, state} = emit_ready(pending, buffer, number, context, reducer, state, true)
          add_error(state, path, :invalid_encoding)
        end
    end
  end

  defp emit_ready(pending, buffer, number, context, reducer, state, flush?) do
    case :queue.out(pending) do
      {{:value, match}, rest} when flush? or match.line_number + context <= number ->
        match =
          if context > 0 do
            lines =
              buffer
              |> :queue.to_list()
              |> Enum.filter(fn {n, _} ->
                n >= match.line_number - context and n <= match.line_number + context
              end)

            Map.put(match, :context, lines)
          else
            match
          end

        state = %{state | count: state.count + 1, value: reducer.(match, state.value)}
        emit_ready(rest, buffer, number, context, reducer, state, flush?)

      _ ->
        {pending, state}
    end
  end

  defp add_error(state, path, reason) do
    %{state | errors: [%{file_path: path, reason: reason} | state.errors]}
  end

  defp matching_paths(root, modifiers, name) do
    modifiers
    |> Enum.filter(fn {key, _} -> key == name end)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {_, pattern}, {:ok, paths} ->
      glob = String.trim_trailing(pattern, "/")
      glob = if String.contains?(glob, "/"), do: glob, else: "**/" <> glob

      try do
        matches =
          root
          |> escape_glob_root()
          |> Path.join(glob)
          |> Path.wildcard(match_dot: true)
          |> Enum.map(&Path.expand/1)

        {:cont, {:ok, MapSet.union(paths, MapSet.new(matches))}}
      rescue
        _ in [ErlangError, ArgumentError] -> {:halt, {:error, {:invalid_glob, pattern}}}
      end
    end)
  end

  # Only the user-supplied pattern is a glob; the directory prefix is literal.
  defp escape_glob_root(root) do
    root
    |> String.graphemes()
    |> Enum.map_join(fn
      char when char in ["[", "*", "?", "{"] -> "[" <> char <> "]"
      char -> char
    end)
  end

  @doc """
  Returns the last value of a modifier, or `default` when absent.
  """
  def option(modifiers, name, default \\ nil) do
    Enum.reduce(modifiers, default, fn
      {^name, value}, _ -> value
      _, previous -> previous
    end)
  end

  @doc false
  def enabled?(modifiers, name) do
    option(modifiers, name, false) not in [false, "false"]
  end

  @doc false
  def compile_query(query, modifiers) do
    pattern =
      case parse_regex_query(query) do
        {:regex, pattern} -> pattern
        :literal -> Regex.escape(query)
      end

    flags = if enabled?(modifiers, "ignore-case"), do: "iu", else: "u"

    case Regex.compile(pattern, flags) do
      {:ok, regex} -> {:ok, regex}
      {:error, _} -> {:error, :invalid_regex}
    end
  end

  defp parse_regex_query(query) do
    if String.length(query) >= 2 and String.starts_with?(query, "/") and
         String.ends_with?(query, "/") do
      pattern = String.slice(query, 1, String.length(query) - 2)
      {:regex, pattern}
    else
      :literal
    end
  end
end
