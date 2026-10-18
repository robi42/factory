# Factory

A simple, lean software factory on Herdr: one Bash script (`factory`) that drives Claude
Code and Codex sessions in Herdr panes, with Beads for tasks and mechanical guardrails.

## Run and verify

- Gate: `just ci` must pass (shfmt, shellcheck, bash -n, our own guardrails, codespell,
  bats). Tools come from `mise.toml`; run `mise install` once, then `mise exec -- just ci`.
- A change to the pipeline deserves a live smoke run against a small fixture repo of your
  own (a git repo with `bd init` and a gate; `.smoke/` is gitignored for that purpose):
  `mise exec -- ./factory run --auto .smoke/<repo> "<task>"`, with Herdr running.

## Layout

- `factory`: the whole CLI, sectioned by comment banners; read `run_task` and the phases
  above it first.
- `guardrails.txt`: forbidden-pattern list applied to task branches, and to this repo.
- `test/factory.bats`: unit tests for the functions and flows; Herdr and Beads are stubbed.
- `test/cargo-sccache.bats`: tests for the compiler wrapper in `extras/cargo-sccache`.
- `extras/`: things useful next to Factory but not part of it.

## Rules that the code cannot tell you

- Commits follow Conventional Commits.
- Never add a suppression comment; fix the finding or restructure so the checker agrees.
- Keep prompts short and mechanical checks strict; a new step must earn its place on a
  real task before it stays.
- The guardrails catch an agent's honest mistakes and lazy shortcuts, and must hold
  whatever the user's own setup does to git's output. They are not containment: an agent
  set on evading them runs as the user. A new check needs a real failure or a likely
  honest mistake behind it; a trick only such an agent would use is listed for the user,
  not closed in code.
- The README says in a line what a check does; how it works lives in the code's comments
  and the commit message. A CHANGELOG entry is a few lines.
- A user-visible change gets an entry under `[Unreleased]` in `CHANGELOG.md`: what was
  wrong, what happens now. A release bumps `FACTORY_VERSION` in `factory`.
