# Factory

A simple, lean software factory on Herdr: one Bash script (`factory`) that drives Claude
Code and Codex sessions in Herdr panes, with Beads for tasks and mechanical guardrails.

## Run and verify

- Gate: `just ci` must pass (shfmt, shellcheck, our own guardrails, codespell, bats).
  Tools come from `mise.toml`; run `mise install` once, then `mise exec -- just ci`.
- A change to the pipeline deserves a live smoke run against a small fixture repo of your
  own (a git repo with `bd init` and a gate; `.smoke/` is gitignored for that purpose):
  `mise exec -- ./factory run --auto .smoke/<repo> "<task>"`, with Herdr running.

## Layout

- `factory`: the whole CLI, sectioned by comment banners; read `run_task` and the phases
  above it first.
- `guardrails.txt`: forbidden-pattern list applied to task branches, and to this repo.
- `test/factory.bats`: unit tests for the pure functions; Herdr and Beads are stubbed.
- `extras/`: things useful next to Factory but not part of it.

## Rules that the code cannot tell you

- Commits follow Conventional Commits.
- Never add a suppression comment; fix the finding or restructure so the checker agrees.
- Keep prompts short and mechanical checks strict; a new step must earn its place on a
  real task before it stays.
