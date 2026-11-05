defmodule Searchie do
  @moduledoc """
  Search utilities for finding matching lines in text files.
  """

  @type modifier :: {String.t(), String.t() | boolean()}
  @type match :: %{file_path: Path.t(), line_number: pos_integer(), line_text: String.t()}
  @type result :: %{matches: [match()], modifiers: [modifier()]}

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
  """
  @spec filter(Path.t(), String.t(), [modifier()]) ::
          {:ok, result()} | {:error, :enoent | :unsupported_path | :invalid_regex}
  def filter(path, query, modifiers \\ []) when is_binary(path) and is_binary(query) do
    with {:ok, regex} <- compile_query(query, modifiers) do
      matcher = &Regex.match?(regex, &1)

      case File.stat(path) do
        {:ok, %File.Stat{type: :regular}} ->
          {:ok, %{matches: filtered_file_matches(path, matcher, modifiers), modifiers: modifiers}}

        {:ok, %File.Stat{type: :directory}} ->
          {:ok, %{matches: directory_matches(path, matcher, modifiers), modifiers: modifiers}}

        {:ok, _other} ->
          {:error, :unsupported_path}

        {:error, :enoent} ->
          {:error, :enoent}
      end
    end
  end

  defp file_matches(file_path, matcher) do
    case File.read(file_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: false)
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _line_number} -> matcher.(line) end)
        |> Enum.map(fn {line, line_number} ->
          %{file_path: file_path, line_number: line_number, line_text: line}
        end)

      {:error, _reason} ->
        []
    end
  end

  defp filtered_file_matches(path, matcher, modifiers) do
    root = Path.dirname(Path.expand(path))
    files = select_files([path], root, modifiers)
    Enum.flat_map(files, &file_matches(&1, matcher))
  end

  defp directory_matches(directory_path, matcher, modifiers) do
    directory_path
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> select_files(Path.expand(directory_path), modifiers)
    |> Enum.flat_map(&file_matches(&1, matcher))
  end

  defp select_files(files, root, modifiers) do
    includes = matching_paths(root, modifiers, "include")
    excludes = matching_paths(root, modifiers, "exclude")
    has_includes = Enum.any?(modifiers, fn {name, _} -> name == "include" end)

    Enum.filter(files, fn file ->
      expanded = Path.expand(file)
      included = not has_includes or MapSet.member?(includes, expanded)
      included and not excluded?(expanded, root, excludes)
    end)
  end

  defp matching_paths(root, modifiers, name) do
    modifiers
    |> Enum.filter(fn {key, _} -> key == name end)
    |> Enum.flat_map(fn {_, pattern} ->
      pattern = String.trim_trailing(pattern, "/")
      glob = if String.contains?(pattern, "/"), do: pattern, else: "**/" <> pattern
      root |> Path.join(glob) |> Path.wildcard(match_dot: true)
    end)
    |> Enum.map(&Path.expand/1)
    |> MapSet.new()
  end

  defp excluded?(path, root, excludes) do
    cond do
      MapSet.member?(excludes, path) -> true
      path == root -> false
      true -> excluded?(Path.dirname(path), root, excludes)
    end
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
