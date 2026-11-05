defmodule Searchie.CLI do
  @moduledoc """
  Search a file or directory for matching lines.

  Usage:

      mix filter PATH QUERY [OPTIONS] [--modifier key=value]...

  Options:

    * `--ignore-case`, `-i`: case-insensitive literal or regex matching
    * `--line-number`, `-n`: prefix matching lines with line numbers
    * `--count`, `-c`: print only the total number of matching lines
    * `--context N`, `-C N`: show N lines before and after each match
    * `--color`: highlight matches in yellow
    * `--color-name NAME`: highlight matches in a named ANSI color
    * `--include GLOB`: select files (repeatable)
    * `--exclude GLOB`: exclude files or directories (repeatable)

  Scalar options use their last command-line value, including legacy modifiers.
  Boolean flags can be disabled with their `--no-` form. Count overrides other
  output modes; context output already includes line numbers.
  """

  @supported_colors %{
    "black" => :black,
    "red" => :red,
    "green" => :green,
    "yellow" => :yellow,
    "blue" => :blue,
    "magenta" => :magenta,
    "cyan" => :cyan,
    "white" => :white
  }

  @doc "Entrypoint for the standalone escript."
  def main(args) do
    status =
      case run(args) do
        {:ok, status} ->
          status

        {:error, message} ->
          IO.puts(:stderr, message)
          2
      end

    System.halt(status)
  end

  @doc "Runs a search without halting the VM; returns an exit status or a usage error."
  def run(args) do
    if args in [["--help"], ["-h"]] do
      IO.puts(help())
      {:ok, 0}
    else
      execute(args)
    end
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  defp execute(args) do
    case parse_args(args) do
      {:ok, path, query, modifiers} ->
        count? = count_enabled?(modifiers)
        context = if count?, do: 0, else: context_size(modifiers)

        regex =
          case Searchie.compile_query(query, modifiers) do
            {:ok, regex} -> regex
            {:error, :invalid_regex} -> raise ArgumentError, "Invalid regex query: #{query}"
          end

        color = color_from_modifiers(modifiers)

        directory? = File.dir?(path)

        render = fn match, index ->
          unless count?,
            do: render_match(match, index + 1, directory?, regex, color, modifiers)

          index + 1
        end

        case Searchie.scan(path, query, modifiers, 0, render, context) do
          {:ok, result} ->
            if count?, do: IO.puts(result.count)
            Enum.each(result.errors, &IO.puts(:stderr, file_error(&1.file_path, &1.reason)))

            status =
              cond do
                result.errors != [] -> 2
                result.count == 0 -> 1
                true -> 0
              end

            {:ok, status}

          {:error, reason} ->
            {:error, search_error(reason, path, query)}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp search_error(:enoent, path, _), do: "Path not found: #{path}"
  defp search_error(:unsupported_path, path, _), do: "Unsupported path type: #{path}"
  defp search_error(:invalid_regex, _, query), do: "Invalid regex query: #{query}"
  defp search_error({:file_error, path, reason}, _, _), do: file_error(path, reason)

  defp search_error({:invalid_pattern, name}, _, _),
    do: "#{name} requires a non-empty glob pattern"

  defp search_error({:invalid_glob, pattern}, _, _), do: "Invalid glob pattern: #{pattern}"

  defp file_error(path, :invalid_encoding), do: "#{path}: invalid UTF-8 text"
  defp file_error(path, :unsupported_path), do: "#{path}: unsupported path type"
  defp file_error(path, reason), do: "#{path}: #{:file.format_error(reason)}"

  defp help do
    """
    Usage: searchie PATH QUERY [OPTIONS]
      -i, --ignore-case       Case-insensitive literal or /regex/ search
      -n, --line-number       Show line numbers
      -c, --count             Print matching-line count
      -C, --context N         Show N lines before and after matches
          --color             Highlight in yellow
          --color-name NAME   Highlight in a named ANSI color
          --include GLOB      Include files (repeatable)
          --exclude GLOB      Exclude files or directories (repeatable)
          --modifier VALUE    Legacy flag or key=value (repeatable)
      -h, --help              Show this help
    Exit codes: 0 matches, 1 no matches, 2 errors (including partial failures).
    """
  end

  defp parse_args(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          modifier: :keep,
          count: [:boolean, :keep],
          context: [:integer, :keep],
          color: [:boolean, :keep],
          color_name: :keep,
          ignore_case: [:boolean, :keep],
          line_number: [:boolean, :keep],
          include: :keep,
          exclude: :keep
        ],
        aliases: [i: :ignore_case, n: :line_number, c: :count, C: :context]
      )

    cond do
      invalid != [] ->
        {:error, "Invalid options: #{inspect(invalid)}"}

      length(positional) != 2 ->
        {:error, "Usage: searchie PATH QUERY [OPTIONS] [--modifier key=value]..."}

      true ->
        [path, query] = positional

        modifiers =
          Enum.flat_map(opts, fn
            {:modifier, value} ->
              parse_modifiers([value])

            {:color_name, value} ->
              [{"color", value}]

            {name, value} when is_integer(value) ->
              [{Atom.to_string(name), Integer.to_string(value)}]

            {name, value} ->
              [{name |> Atom.to_string() |> String.replace("_", "-"), value}]
          end)

        validate_modifiers!(modifiers)
        {:ok, path, query, modifiers}
    end
  end

  defp parse_modifiers(values) do
    Enum.map(values, fn value ->
      case String.split(value, "=", parts: 2) do
        [key, val] when key != "" and val != "" -> {key, val}
        [flag] when flag != "" -> {flag, true}
        _ -> raise ArgumentError, "Invalid modifier format: #{value}"
      end
    end)
  end

  defp render_match(%{context: lines} = match, index, _directory?, regex, color, _modifiers) do
    IO.puts("[#{index}] #{match.file_path}:#{match.line_number}")

    Enum.each(lines, fn {number, text} ->
      hit? = number == match.line_number
      marker = if hit?, do: ">", else: " "
      text = if hit?, do: colorize(text, regex, color), else: text
      IO.puts("#{marker} #{number}: #{text}")
    end)
  end

  defp render_match(match, _index, directory?, regex, color, modifiers) do
    prefix = if directory?, do: "#{match.file_path}:", else: ""

    prefix =
      if Searchie.enabled?(modifiers, "line-number"),
        do: prefix <> "#{match.line_number}:",
        else: prefix

    IO.puts(prefix <> colorize(match.line_text, regex, color))
  end

  defp colorize(line, _regex, nil), do: line

  defp colorize(line, regex, color) do
    Regex.replace(regex, line, fn match ->
      IO.ANSI.format([color, match], true) |> IO.iodata_to_binary()
    end)
  end

  defp color_from_modifiers(modifiers) do
    case Searchie.option(modifiers, "color") do
      value when value in [nil, false, "false"] ->
        nil

      true ->
        :yellow

      value when is_binary(value) and value != "false" ->
        case Map.fetch(@supported_colors, String.downcase(value)) do
          {:ok, color} -> color
          :error -> raise ArgumentError, "Unsupported color modifier: #{value}"
        end
    end
  end

  defp count_enabled?(modifiers) do
    Searchie.enabled?(modifiers, "count")
  end

  defp context_size(modifiers) do
    case Searchie.option(modifiers, "context") do
      nil ->
        0

      true ->
        raise ArgumentError, "context modifier requires a number, e.g. --modifier context=2"

      value ->
        case Integer.parse(value) do
          {number, ""} when number >= 0 ->
            number

          _ ->
            raise ArgumentError, "context modifier must be a non-negative integer: #{value}"
        end
    end
  end

  defp validate_modifiers!(modifiers) do
    context_size(modifiers)
    color_from_modifiers(modifiers)

    Enum.each(modifiers, fn
      {name, value} when name in ["include", "exclude"] ->
        if not is_binary(value) or value == "" do
          raise ArgumentError, "#{name} requires a non-empty glob pattern"
        end

      _ ->
        :ok
    end)
  end
end
