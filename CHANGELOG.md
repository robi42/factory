# Changelog

All notable changes to Factory. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- The approvals ask you in a question dialog in the agent's pane, the planner's for the
  plan and the builder's for the build: Approve, Abort, for the plan also Approve, allow
  protected paths, or a typed note to have it revised, which arrives as typed, with no
  shell in between. Hooks Factory installs when it starts the agent hand your answer to
  the gate, so the agent never relays it, and mark the dialog as open meanwhile, so that
  Factory neither types into it nor takes it for the end of the agent's turn. Factory's
  terminal prompt and the `fy` commands still answer too, `!fy` typed in a pane that shows
  no dialog (keys typed into the dialog go to it), and Factory closes the dialog when they
  do.
- Every answer you give on a task, the planner's questions included, goes into
  `.factory/run/decisions.md`, onto the bead as a comment, and into the pull request's
  description. A planner that starts over reads it before asking again.
- A run that opens a pull request (`--pr`, `FACTORY_PR=1`) checks at its start, before it
  claims a bead, that origin takes a push without a prompt, with a dry-run push that sends
  nothing. A missing credential or write access stops the run there, with git's error,
  instead of at the push after the work.

### Changed
- The planner asks its questions in its own question dialog, with options where they
  help, instead of through `questions.md` and Factory's terminal. A question waits as long
  as you need: a wait on your input no longer times out, and each new question gets a
  toast. A dismissed question gets the planner to plan with stated assumptions.
- Factory's startup-dialog settler leaves question dialogs alone, whatever their options
  say.

### Fixed
- A run no longer dies when an agent starts on its prompt later than Herdr's five seconds,
  as Codex did on a long plan review ("still working after startup"): Factory sees the
  turn begin and waits it out, instead of dying or sending the prompt twice.

