# Manual QA samples

The `samples/` directory contains static text for development. Run commands from
the project root. It includes mixed-case log messages, nested directories,
an Elixir source file, a filename with spaces, literal punctuation, Unicode,
a hidden file, and generated output for exclusion checks.

## IEx console

Run `make up`, then `make console` in another terminal. Without Docker, run
`iex -S mix`. Source edits can be loaded with `recompile()`.

Inspect structured results:

```elixir
{:ok, result} = Searchie.filter("samples/logs/app.log", "error")
Enum.map(result.matches, &{&1.line_number, &1.line_text})
# Matching lines: 2 and 7. Line 7 contains two occurrences but counts as one line.

{:ok, result} = Searchie.filter("samples/logs/app.log", "error", [{"ignore-case", true}])
Enum.map(result.matches, & &1.line_number)
# [2, 4, 6, 7]

{:ok, result} = Searchie.filter("samples", "error", [
  {"ignore-case", true}, {"exclude", "_build"}, {"exclude", ".hidden.log"}
])
length(result.matches)
# 7: four app log lines, two worker log lines, and one source line.

Searchie.filter("samples", "error", [{"include", "*.ex"}])
# One match: samples/src/example.ex, line 4.

Searchie.filter("samples/notes/release notes.txt", "config.json")
# One literal match on line 2; the dot is not a regex wildcard.

{:ok, result} = Searchie.filter("samples/notes/release notes.txt", "café", [{"ignore-case", true}])
length(result.matches)
# 1 matching line, containing three differently cased occurrences.

Searchie.filter("samples", "nothing-matches-this")
# {:ok, %{matches: [], modifiers: []}}

Searchie.filter("samples/missing.txt", "error")
# {:error, :enoent}

Searchie.filter("samples/logs/app.log", "/(unclosed/")
# {:error, :invalid_regex}
```

For formatted output, call the task module directly. This can be repeated in the
same console without Mix task re-enabling:

```elixir
Mix.Tasks.Filter.run(["samples/logs/app.log", "error", "-i", "-n", "--color"])
# Four matching lines, numbered 2, 4, 6, and 7, preserving their original casing.

Mix.Tasks.Filter.run(["samples/logs/app.log", "/error [0-9]+/", "-i", "-C", "1", "--color-name", "cyan"])
# Four context blocks; the matching line in each block is marked with >.

Mix.Tasks.Filter.run(["samples", "error", "-i", "--include", "*.log", "--exclude", "_build", "--exclude", ".hidden.log", "--count"])
# 6

Mix.Tasks.Filter.run(["samples", "error", "-i", "--count"])
# 9: includes generated output and the hidden file.

Mix.Tasks.Filter.run(["samples/logs/app.log", "error", "--modifier", "color=red", "--modifier", "context=1"])
# Two context blocks using the legacy modifier syntax.
```

Count, context, line numbers, and color are rendered by the CLI. Passing those
modifiers to `Searchie.filter/3` returns the full matching-line metadata instead.

## Terminal

From a host or container shell:

```bash
mix filter samples/logs/app.log error -i -n --color
mix filter samples '/error [0-9]+/' -i --include '*.log' --exclude _build --exclude .hidden.log --count
# 6
mix filter 'samples/notes/release notes.txt' 'config.json' -n
# 2:Literal punctuation: config.json and price=$5.00
```

For a one-off Docker search, prefix these commands with
`docker compose run --rm -T app`. A basic Makefile search also works:

```bash
make search SEARCH_PATH=samples/logs/app.log QUERY=error
```
