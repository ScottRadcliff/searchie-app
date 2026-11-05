# Searchie

Searchie is a small grep-like utility that searches a file or directory and prints matching lines.

## Docker development

Install Docker with Docker Compose and Make. Host Elixir is not required.
From the project directory:

```bash
make build
make check
make search SEARCH_PATH=sample.txt QUERY=Lorem
```

`make search`, `make test`, `make format`, and `make check` use temporary
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
`restart`, `logs`, `ps`, `shell`, `console`, `test`, `format`, `check`, and `search`.
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
Filters are applied before reading file contents; directory enumeration still
visits the search tree.

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
#         modifiers: [...]}}
```

Boolean modifiers accept `true` or `false` (the string `"false"` also disables a
flag). Scalar modifiers use their last value; include and exclude modifiers
accumulate. File filtering and case sensitivity belong to the core API;
formatting, context, color, and count rendering belong to the CLI.
