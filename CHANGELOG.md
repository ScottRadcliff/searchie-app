# Changelog

## 0.1.0 — prepared for release

- Search individual files or directories recursively using literal or `/regex/` queries.
- Support case-insensitive matching, line numbers, highlighting, counts, context,
  and repeatable file include/exclude patterns.
- Preserve the original `--modifier` interface alongside conventional CLI flags.
- Provide a reusable Elixir API with incremental `scan/6` and collecting `filter/3`.
- Stream file contents and context in one pass; retain partial results and report
  filesystem or UTF-8 errors.
- Package a standalone escript with exit codes 0 (matches), 1 (no matches), and
  2 (errors). The target machine requires compatible Erlang/OTP.
- Add Docker development tooling, Make commands, sample files, and manual QA docs.

### Compatibility notes

- `filter/3` results now include an `errors` list. Callers should check it even
  when the outer result is `:ok`; matches can be partial.
- Empty files contain no lines, and a final newline does not produce an additional
  empty line. This changes empty-query and empty-line-regex behavior from the
  original whole-file splitting implementation.
- Hidden files are searched. No automatic `.gitignore` handling is provided.
- Nested directory symlinks are skipped to prevent cycles. File symlinks remain
  searchable, and broken symlinks are reported.
- The Mix task returns statuses for console use. Process exit codes are guaranteed
  by the standalone executable.

### Release review fixes

- Treat wildcard characters in the search directory as literal characters when
  expanding include/exclude patterns.
- Preserve literal dollar signs in Make search queries and paths.
