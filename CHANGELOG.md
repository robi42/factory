# Changelog

All notable changes to Factory. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Factory installs Beads 1.3.2, up from 1.2.2. bd 1.3 migrates a repo's task database on its
  first command there, and bd 1.2 refuses the database after that. Upgrade bd in every clone
  of a repo at once, after a last `bd dolt push` with the old one where the database syncs to
  a remote, then run `bd recompute-blocked` once in each repo, as bd's release notes ask.
- `factory next` and `queue` take the oldest of equally urgent tasks first, as bd 1.3's
  `bd ready` orders them, and `factory tasks` lists them that way.

### Fixed
- `factory add` names the bead it filed; the quiet `bd create` it ran says nothing from bd
  1.3 on.
- A bead bd will not close, one with an open blocker or, from bd 1.3 on, an open child, no
  longer stops a run after your approval, nor `factory clean`: Factory says that bd kept it
  open, and how to close it.

## [0.2.1] - 2026-10-29

### Fixed
- The tests guardrail took a repo's own `test.sh` or `tests.py` for no test file: a task on
  such a repo failed it until the builder moved the tests, which the reviewers objected
  to, and was handed over. A file named `test` or `tests`, or starting with `test_`, counts
  as a test now, whatever its language.

## [0.2.0] - 2026-10-24

Upgrading from 0.1.x: finish a task 0.1.x started before you upgrade, or rerun it with
`--fresh` (a plain rerun plans it again from scratch), and upgrade between runs: a run
that waits for your approval takes your answer where its own Factory looks for it.
`factory answer` and `factory sync` are gone; the planner asks its questions in a dialog
in its pane. The guardrails stop more than before: a change to any file under `.factory/`
but `.factory/run/`, or a symlink to a directory, the worktree's top included, needs
your waiver at plan approval, and a symlink to a place the branch does not hold or an
ignored file at a protected path fails them whatever you waive. Factory's
`guardrails.txt` refuses a submodule the branch adds or points at another
commit; a repo with its own `.factory/guardrails.txt` needs Factory's `+Subproject commit`
line in it to refuse them too. A sparse checkout, or a worktree on a filesystem without
executable bits, reads as changed, so a task there stops before any agent works. A knob's
value Factory cannot read, or a name in `.factory/env` that is no knob (see Removed),
stops the command. `factory clean --force` drops one task now, named by its bead id.
`factory next` and `queue` need flock (util-linux). The agents may no longer run
`git push`, `gh` or Factory itself.

### Added
- The approvals ask you in a question dialog in the agent's pane: Approve, Abort, for the
  plan also Approve, allow protected paths, or a note to have it revised, which hooks
  Factory gives the agent hand to the run. Factory's terminal and `fy` still answer too.
- Every answer you give on a task, the planner's questions included, goes into Factory's
  state for the task, onto the bead and into the pull request's description; a planner
  that starts over reads it, as `.factory/run/decisions.md`, before asking again.
- A run that opens a pull request (`--pr`, `FACTORY_PR=1`) checks at its start that origin
  takes a push without a prompt, before any bead is claimed, and holds the task's base as
  a branch, before `factory run` claims its bead (`next` and `queue` have claimed theirs
  by then), rather than failing at the push after the work.
- A rerun picks up a written plan at its next review round instead of planning again, so
  a run that stops during the plan's review keeps the planner's work.
- From the second build round on, the reviewers check what changed since their last
  notes, with the builder's answer to them (`response-N.md`, which nothing read) and
  your note on the build, as the plan's reviewers already did.
- `factory doctor` also checks that `fy` resolves from a login shell, as `!fy` in a pane
  needs, that git is 2.31 or newer, and that flock is there; gh, which only pull requests
  need, shows as absent without failing it.
- The plan ends saying whether the build must change protected paths, as
  `Protected paths: none` or which, so you know at approval whether to allow them; Factory
  warns when the plan does not say.
- `factory stats <repo>` shows how the repo's tasks went: rounds, gate and guardrail
  failures, objections, your notes, time and tokens, with means per Factory version. Each
  run records its events in `events.jsonl` beside the tasks' state.
