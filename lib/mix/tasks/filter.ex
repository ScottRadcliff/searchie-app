defmodule Mix.Tasks.Filter do
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

  use Mix.Task

  @shortdoc "Filters a file by a query string"
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

  @impl Mix.Task
  def run(args) do
    case parse_args(args) do
      {:ok, path, query, modifiers} ->
        case Searchie.filter(path, query, modifiers) do
          {:ok, %{matches: matches}} ->
            if count_enabled?(modifiers) do
              Mix.shell().info(Integer.to_string(length(matches)))
            else
              render_matches(matches, path, query, modifiers)
            end

          {:error, :enoent} ->
            Mix.raise("Path not found: #{path}")

          {:error, :unsupported_path} ->
            Mix.raise("Unsupported path type: #{path}")

          {:error, :invalid_regex} ->
            Mix.raise("Invalid regex query: #{query}")
        end

      {:error, message} ->
        Mix.raise(message)
    end
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
        {:error, "Usage: mix filter PATH QUERY [OPTIONS] [--modifier key=value]..."}

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
        _ -> Mix.raise("Invalid modifier format: #{value}")
      end
    end)
  end

  defp render_matches(matches, path, query, modifiers) do
    context = context_size(modifiers)

    if context == 0 do
      render_simple_matches(matches, path, query, modifiers)
    else
      render_matches_with_context(matches, query, modifiers, context)
    end
  end

  defp render_simple_matches(matches, path, query, modifiers) do
    directory? = File.dir?(path)
    numbered? = Searchie.enabled?(modifiers, "line-number")

    Enum.each(matches, fn match ->
      line = maybe_colorize_line(match.line_text, query, modifiers)
      prefix = if directory?, do: "#{match.file_path}:", else: ""
      prefix = if numbered?, do: prefix <> "#{match.line_number}:", else: prefix
      Mix.shell().info(prefix <> line)
    end)
  end

  defp render_matches_with_context(matches, query, modifiers, context) do
    file_cache = load_file_cache(matches)

    matches
    |> Enum.with_index(1)
    |> Enum.each(fn {match, index} ->
      Mix.shell().info("[#{index}] #{match.file_path}:#{match.line_number}")

      file_cache
      |> Map.fetch!(match.file_path)
      |> surrounding_lines(match.line_number, context)
      |> Enum.each(fn {line_number, text} ->
        marker = if line_number == match.line_number, do: ">", else: " "

        line =
          maybe_colorize_context_line(text, query, modifiers, line_number == match.line_number)

        Mix.shell().info("#{marker} #{line_number}: #{line}")
      end)
    end)
  end

  defp load_file_cache(matches) do
    matches
    |> Enum.map(& &1.file_path)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn file_path, acc ->
      lines =
        case File.read(file_path) do
          {:ok, content} -> String.split(content, "\n", trim: false)
          {:error, _reason} -> []
        end

      Map.put(acc, file_path, lines)
    end)
  end

  defp surrounding_lines(lines, center_line, context) do
    start_line = max(1, center_line - context)
    end_line = min(length(lines), center_line + context)

    start_line..end_line
    |> Enum.map(fn line_number ->
      {line_number, Enum.at(lines, line_number - 1)}
    end)
  end

  defp maybe_colorize_context_line(line, query, modifiers, true) do
    maybe_colorize_line(line, query, modifiers)
  end

  defp maybe_colorize_context_line(line, _query, _modifiers, false), do: line

  defp maybe_colorize_line(line, query, modifiers) do
    case color_from_modifiers(modifiers) do
      nil -> line
      color -> apply_color(line, query, color, modifiers)
    end
  end

  defp apply_color(line, query, color, modifiers) do
    {:ok, regex} = Searchie.compile_query(query, modifiers)

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
          :error -> Mix.raise("Unsupported color modifier: #{value}")
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
        Mix.raise("context modifier requires a number, e.g. --modifier context=2")

      value ->
        case Integer.parse(value) do
          {number, ""} when number >= 0 ->
            number

          _ ->
            Mix.raise("context modifier must be a non-negative integer: #{value}")
        end
    end
  end

  defp validate_modifiers!(modifiers) do
    context_size(modifiers)
    color_from_modifiers(modifiers)

    Enum.each(modifiers, fn
      {name, value} when name in ["include", "exclude"] ->
        if not is_binary(value) or value == "" do
          Mix.raise("#{name} requires a non-empty glob pattern")
        end

      _ ->
        :ok
    end)
  end
end
