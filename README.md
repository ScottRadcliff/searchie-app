# Searchie

![Searchie, a cheerful retro terminal mascot with a magnifying glass searching a trail of highlighted text files](docs/assets/searchie.png)

Searchie is a small grep-like utility that searches a file or directory and prints matching lines.

For hands-on development, use the files in `samples/` and the
[manual QA guide](docs/manual-qa.md), including copy/paste IEx commands and expected results.

See the [changelog](CHANGELOG.md) and [v0.1 release review](docs/release-readiness.md)
for compatibility notes and verification results.

## Table of contents

- [Standalone command](#standalone-command)
- [Docker development](#docker-development)
- [Searching files outside the project](#searching-files-outside-the-project)
- [Command line usage](#command-line-usage)
- [Search options](#search-options)
- [Compatibility and option precedence](#compatibility-and-option-precedence)
- [Elixir API](#elixir-api)
- [Streaming and limitations](#streaming-and-limitations)

## Standalone command

Build the executable with Docker:

```bash
make build
make package
```

Or, with Elixir 1.16 and a compatible Erlang runtime installed:

```bash
mix escript.build
```

Both commands produce `./searchie`. The escript bundles Elixir and the application;
only Erlang/OTP is required on the target machine. Use an OTP version compatible
with the build runtime (the Docker image builds with OTP 26). The executable can
be copied to a directory on your executable search path and run from any working
directory; it does not require this repository, Mix, or Docker at runtime.

```bash
./searchie samples/logs/app.log error -i -n --color
./searchie --help
```

For example, install the built executable locally:

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 searchie "$HOME/.local/bin/searchie"
```

Ensure `$HOME/.local/bin` is on your executable search path. Search paths are
relative to the current working directory, so after installation you can use
`searchie /absolute/path/to/logs error -i` from anywhere.

The standalone command uses these exit codes:

| Code | Meaning |
| --- | --- |
| `0` | At least one matching line, or successful `--help` |
| `1` | No matching lines (including a count of zero) |
| `2` | Invalid arguments/query, filesystem failure, or invalid UTF-8 text |

Matches and counts go to stdout; diagnostics go to stderr. A directory search
continues after individual failures, prints its successful matches, and exits `2`
if any errors occurred. Counts accompanying errors are partial counts. A file
with invalid UTF-8 stops at the invalid line; earlier matches remain available.

## Docker development

Install Docker with Docker Compose and Make. Host Elixir is not required.
From the project directory:

```bash
make build
make check
make search SEARCH_PATH=sample.txt QUERY=Lorem
```

`make search`, `make test`, `make format`, `make check`, and `make package` use temporary
containers and do not require `make up`. Search arguments use `SEARCH_PATH`
because `PATH` is reserved for executable lookup. Quote queries containing spaces
or shell special characters:

```bash
make search SEARCH_PATH=sample.txt QUERY='Lorem ipsum'
make search SEARCH_PATH=lib QUERY='/def[a-z ]+/'
```

To keep a development container running, use `make up` (attached foreground
logs). In another terminal, use `make shell` or `make console` to open a shell
or IEx with Searchie loaded. Use `Ctrl+C` to stop the attached environment.
Searchie is a CLI, so this container waits for commands and exposes no ports.

`make help` lists all commands, including `build`, `up`, `down`, `stop`,
`restart`, `logs`, `ps`, `shell`, `console`, `test`, `format`, `check`, `search`, and `package`.
`make down` retains named volumes. Source is mounted at `/app`, so edits appear
immediately and formatting updates host files. Build artifacts and dependencies
live in named volumes outside `/app`, separate from the host's `_build` and `deps`.
The project currently has no external dependencies or database preparation steps.

### Searching files outside the project

Mount an additional directory read-only and use its container path. For example,
to search a host directory whose name contains spaces:

```bash
docker compose run --rm -T \
  -v "/absolute/path/to/my logs:/data:ro" \
  app mix filter /data 'error' --modifier context=2
```

For other search modifiers, invoke `docker compose run --rm -T app mix filter`
with the same arguments shown below. With host Elixir installed, the direct
`mix filter` commands also work.

## Command line usage

```bash
mix filter path/to/file.txt "needle"
```

Search a directory recursively:

```bash
mix filter path/to/directory "needle"
```

Use a regex query by wrapping it in `/.../`:

```bash
mix filter path/to/file.txt "/error [0-9]+/"
```

### Search options

| Option | Short form | Behavior |
| --- | --- | --- |
| `--ignore-case` | `-i` | Case-insensitive literal or regex matching |
| `--line-number` | `-n` | Prefix matching lines with line numbers |
| `--count` | `-c` | Print the total number of matching lines |
| `--context N` | `-C N` | Show N lines before and after each match |
| `--color` | | Highlight matches in yellow |
| `--color-name NAME` | | Highlight in black, red, green, yellow, blue, magenta, cyan, or white |
| `--include GLOB` | | Include matching files; repeat to select multiple patterns |
| `--exclude GLOB` | | Exclude matching files or directories; repeat as needed |

Combine flags to search Elixir files, exclude generated files, and show numbered,
case-insensitive results with highlighting:

```bash
mix filter . "error" -i -n --color --include '*.ex' --include '*.exs' --exclude _build --exclude .git
mix filter sample.txt '/lorem [a-z]+/' -i --context 2 --color-name cyan
mix filter lib 'def' --count
```

Use the same options in Docker:

```bash
docker compose run --rm -T app mix filter lib 'def' -n --include '*.ex'
```

Quote glob patterns so the shell passes them to Searchie without expanding them.
Patterns without `/`, such as `*.ex` or `_build`, match at any depth. Patterns
containing `/` are relative to the search root: `lib/*.ex` matches files directly
in `lib`, while `lib/**/*.ex` also matches its subdirectories. For an individual
file, the root is its parent directory. Includes select files, and exclusions
always take priority. Excluding a directory excludes all its descendant files.
A trailing slash is accepted on directory exclusions.

Hidden files are searched too. There are no automatic exclusions and `.gitignore`
is not read; use `--exclude .git`, `--exclude _build`, and other patterns as needed.
Excluded directories are skipped during the search traversal. Glob expansion
still enumerates paths to build the include/exclude sets.

### Compatibility and option precedence

Existing modifier commands remain supported, including the new options:

```bash
mix filter sample.txt "Lorem" --modifier color=red --modifier context=2
mix filter lib "DEF" --modifier ignore-case --modifier line-number --modifier 'include=*.ex'
```

- Scalar options use the last value in command-line order, including mixed flags
  and modifiers. Include and exclude patterns accumulate instead.
- Boolean flags support `--no-count`, `--no-color`, `--no-ignore-case`, and
  `--no-line-number`. Legacy `--modifier count=false` also disables a flag.
- `--count` takes precedence over context, color, and line-number output. It counts
  matching **lines**, even when a query occurs several times on one line.
- Options are validated even when there are no results or count output is selected.
- Without `--line-number`, single-file searches print matching text and directory
  searches print `path:text`. With it, they print `line:text` and `path:line:text`.
- Context output always includes file and line metadata. It shows a separate block
  per match, marking the matching line with `>`. Only matching lines are highlighted.
- Case-insensitive search preserves the original text and casing in results.
- Queries wrapped in `/.../` are regular expressions; other queries are literals.
- `mix help filter` lists the CLI options.

## Elixir API

`Searchie.filter/3` accepts the same string-keyed modifiers and returns file, line,
and original text metadata. Presentation options are returned for callers to
render; they do not alter the match list.

```elixir
Searchie.filter("lib", "DEF", [
  {"ignore-case", true},
  {"include", "*.ex"},
  {"exclude", "_build"}
])
# {:ok, %{matches: [%{file_path: "lib/searchie.ex", line_number: 1, line_text: "..."}, ...],
#         modifiers: [...], errors: []}}
```

Boolean modifiers accept `true` or `false` (the string `"false"` also disables a
flag). Scalar modifiers use their last value; include and exclude modifiers
accumulate. File filtering and case sensitivity belong to the core API;
formatting, context, color, and count rendering belong to the CLI.

`errors` contains `%{file_path: path, reason: reason}` entries for read, traversal,
and invalid-encoding failures. Check it even when the outer result is `:ok`.
Root validation errors return `{:error, reason}`, such as `:enoent`,
`:unsupported_path`, or `{:file_error, path, reason}`. Invalid queries and patterns
return `:invalid_regex`, `{:invalid_pattern, name}`, or `{:invalid_glob, pattern}`.

For large files, reduce matches incrementally instead of collecting them:

```elixir
Searchie.scan("samples", "error", [{"ignore-case", true}], 0, fn _match, count ->
  count + 1
end)
# {:ok, %{value: 9, count: 9, errors: []}}
```

`scan/6` accepts an optional final context size. With positive context, each match
also has a `context` list of `{line_number, text}` tuples. Matches are delivered
once their following context is available, or at the end of the file.

`Searchie.CLI.run/1` returns `{:ok, exit_code}` after rendering output, or
`{:error, message}` for usage/root errors. `Mix.Tasks.Filter.run/1` is a development
adapter that returns the code or raises `Mix.Error` for usage/root errors. These
console APIs do not halt IEx; use the standalone executable when shell exit codes
are needed.

## Streaming and limitations

- The CLI scans each file once, including context output, without collecting all
  matches. `--count` also streams and does not retain matching lines.
- File-content memory depends on the longest line and requested context size.
  Path-filter sets and filesystem errors require additional metadata memory.
  `filter/3` collects all matching lines; a `scan/6` accumulator can also grow if
  the caller chooses to retain results.
- Empty files contain no lines. A final newline terminates its line without
  creating an extra empty line. Internal blank lines are searchable.
- Search input is UTF-8 text. Binary or differently encoded files can produce
  encoding errors; exclude those files when searching mixed directories.
- Nested directory symlinks are skipped to prevent cycles. File symlinks are
  searched; broken symlinks are reported. An explicitly supplied directory
  symlink is accepted as the search root.
- Context blocks can overlap. `.gitignore` compatibility, JSON output, whole-word
  matching, and Hex publication remain outside v0.1.