- `extras/factory-user/`: a recipe for running Factory, Herdr and the agents as a user of
  their own, which holds only its clones, a GitHub token for them and the agents' logins,
  so that an `--auto` run reaches nothing else of yours.
- The Herdr tab with a task's agents is named after the task's bead id, as `bk-0b1`,
  where Herdr numbered it; a name you gave it stays.
- `FACTORY_WORKSPACE_SCRIPT`: a command of yours that Factory runs once in each workspace
  it makes for a task, when the agents are up, to open tabs of your own beside theirs.
  `extras/workspace-tabs/` opens glow on the plan and the reviews, hunk, tig, nvim and a
  shell to try the build in.

### Changed
- The planner asks its questions in its own question dialog, with options where they
  help, instead of through `questions.md` and Factory's terminal. A question waits as long
  as you need, with a toast, and Factory never answers one for you.
- All of `.factory/` is protected now, but Factory's own `.factory/run/`: a task that
  changes any file there needs your waiver at plan approval. Only the gate, `protected`,
  `guardrails.txt` and `env` were, though the guardrails read no line under `.factory/`.
- The agents may not run `git push`, `gh` or Factory itself: the settings Factory starts
  them with deny them, so no agent pushes unchecked commits, answers your approval or
  merges its own pull request. Your own `!` commands in a pane run as typed.
- In Rust, whose unit tests live in the file they test, a `#[test]` or an assertion added
  to a changed `.rs` file counts for the tests-required check.
- Each refusal of the guardrails, and each stop, says what to do next.
- `factory pr` refuses `--auto` and `--fresh`, which do nothing there.
- `factory tasks`, `approve`, `reject` and `abort` read no knob, and no longer load the
  repo's `.factory/env` or say which knobs it set.
- `factory pr` checks after Copilot's rounds, as a run does, that origin's copy of the
  branch is the commit it pushed, and names what the worktree holds that the pull request
  lacks.
- Every command takes any directory of a repo for the repo: `factory run`, `pr`, `init`,
  `next`, `queue`, `add` and `tasks` took only its top.
- The agents' prompts tell them how you approve only where Factory asks you, not under
  `--auto`, where those commands refuse.
- Factory needs Bash 4.4 or newer, as the README now says, where it said Bash 4: an older
  Bash takes an empty list for an unset variable. On one, Factory stops at its start and
  says which Bash it needs.
- A file you add or change while one of the planner's questions is open counts as the
  planner's, which is asked to revert it, as its questions now wait inside its turn; what
  you change while an approval waits, or before a rerun, still does not.
- The planner and the builder no longer say how to write an apostrophe in a `!fy reject`
  note, which their dialog takes as typed; the README still does.
- A rerun ran the gate again on a commit it had already passed on, 20 to 40 minutes in
  Blik, as did `factory pr` after the guardrails failed. Factory skips it now, and says
  so, on the same commit and command when the worktree had no file changed or added, nor
  an ignored one at a protected path, at the pass and has none now. The first rerun
  after upgrading runs it once: only passes this version records count.
- Factory keeps your answers, the waiver and where a rerun resumes in its own state for
  the task, under `${XDG_STATE_HOME:-~/.local/state}/factory/tasks/`, not in the run dir,
  which the agents write.
- An agent that pasted its plan or review into its reply could put it in a code block,
  which Claude Code shows unformatted, headings and lists as raw Markdown. The prompts ask
  for it as Markdown, not in a code block.
- A plan gets three review rounds by default, up from two (`FACTORY_PLAN_ROUNDS`). After
  two, a plan still objected to came to you with its last revision unreviewed, and a note
  was how to get another round, as on two of three tasks in Blik.
- A note of yours at build approval got one round, and the reviewers often object to what
  a note changed: late in the rounds that left none for the fix, and the task was handed
  over, as twice on one task in Blik. A note starts the rounds over now, up to
  `FACTORY_ROUNDS` more after it.