### Removed
- `factory answer` and the questions relay (`questions.md`, `answers.md`, the questions
  prompt in Factory's terminal): the planner asks in its dialog.

## [0.1.11] - 2026-10-05

### Changed
- A note at plan approval goes through a plan review round of its own: the planner
  revises, Codex and the builder check the revision against your note and their last
  notes, and the planner revises once more if either objects, adding that to its summary
  of what changed. Then the plan comes back to you with that round's verdicts, past
  `FACTORY_PLAN_ROUNDS` if need be. It used to reach the planner alone, so after a last
  round that ended in REVISE no reviewer saw the plan again. While the round runs, and
  while Factory's terminal takes a note, `factory approve`, `reject` and `abort` say so
  instead of taking an answer that would be dropped or applied to a plan still changing.
- `factory reject` refuses an empty note, as `answer` refuses empty answers.
- In a terminal, the approval prompts colour their keys by what they do: approving green,
  revising yellow, aborting red.

### Fixed
- Factory no longer prompts an agent in the middle of a turn. Claude Code replies to a
  `!fy` command typed in its pane, and herdr's wait, which does not track turns, could
  match the end of that reply instead, so the next step, a plan review round or the gate,
  could start before the agent had acted on the note. Factory now lets the turn end
  first, and after an approval, a note or answers that came by file it pauses a few
  seconds for such a reply to start.
- A note or answers typed after `!fy reject` or `!fy answer` go through the pane's shell
  first: unquoted, an apostrophe or a parenthesis broke the command, and backticks ran as
  one. The agents, `factory help`, the hints and the README now show them in single quotes,
  which keep everything as typed, and the agents and the README say how to write an
  apostrophe there.
- In a run without a terminal, an approval that comes back after a note says again where
  to answer.
- An uncommitted edit under `.factory/`, such as to the gate, went unnoticed: the
  planner's hands-off check and the builder's guardrails looked only outside it, while the
  gate that ran was the edited copy. Only Factory's own `.factory/run/` is left out now.
- The planner's hands-off check looks at what each of its turns changed. Files you add or
  change in the worktree while its questions or the plan approval wait, or before a rerun,
  were blamed on it, and it was told to discard them or the run died.
- Planning afresh (`--fresh`, or a rerun after planning was cut off) no longer starts from
  the last run's plan.md, which let the planner's questions go unasked and a turn that
  wrote nothing go unnoticed while the old plan was reviewed and offered as the new one.
- The protected-path waiver (`p`, or `approve --allow-protected`) goes with the plan
  approval it came with: when that approval does not stand, because the plan is shown
  again or planned afresh, neither does the waiver.

## [0.1.10] - 2026-10-04

### Added
- `factory abort`, the gate's `b` from anywhere.
- In a task's worktree, `factory approve`, `reject`, `abort` and `answer` need no repo and
  bead: the task is the one there. Typed after a `!` in an agent's pane, which Claude Code
  and Codex run as a shell command rather than through the agent, they answer a gate from
  the pane you are in: `!fy approve`, `!fy reject <note>`. The planner and the builder
  point you to them when you tell them a decision in words, and never run them.
- Extras: `cargo-sccache/sccache`, a compiler wrapper for Cargo builds in task worktrees.
  It runs sccache and shares between worktrees only the dependencies, which no task can
  edit; in Codex's sandbox or without sccache installed it runs the compiler alone.
  `extras/cargo-sccache/README.md` has the setup, what is shared, and why a shared
  `target/` is no way to the same saving.

### Changed
- The build approval prompt shows the commits and the diff stat in git's colours, the
  stat fitted to the terminal's width.
- `factory approve`, `reject` and `abort` refuse when no run waits at an approval for the
  task, and `answer` when no questions wait, instead of leaving a file the next prompt
  clears; a gate or the planner's questions name themselves and the run in
  `.factory/run/waiting` while they wait. `--allow-protected` is refused at the build's
  approval. There it used to waive the protected-path check for the rest of the task, the
  rebase and the Copilot rounds included, and the pull request recorded the waiver.
- `factory reject` and `answer` take a note or answers of several words without quotes,
  as typed in a pane; both used to refuse a second word.
- Agents reply with what they write, so their panes show it: the planner its plan (or,
  after your note, what it changed), the reviewers their reviews, the builder its
  pushback. A review now ends with its step and round, such as `PLAN REVIEW round 1` or
  `CODE REVIEW round 2`, above the verdict line.

### Fixed
- A note at build approval in the last round got no round of its own: the builder took
  it, and the run ended unchecked as needing a human. It now gets its round, one past
  `FACTORY_ROUNDS` if need be.

## [0.1.9] - 2026-10-04

### Added
- `FACTORY_PLAN_ROUNDS`, 2 by default. After a revision, the plan goes back to Codex and
  the builder, who check it against their notes, until both approve or the rounds run out;
  an objection in the last round still gets its revision, with a warning that it goes on
  unreviewed. The plan used to go on after one revision that nobody checked.

### Changed
- The plan approval prompt shows the last plan review's verdicts, whether the plan changed
  since, and where its notes are. Plan reviews are written per round, to
  `plan-review-N.md` (Codex) and `plan-review-N-build.md` (builder).

### Fixed
- `factory clean` removed a task still in planning and closed its bead as merged. A branch
  with no commits of its own is an ancestor of the base from the start, and ancestry alone
  counted as merged, so the worktree went, and the plan with it. Ancestry now counts only
  once the task's bead is closed, as Factory closes it at build approval; a merged pull
  request still counts on its own. `clean` says which task it keeps and why.
- The guardrails' note that the protected-path check is waived now carries the `[factory]`
  tag like every other line Factory prints.
- Codex never took Factory's trust for the reviewer's repo: it splits a `-c` key at its
  dots, quotes and all, so the quoted repo path never matched. In a repo Codex had not
  trusted yet, the reviewer met the trust dialog, Factory accepted it, and Codex saved the
  trust in `~/.codex/config.toml` for good. Factory now passes it as an inline table.

## [0.1.8] - 2026-10-03

### Changed
- `factory tasks` lists the open tasks in the order `factory next` takes them: a task
  after the ones that block it, else in progress first, then by priority, the newest
  first as `bd ready` has it; blocked and deferred tasks come last. With arguments such
  as `--all` it is `bd list` as before.
- `factory init` gives the beads a short prefix from the repo's name: the initials of
  several words (AllesBuien `ab`), else a word's first and last letter (Blik `bk`).
  `--prefix` still picks another. Under a directory with its own `.beads`, such as a Gas
  Town, a repo used to inherit its prefix (`hq`); `bd rename-prefix` changes one.
- The planner's effort defaults to `max`, up from `xhigh`: it runs once per task, and its
  plan steers every round after it. `FACTORY_PLAN_EFFORT` still overrides it; the builder
  and the reviewer stay at `xhigh`.

### Fixed
- Seven of the twenty default guardrail patterns were never applied: they begin with `#`,
  and the list's comment filter dropped them. `noqa`, `type: ignore`, `nosec`,
  `shellcheck disable`, `pragma: no cover` and Rust's `#[allow(` and `#[ignore]` on added
  lines now fail the branch as the README says. The list now writes their leading hash as
  `[#]`. A copy of the old list, as a repo's `.factory/guardrails.txt` or a file set in
  `FACTORY_GUARDRAILS`, still skips them until it gets the same edit, on the lines that
  `grep -n '^#[^[:space:]]'` prints.
- `factory add` without a title lost the first description line whenever the title was
  on the first line, which is what its editor template and its stdin prompt ask for.
- The Copilot loop never saw an approval. Copilot's review now opens with an overview
  header above its `###` verdict, and Factory took the first line as the verdict, so a
  review that recommended approval with nits went back to the builder for another pushed
  round, up to `FACTORY_COPILOT_ROUNDS`, and the bead noted the header. Factory now takes
  the first `###` heading as the verdict and the sentence under it as the summary.
- Codex 0.160 asks "Trust this folder?" in a folder it has not trusted yet, and the run
  stopped there. Factory accepts it as it did the old trust dialog.
- A startup dialog Factory cannot clear goes to you once, and the run waits for your
  answer, up to `FACTORY_TURN_TIMEOUT_MS`. It used to warn six times in 18 seconds and
  then stop the run.

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

[Unreleased]: https://github.com/robi42/factory/compare/v0.1.11...HEAD
[0.1.11]: https://github.com/robi42/factory/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/robi42/factory/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/robi42/factory/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/robi42/factory/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/robi42/factory/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/robi42/factory/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/robi42/factory/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/robi42/factory/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/robi42/factory/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/robi42/factory/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/robi42/factory/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/robi42/factory/releases/tag/v0.1.0
