# Changelog

All notable changes to Factory. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.7] - 2026-09-25

### Added
- Effort knobs `FACTORY_PLAN_EFFORT`, `FACTORY_BUILD_EFFORT` and `FACTORY_REVIEW_EFFORT`,
  all `xhigh` by default. They override the effort in your Claude Code and Codex settings;
  a Codex config without one ran GPT 6 Astra at its default of `low`.

### Changed
- The planner replies with its questions instead of QUESTIONS, so they read in its pane as
  well as in Factory's terminal.
- The builder defaults to Opus 5.5 (`claude-opus-5-5`); `FACTORY_BUILD_MODEL` still
  overrides it.

### Fixed
- After an interrupt, Factory names the command that resumes: `factory run` with the bead
  id. Rerunning `next` or `queue` claims another bead, and rerunning with the title files
  a new one.
- A run that used up its rounds reported one round more than it had, and a run approved
  but handed over because the gate log or guardrails failed at the end said "not
  approved". Both now say the run needs a human, with the right round count.
- `factory answer` refuses more than one answer argument instead of sending only the first
  word of an unquoted answer, and `factory approve` refuses a third argument other than
  `--allow-protected` instead of approving without the waiver.
- `factory pr` checks for Herdr and `factory status` for jq up front, and a repo's
  `.factory/env` can no longer set `FACTORY_PID`.
- Prompts: the answers prompt no longer points at `questions.md` after Factory removed it,
  the retry for a missing review file asks for the verdict line instead of DONE, and the
  builder hears that only `.factory/run/` is ignored by git, not all of `.factory/`.
- A review from a deleted account on the pull request no longer hides Copilot's review, so
  the wait for it no longer runs out after Copilot has reviewed.

## [0.1.6] - 2026-09-18

### Changed
- Reviewers reply with their verdict line instead of DONE, so each reviewing pane shows
  APPROVE or REVISE at a glance.
- A run that stops at plan approval leaves a `reviewed` marker, so the rerun comes straight
  back to the approval prompt with the reviewed plan instead of planning and reviewing
  again.

## [0.1.5] - 2026-09-18

### Added
- With `glow` on the PATH, the plan and the planner's questions are rendered as Markdown at
  the approval prompts.
- After a note at plan approval, the planner writes what it changed and why to
  `plan-changes.md`, and the next prompt shows that below the revised plan.

### Fixed
- `factory check` exited 1 after a green gate and guardrails, and left its gate log in the
  temp directory: the exit trap read a local variable that was gone by then.
- A failed push in `factory pr` or at the end of a run was ignored: the open pull request
  was reused and the task closed as done while the branch on GitHub still held the old
  commits. The run now stops with an error.
- A failed push of a Copilot round's fixes was ignored too, so the next round waited the
  whole Copilot timeout for a review of a commit GitHub never saw. The loop now ends with
  a note.
- `factory add` with an empty task on stdin exited silently and left its temp file behind
  instead of saying "empty title, nothing filed".
- In `factory queue`, an error inside a command substitution (no gate found, a pane that
  failed to open, a pull request that failed to open) ended only that subshell and the run
  carried on with an empty value, because Bash ignores errexit under the queue's `||`.
  A `die` in a subshell now signals the main shell, which exits 1 as it does elsewhere.
- A Copilot round the builder answered without changing anything requested another review
  of the same commit and got the same comments back, round after round. The loop now posts
  the answers, resolves the threads, and ends with a note.
- `n` at an approval prompt aborted the run, a hidden alias for "no" next to `y` for
  "yes". Only the keys the prompt shows mean anything now; any other key, and an empty
  note, ask again in place instead of re-rendering the plan and toasting.

### Changed
- `factory help` lists every knob, `FACTORY_GUARDRAILS`, `FACTORY_POLL_SECONDS`,
  `FACTORY_COPILOT_WAIT_S` and `FACTORY_FRESH` included; the usage lines of `run`, `next`
  and `queue` name all four flags; the messages that point at `clean` say `factory`, not
  the `fy` alias.

## [0.1.4] - 2026-09-17

### Added
- A repo can commit its own knob defaults in `.factory/env`, one `FACTORY_NAME=value` per
  line. Parsed, never sourced; the environment and flags still win; the file is protected
  from the agents like the gate.

### Fixed
- The guardrails and the diffs shown to reviewers measured the branch against the local
  base branch even after the pull request rebase had put it on origin's, so a stale local
  `main` blamed the branch for what the upstream had added (a protected workflow file, in
  practice): the run died right after the rebase, or a Copilot round stopped before pushing
  the builder's fix. The branch is now measured against the local base branch or origin's
  copy, whichever it forked from later.
- A guard failure after a rebase or a Copilot round now prints the violations instead of
  only saying that the guardrails failed.
- Copilot comments were matched on the commit GitHub currently attaches them to, which
  moves along with the branch head while the commented line survives. So a comment the
  builder had answered without changing the line was handed to it again in the next round,
  and its thread was never resolved after the push. Comments are now matched on the commit
  they were made on.
- The script exits right after its main function, so a `factory` file rewritten in place
  during a run (an editor, a repo update) can no longer make Bash execute a stray line from
  the changed file once the run is done.

### Changed
- The turn timeout no longer kills a run whose agent is still working, as on a long
  build; it toasts you once and keeps waiting. Only a turn that is not working when the
  timeout runs out fails the run.

## [0.1.3] - 2026-09-14

### Added
- A human gate on the build: once the gate, guardrails and both reviewers approve, Factory
  shows the branch's commits and diff stat and waits for `a`, `r` with a note for one more
  round, or `b`; `fy approve` and `fy reject` work there too.

### Changed
- `FACTORY_PLAN_APPROVAL` is now `FACTORY_APPROVAL`, since `--auto` skips both human gates.

## [0.1.2] - 2026-09-13

### Added
- An interrupted run (Ctrl-C, kill) leaves a note on the bead saying at which step it
  stopped; rerunning the same command resumes.
- A rerun that reaches the pull request stage reuses the branch's open pull request instead
  of failing to create a second one.
- Reruns resume after the last completed milestone, an approved plan or an approved build,
  instead of replanning; `--fresh` starts over.

### Fixed
- Agent startup no longer fails when a pane's line editor swallows the setup command's
  Enter and sits in multiline mode: the setup is verified and retried, and a startup
  timeout clears the pane's input line before trying again.

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

[Unreleased]: https://github.com/robi42/factory/compare/v0.1.7...HEAD
[0.1.7]: https://github.com/robi42/factory/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/robi42/factory/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/robi42/factory/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/robi42/factory/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/robi42/factory/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/robi42/factory/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/robi42/factory/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/robi42/factory/releases/tag/v0.1.0
