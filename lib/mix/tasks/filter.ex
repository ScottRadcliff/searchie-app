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

  @shortdoc "Search a file or directory for matching lines"

  @impl Mix.Task
  def run(args) do
    case Searchie.CLI.run(args) do
      {:ok, status} -> status
      {:error, message} -> Mix.raise(message)
    end
  end
end