### Removed
- **Breaking:** `factory answer` (`!fy answer` in a pane) and the questions relay
  (`questions.md`, `answers.md` and the terminal's questions prompt) are gone; the planner
  asks in its own question dialog instead.
- Four knobs nobody set are fixed values now, ignored when exported and refused in
  `.factory/env` unless exported too: `FACTORY_POLL_SECONDS`, `FACTORY_TURN_TIMEOUT_MS`,
  `FACTORY_COPILOT_WAIT_S` and `FACTORY_GUARDRAILS` (the list beside the script).
- `factory sync` is gone: it pushed the Beads database even with `FACTORY_BD_PUSH=0`. By
  hand it is `bd -C <repo> dolt pull && bd -C <repo> dolt push`; on a remote that holds no
  beads yet the pull fails, so push alone there.

### Fixed
- A build whose plan you approved with protected paths allowed was still told to change
  none, and the waiver let any protected path through. It is told to change those the
  plan's `Protected paths:` line names now, and the guardrails hold it to them.
- The build's reviewers ran the gate again, which Factory had just passed on that commit,
  and on a long gate the planner ended its review with the gate still running in the
  worktree. They are told now that the gate passed and where its log is.
- A builder that could not fix what the guardrails found, as a commit a locked 1Password
  would not sign, had the gate run again until the rounds ran out. A turn that changes
  nothing they check now hands the task over at once, naming the checks that failed.
- A task started from your local base where origin's had moved on: the planner planned on
  code the branch lacked, and the unbuilt branch was gated. It starts from origin's base
  where yours is only behind now, and a first build turn changing nothing hands it over.
- A Copilot round whose fixes did not reach the pull request closed the task as done, as
  on Blik's bk-9tt with 1Password locked. Factory hands the task over now, naming what the
  pull request lacks and `factory pr`, which checks and pushes it once it is committed.
- `factory next` and `queue` took up a task whose blocker's pull request was still open,
  as Blik's bk-cxs during bk-9tt's, so it started without that code. Such a task waits
  for the merge now: `next` skips it, naming the pull request, and `run` stops on it.
- A task that started on a checkout git reads as changed failed every check after hours of
  work; it now stops before any agent works.
- `FACTORY_APPROVAL=Ask` skipped both of your approvals, and `FACTORY_PR=true` died
  halfway through a run. Factory now checks the knobs before a bead is claimed, and stops
  on a value it cannot read or a name in `.factory/env` that is no knob.
- A rules file the guardrails could not read, as a copy of the script with no
  `guardrails.txt` beside it, passed every line the branch added; it fails the check now,
  and `factory doctor` reports it.
- The forbidden patterns missed `|| true`, `|| :` and `|| exit 0` before a `;`, a `)` or a
  quote, Rust's `#![allow(...)]`, `#[expect(...)]` and `#[ignore = "reason"]`, and Go's
  `t.Skipf` and `t.SkipNow`; they catch them now, but not a closure, as `f(|| true)`.
- The tests-required check counted a deleted test file, or one moved unchanged, as a test
  changed, and a deleted code file, or one moved unchanged, as a change of code. None of
  them counts now: a branch that only deletes or moves files needs no test.
- `factory next` and `factory queue` filed a task of their own, titled with the bead's id,
  for a ready child bead (`ab-x7k.1`, as `bd create --parent` names one), and left the
  child claimed. A child's id is a bead id to Factory now.
- `factory next` on a repo without a gate claimed a ready task and left it in progress,
  and so did `factory queue`. Both now stop before they claim anything.
- `factory clean <repo> --force` without a bead id dropped every task, a live run's too,
  and closed their beads; `--force` needs the bead id now. An unknown flag or a second
  bead id stops the command.
- Copilot's comments were counted by their lines, a builder turn that changed nothing had
  every thread resolved, and past 30 reviews Copilot's latest went unseen. Comments count
  whole now, such a turn ends the loop with a note, and every page of reviews is read.
- A rebase before a pull request that failed for a reason other than conflicts asked the
  builder to resolve conflicts in no file; it stops at once now, with git's error. A
  conflict that rerere resolves goes to the builder to check.
- A herdr error in plain text, such as a refused connection, ended a run without a word
  while it waited for an agent, started one or counted the live ones; it stops the run
  with herdr's message now.
- Ctrl-C ended a run with status 1 instead of 130 when its note on the bead failed. It
  ends with 130 now, and says the note failed.
- `factory pr` ended without a word when bd could not show the bead, as with its database
  locked; it says so now.
- `factory check` deleted the gate's log it pointed you to after a failed gate; the log
  stays now.
- `factory add` with an unquoted title filed its first word; it takes a title and a
  description at most now, and says nothing was filed when your editor exits with an
  error. `factory queue` refuses a max that is no whole number, with which it ran nothing.
- `factory pr`, `factory clean` and a rerun did not find a task's worktree in a path with
  a space.
- A run no longer dies when an agent starts on its prompt later than Herdr's five seconds,
  as Codex did on a long plan review ("still working after startup"): Factory sees the
  turn begin and waits it out, instead of dying or sending the prompt twice.
- An agent start that times out because the pane's shell kept its command line, the line
  editor (ble.sh) stuck in multiline mode, is cleared and tried again, as it used to be:
  Herdr 0.8 reports the timeout under a new code, and the run stopped instead.
- A rerun after a restart of Herdr's server (a reboot, an update) adopted the agents Herdr
  brought back with their resume alone, without their effort, model and permissions; it
  starts them again with Factory's arguments now, their sessions resumed. The reviewer's
  session, which Codex's background server holds for 30 minutes after the Codex Herdr
  restored quits, goes on in a fork of it, its history kept.
- `factory tasks` showed bd's notice that its `--json` output changes in bd 2.0. Factory
  now reads bd's JSON in the envelope bd 2.0 makes its default, which ends the notice and
  keeps the task list, `factory next` and the task lookups working on bd 2.0.
- `factory queue` ran its tasks in one shell with errors ignored, so a pull request that
  failed to open closed the bead as approved. It runs each task as a `factory next` of
  its own now: a task that stops, or needs you, ends there, and the queue goes on.
- `factory next` read a bd error, such as a locked database, as nothing ready, and a repo
  without beads too; it says so now, and `factory queue` ends with the error.
- A review left by an interrupted run passed for the same round's review on a rerun, its
  old verdict counted; each round's reviews are removed before it asks.
- A failed read of Copilot's comments, such as on a rate limit, read as no comments, and
  the review counted as clean. It ends the Copilot loop with a note now.
- Ctrl-C stopped the run but not its gate, which ran on in the worktree beside a rerun's.
  The gate now runs in the foreground, and Ctrl-C stops it with the run.
- Factory searched a working agent's whole screen for the startup dialogs it clears, and
  typed Esc, Enter, `q` or `r` into the agent's turn when the screen only showed such a
  dialog's words, as a run on Factory's own code does. It settles only a blocked agent.
- A task that needed you after its approval, as when the memory turn committed a file,
  said "needs a human" without saying why; the guardrails' reasons now go into the
  message and onto the bead.
- A rerun found only some of a task's agents alive and suggested `factory clean --force`,
  which drops the work. It keeps the live ones now and starts one that is gone, its CLI
  quit as for a switch of accounts, again in its own pane, with a new session.
- A rerun with none of a task's agents alive closed every other pane in the task's
  workspace, tabs of your own too, with what ran in them. It closes only the planner's and
  the reviewer's old panes now, where the shell waits at its prompt.
- A rerun with none of a task's agents alive typed its setup, and Ctrl-C, into whatever
  ran in the builder's pane, an editor of yours say. It stops and says so now.
- A rerun started an agent in whatever directory its pane's shell was in, or stopped with
  "the shell does not run commands". Its setup takes the shell to the worktree now, and
  passes only on a mark of its own, not on one an agent that quit left on screen.
- A Claude agent just started could take `/color` and its Enter as one paste, losing the
  colour or swallowing Factory's next prompt. The command goes in first now, and its Enter
  once the prompt shows it.
- The `extras/cargo-sccache` wrapper printed a write error on a compile's stderr now and
  then, under `mise exec`, which leaves SIGPIPE ignored. It now reads every sccache on the
  PATH before it picks one, so it writes into no closed pipe.
- A rerun took the branch your checkout was on for the task's base, so its pull request
  could go against another branch, or one merged and deleted. A task keeps the base it
  started from now, in Factory's state for it; `--fresh` takes the checkout's anew.
- The rebase before a pull request fell back to your local base when origin's could not be
  fetched, and took commits only your local base held, such as a fix of yours the builder
  merged in, into the pull request unchecked. It stops in both cases now.
- A commit made after the gate, by the memory turn after your approval or a fixup of
  yours, went out unchecked: Factory pushed the branch by name. It pushes the commit the
  gate and the guardrails passed on now, by its id, and checks a newer tip first.
- The guardrails passed a branch whose diff against its base git could not read, as with
  an object missing from the repository, since every check then read nothing. They fail
  it now, with git's error.
- Since 0.1.11 the check for uncommitted changes counted your own untracked `.factory/env`
  in the repo's main checkout, so `factory check` failed there. It is left out there
  again; in a task's worktree it still counts.
- The guardrails skipped a file whose name git quotes, such as `naïve.rs`, or one that
  reads as a pathspec, such as `:(exclude)x.sh`: none of its lines was matched, and it
  counted as neither code, test nor artifact. Such names count like any other now.
- The guardrails skipped an added line that begins with a `+`, such as a suppression in a
  patch file the build applies, along with the `+++` file header; only the headers above
  each hunk are skipped now.
- With a diff tool or colours in your git config, as difftastic's recommended
  `diff.external` or `color.ui=always` set them, or a textconv filter, the guardrails read
  no added line and passed the branch; they read git's plain diff now, whatever it says.
- One line of a repo's `.factory/guardrails.txt` that grep could not read switched off
  every forbidden pattern: the branch passed whatever it added. Such a line now fails the
  guardrails, which name the file and the line.
- A renamed file read as added in full, so moving a module that already held a
  suppression failed the branch. A renamed file counts only the lines it changed; a copy's
  lines count in full.
- A NUL byte past a text file's first 8000 bytes, which git still shows as text, hid the
  file's lines from the guardrails, as grep stops printing lines at one; they are read now.
- A committed build artifact slipped past the build-artifact check when git read it as a
  rename of a deleted file of like content. A rename no longer hides one.
- A planner's commit passed the check that planning leaves the code untouched, which read
  only uncommitted changes. A planner turn that commits or checks out now stops the run.
- A line of `.factory/protected` that git cannot read as a pathspec, such as `:(bogus)x`,
  made git fail in both checks of protected paths, which then read no path and passed;
  only git's own error reached the terminal. The guardrails now fail and say which line.
- A submodule the branch added or pointed at another commit brought in files no diff
  showed. Factory's `guardrails.txt` refuses its `+Subproject commit` line now, whatever
  your `diff.submodule` says; a repo's own `.factory/guardrails.txt` needs the line too.
- The guardrails trusted what an agent set on beating them can change: the worktree's
  `.git` file, index and config, the run dir and `.factory/protected`. Factory reads its
  own state and index now, or fails the branch. An ignored file at a protected path, as a
  `.mise.local.toml` left there by mistake, or a symlink had the gate read what they did
  not see; they check both now. The base Factory records moves only when it rebases the
  branch for a pull request, or when the branch took in newer commits of its base that
  origin holds. Newer ones only your `main` holds, as a fix of yours the builder merged or
  an agent's commits, count as the base's without being recorded, and stop the rebase for
  a pull request.
- In a fresh clone the task commands stopped on bd's "no beads database found": git brings
  `.beads` but not the tasks. Factory now says to take them from origin with
  `bd -C <repo> bootstrap --yes`.
- A rerun that found none of the task's agents alive took the root pane of the tab in front
  as the builder's, which can be a tab of yours: it started the agents there, or stopped
  because your tool ran in it. It takes the pane Factory labelled build now.

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

[Unreleased]: https://github.com/robi42/factory/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/robi42/factory/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/robi42/factory/compare/v0.1.11...v0.2.0
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
