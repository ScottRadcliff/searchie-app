### Description

Complete the Searchie v0.1 release review by fixing two cases that silently changed
search results: glob filters interpreted wildcard characters in the search root,
and Make expanded dollar signs in search arguments. Escape only the directory
prefix during glob expansion and preserve Make arguments as literal environment
values.

Add regression coverage, clarify scan/context API types, and avoid traversing the
context queue just to determine its size on each line. Include release notes and
a readiness report covering the existing streaming CLI and standalone packaging.

Validation completed on Elixir 1.16.2 / OTP 26: 51 tests passed, production
compilation passed with warnings treated as errors, and standalone and documented
console QA passed. Standalone execution requires compatible Erlang/OTP; Docker
development remains available through the existing Makefile.

### QA Steps

1. Run `mix format --check-formatted` and `mix test`, or use `make check` in Docker.
2. Run `MIX_ENV=prod mix compile --warnings-as-errors` and
   `MIX_ENV=prod mix escript.build` (or `make package`).
3. Run `./searchie samples/logs/app.log error -i -n --color`. Expect four matching
   lines numbered 2, 4, 6, and 7, and exit code 0.
4. Run `./searchie samples nothing-matches-this --count`. Expect stdout `0` and
   exit code 1. Run `./searchie samples/missing.txt error`; expect a diagnostic
   on stderr and exit code 2. Check each code immediately with `echo $?`.
5. Run `make search SEARCH_PATH='samples/notes/release notes.txt' QUERY='price=$5.00'`.
   Expect the literal punctuation line; the dollar sign must remain in the query.
6. Review the wildcard-directory regression test in `test/searchie_stream_test.exs`
   and follow `docs/manual-qa.md` for context, exclusions, Unicode, and IEx checks.
7. Copy the generated executable outside the repository and search an absolute
   sample path. It should work without a project checkout or Mix invocation.

### Screenshot/Video

N/A

### JIRA Ticket

N/A

### Ansible Changes

N/A
