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

Combine modifiers:

```bash
mix filter path/to/file.txt "needle" --modifier count --modifier context=2
```

Colorize matched text:

```bash
mix filter path/to/file.txt "needle" --modifier color
mix filter path/to/file.txt "needle" --modifier color=red
```

Return only the number of matches:

```bash
mix filter path/to/file.txt "needle" --modifier count
mix filter path/to/directory "needle" --modifier count
```

Show context lines around each match:

```bash
mix filter path/to/file.txt "needle" --modifier context=2
mix filter path/to/directory "needle" --modifier context=3
```

## Notes

- `--modifier` can be provided multiple times.
- Supported formats are `key=value` and `flag`.
- Query is treated as regex when wrapped in `/.../`.
- When searching a directory, output is formatted as `path/to/file:matching line`.
- `count` prints only the total number of matches.
- `context=N` shows `N` lines above and below each match.
- `color` now highlights the matched text. If provided as a flag, it defaults to yellow.
