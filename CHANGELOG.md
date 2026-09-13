# Changelog

All notable changes to Factory. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- An interrupted run (Ctrl-C, kill) leaves a note on the bead saying at which step it
  stopped; rerunning the same command resumes.
- A rerun that reaches the pull request stage reuses the branch's open pull request instead
  of failing to create a second one.
- Reruns resume after the last completed milestone, an approved plan or an approved build,
  instead of replanning; `--fresh` starts over.

## [0.1.1] - 2026-09-13

### Added
- When a Copilot review has no inline comments, its summary sentence is recorded on the bead
  next to the verdict, so the note says what to look at.

### Fixed
- Docs work from a fresh clone: no machine-specific paths, no reference to the gitignored
  fixture repo.

## [0.1.0] - 2026-09-13

First tagged state.

### Added
- One Bash CLI, `factory` (alias `fy`), driving Claude Code and Codex sessions in Herdr panes
  per task: planner (Fable 5.1), builder (Opus 5), reviewer (GPT 6 Astra), each task in its
  own git worktree and Herdr workspace.
- Pipeline: plan with an optional interview, dual plan review by Codex and the builder, human
  approval, build, gate, guardrails, dual code review by Codex and the planner, revise loop,
  memories, bead close, toast.
- Human gates from the terminal or from anywhere: `fy approve`, `fy reject`, `fy answer`, with
  a one-task waiver for protected paths.
- Gate resolution: `FACTORY_GATE`, `.factory/gate`, or the repo's own convention (`bin/test`,
  `just ci`, Makefile targets, language defaults); `fy init` detects and writes it.
- Guardrails: forbidden added lines (suppressions, skipped tests, swallowed errors; per-repo
  override in `.factory/guardrails.txt`), tests must change with code, no build artifacts, a
  clean committed tree, protected paths, a planner that leaves code untouched.
- Beads as task queue and memory: `fy add` (also from `$EDITOR`), `fy tasks`, `fy next` with
  atomic claims, `fy queue`, `fy sync`; the database is pushed to the repo's Git remote after
  tasks and adds.
- Pull requests: `--pr` or `fy pr` rebases onto the base (the builder resolves conflicts, gate
  and guardrails rerun), pushes with force-with-lease, opens the PR with a short body, then
  requests a GitHub Copilot review and acts on its inline comments round by round, posting one
  summary comment and resolving addressed threads.
- Robustness: startup dialogs of Claude Code and Codex cleared automatically, blocked agents
  settled before the human is asked, heartbeats during long waits and gate runs, reruns adopt
  a task's live agents, unclaimable beads fail loudly.
- Housekeeping: `fy clean` removes workspaces, worktrees and branches of merged tasks (squash
  merges included) and prunes stale worktree entries; `fy status` with coloured states;
  `fy doctor` including the login-shell check for `bd`.
- Branches named `factory/<bead-id>-<title-slug>`, checkouts as `factory-<bead-id>`; planner
  and builder prompt lines coloured purple and cyan.
- Extras: a `metals-lsp` Claude Code plugin for Scala in a small local marketplace.
- Repo: MIT license, CI on GitHub Actions with pinned action SHAs and Dependabot, `just ci`
  applying shfmt, shellcheck, the guardrails, codespell and bats to Factory itself.

[Unreleased]: https://github.com/robi42/factory/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/robi42/factory/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/robi42/factory/releases/tag/v0.1.0
