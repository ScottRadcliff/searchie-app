# v0.1.0 release readiness

Status: ready for review and tagging after the release-pass changes are committed.
This pass did not create a commit, tag, remote PR, or published release.

## Review findings resolved

1. **Glob filters could silently miss matches under directory names containing
   wildcard characters.** Include/exclude expansion interpreted the entire path
   as a glob. The directory prefix is now escaped independently of the user
   pattern. Regression coverage exercises `[`, `{`, `*`, and `?` in the root,
   directory exclusion, and individual-file searches.
2. **Make changed literal dollar signs in queries and paths.** For example,
   `QUERY='price=$5.00'` became `price=.00`, and `$draft.txt` became `raft.txt`.
   Search arguments are now captured without recursive Make expansion, then
   exported as environment values. Probes verified dollar signs, Make-like syntax,
   spaces, and literal backticks.

The API review also added a typed scan result and optional context metadata to
the match type. Context-window trimming now uses the existing line counter,
avoiding a queue-length traversal on every input line.

## Verification

This pass used host Elixir 1.16.2 and Erlang/OTP 26:

- `mix format` and `git diff --check` completed successfully.
- `mix test`: **51 tests, 0 failures**. This includes escript subprocess tests,
  partial failures, symlink cycles, context boundaries, invalid UTF-8, and a
  100,000-line streaming scan.
- `MIX_ENV=prod mix compile --warnings-as-errors` passed.
- `MIX_ENV=prod mix escript.build` produced the ignored `./searchie` executable.
- **19 standalone QA cases** checked sample results, glob filters, mixed-case and
  regex searches, option precedence, legacy modifiers, counts, help, diagnostics,
  exit codes, context, and partial failures. A copy of the executable ran from a
  temporary directory outside the repository.
- Both Elixir code blocks from [manual QA](manual-qa.md) executed successfully.
- All three documented terminal searches passed, as did a separate literal-dollar
  search against the notes sample.
- A Make command probe verified argument export without starting Docker.

Docker builds and unprivileged permission-denied checks were verified during
milestone 3, as recorded in [the plan](v0.1-plan.md). Docker was not rerun during
this release pass; the current code was verified on the host runtime above.

## API and behavior reviewed

- `filter/3` collects matches and returns `errors` alongside them.
- `scan/6` reduces matches incrementally and can attach bounded context windows.
- Partial filesystem failures retain matches, emit diagnostics, and produce
  standalone status 2. No matches produce status 1; matches and help produce 0.
- Console adapters return statuses without halting IEx. Use the executable for
  shell exit-code guarantees.
- Empty files and trailing newlines follow physical-line semantics. Original
  text and casing are preserved in matching lines.

Known limits remain documented: UTF-8 input, compatible OTP required for the
escript, path/error metadata retained in memory, overlapping context blocks,
skipped nested directory symlinks, and no `.gitignore` compatibility or Hex release.
These are accepted v0.1 boundaries; no unresolved release-blocking findings remain
from this pass.

## Release handoff

1. Review and commit the release-pass changes.
2. Use [the PR description](pr-description.md) for a review handoff if needed.
3. Rebuild the intended artifact with `MIX_ENV=prod mix escript.build` (or use
   Docker's `make package`) and retain the compatible OTP runtime requirement.
4. Tag `v0.1.0` when the review is accepted.

See [the changelog](../CHANGELOG.md) for release notes and compatibility changes.
