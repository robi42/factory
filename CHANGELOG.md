# Changelog

All notable changes to Factory. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

Upgrading from 0.1.x: `factory answer` is gone; the planner asks its questions in a dialog
in its pane. The guardrails stop more than before: a change to any file under `.factory/`
but `.factory/run/` needs your waiver at plan approval; a NUL byte added to any file but
an image, a PDF, a font, an archive, audio or video fails the branch; and a submodule
added or moved, a symlink to a place git does not show, or an ignored file at a protected
path fails it whatever you waive. A typo in a knob now stops the run instead of being
read as something else. The agents may no longer run `git push`, `gh` or Factory itself.
A task 0.1.x started stops at its rerun on the files 0.1.x kept in its run dir, which
Factory reads from there no longer. Rerun it with `--fresh` to start it over; or, for it to
resume where it was, move `.factory/run/state` to the task's state dir, as the message
says, with `allow-protected` if you had waived the protected paths, listing in it those
the build may change, a path a line, and `decisions.md` to keep your answers in the pull
request, and remove the others. A build 0.1.x approved goes through one more round of
gate, reviews and your approval, as 0.1.x recorded no check of it. Upgrade between runs:
a run that waits at a gate takes your answer where its own Factory looks for it.

### Added
- The approvals ask you in a question dialog in the agent's pane, the planner's for the
  plan and the builder's for the build: Approve, Abort, for the plan also Approve, allow
  protected paths, or a typed note to have it revised, which arrives as typed, with no
  shell in between. Hooks that Factory gives the agent as it starts it (`--settings`)
  hand your answer to the gate, so the agent never relays it, and mark the dialog as open
  meanwhile, so that Factory neither types into it nor takes it for the end of the
  agent's turn. Factory's terminal prompt and the `fy` commands still answer too, `!fy`
  typed in a pane that shows no dialog (keys typed into the dialog go to it), and Factory
  closes the dialog when they do.
- Every answer you give on a task, the planner's questions included, goes into Factory's
  state for the task, onto the bead as a comment, and into the pull request's description.
  A planner that starts over reads it, as `.factory/run/decisions.md`, before asking again.
- A run that opens a pull request (`--pr`, `FACTORY_PR=1`) checks at its start, before it
  claims a bead, that origin takes a push without a prompt, with a dry-run push that sends
  nothing. A missing credential or write access stops the run there, with git's error,
  instead of at the push after the work. A base that is no branch on origin stops it too,
  before `factory run` claims its bead.
- A rerun picks up a written plan at its next review round instead of planning again: the
  run marks the plan as written, and again after each revision, so a run that stops
  during the plan's review keeps the planner's work.
- From the second build round on, the reviewers check what changed since their last
  notes, with the builder's answer to them (`response-N.md`, which nothing read) and
  your note on the build, as the plan's reviewers already did.
- A task that starts on a checkout git reads as changed stops before any agent works,
  instead of failing every check after hours of work.
- `factory doctor` also checks that `fy` resolves from a login shell, as the `!fy`
  commands in a pane need, and that git is 2.31 or newer.
- The plan ends saying whether the build must change protected paths, as
  `Protected paths: none` or which, so you know at approval whether to allow them. The
  planner is told which paths are protected; Factory warns at the approval when the plan
  does not say.
- `fy stats <repo>` shows how the repo's tasks went: for each task its plan and build
  rounds, how often the gate and the guardrails failed, the reviewers' objections, your
  notes, the time the agents, the gate and you took, and the tokens the agents read and
  wrote; the same as means per finished task for each Factory version, which tell whether
  a change helped; the guardrails that failed; and your latest notes. Each run records
  what it does as it goes, a JSON line an event, in `events.jsonl` beside the tasks'
  state, which `fy clean` leaves.
- `extras/factory-user/`: a recipe for running Factory, Herdr and the agents as a user of
  their own, which holds only its clones, a GitHub token for them and the agents' logins,
  so that an `--auto` run reaches nothing else of yours.

### Changed
- The planner asks its questions in its own question dialog, with options where they
  help, instead of through `questions.md` and Factory's terminal. A question waits as long
  as you need: a wait on your input no longer times out, and each new question gets a
  toast. A dismissed question gets the planner to plan with stated assumptions. Factory
  never answers such a dialog for you, whatever its options say.
- All of `.factory/` is protected now, but Factory's own `.factory/run/`: a task that adds
  or changes any file there needs your waiver at plan approval, and an ignored file
  anywhere under it fails the guardrails, waiver or not. Only the gate,
  `.factory/protected`, `.factory/guardrails.txt` and `.factory/env` were protected,
  though the guardrails read no line under `.factory/`, so an example in `.factory/guard/`
  that a repo's own gate holds its rules to could change unseen. Your own `.factory/env`
  in the repo's main checkout stays exempt from the checks for uncommitted and ignored
  files.
- The knobs are checked before a bead is claimed: an approval mode other than `ask` or
  `auto`, a flag other than 0 or 1, or a count that is no whole number stops the run with
  the knob's name. `FACTORY_APPROVAL=Ask` skipped both of your approvals, and
  `FACTORY_PR=true` died halfway through a run.
- The agents may not run `git push`, `gh` or Factory itself: the settings Factory starts
  them with deny them, so that no agent pushes unchecked commits, answers your gate with
  `fy approve` or merges its own pull request. Your own `!` commands in a pane run as
  typed.
- `factory queue` runs each task as a `factory next` of its own. A task that stops, or
  needs you, ends there and the queue goes on with the next one; Ctrl-C ends the queue.
- `factory pr`, and a rerun after the build's approval, check a branch that moved on since
  its last check, such as by a fixup you committed by hand, instead of refusing to push
  it; the rerun also takes it through another round of reviews and your approval.
- In Rust, whose unit tests live in the file they test, a `#[test]` or an assertion added
  to a changed `.rs` file counts for the tests-required check.
- Each refusal of the guardrails, and each stop, says what to do next.
- `factory pr` refuses `--auto` and `--fresh`, which do nothing there.

### Removed
- **Breaking:** `factory answer` (`!fy answer` in a pane) and the questions relay
  (`questions.md`, `answers.md` and the questions prompt in Factory's terminal) are gone;
  `factory answer` now fails as an unknown command. The planner asks in its own question
  dialog instead.

### Fixed
- A build whose plan you approved with protected paths allowed was still told to change
  none of them, and the waiver let any protected path through. It is told to change those
  the plan names, and the guardrails hold it to them: Factory keeps the paths the plan's
  `Protected paths:` line names as you approve it, a directory with the files under it,
  and fails any other protected path the branch changes, a symlink to a directory too.
  Factory's terminal shows beside `p` the paths it reads on that line.
- The build's reviewers ran the gate again, which Factory had just passed on that commit.
  On a long gate the planner ended its turn with its run still going and its review
  unfinished, which Factory took as given, and the run competed with the builder's next
  round in the same worktree. They are told now that the gate passed and where its log is,
  and not to run it again.
- A builder that could not fix what the guardrails found, such as a commit that 1Password,
  locked while you were away, would not sign, had the gate run again on the same files
  until the rounds ran out, and the hand-over said only `verdict: none`. A turn of the
  builder's after failed guardrails that changes nothing they check now ends the rounds:
  Factory hands the task over at once, naming the checks that failed.
- A task started from your local base even where origin's had moved on since you last
  pulled: the planner planned on origin's newer code, which the branch lacked, and the
  builder ended its turn without building, which Factory took for the build, running the
  gate on the unbuilt branch. A new task now starts from origin's copy of its base where
  yours is only behind it, and a first build turn that changes nothing hands the task
  over.
- A Copilot round whose fixes did not reach the pull request closed the task as done. On
  Blik's bk-9tt the builder's commit failed with 1Password locked; Factory ran the gate on
  the uncommitted fixes for 16 minutes, the guardrails failed, and the bead was closed
  with the pull request lacking them. Factory now hands the task over when the worktree
  holds commits or changes the pull request lacks, naming them and `fy pr`, which checks
  and pushes them once they are committed; fixes left uncommitted skip the gate.
- `factory next` and `factory queue` took up a task whose blocker in bd still had its pull
  request open: Factory closes a bead once its pull request is open, which makes the tasks
  it blocks ready in bd, and they started from a base without its code. On Blik, bk-cxs
  came next while bk-9tt's pull request, with the viewer bk-cxs builds on, was open.
  Such a task now waits for the merge: `factory next` skips it, naming the pull request,
  and takes the next ready task, and `factory run` stops on it before claiming its bead.
- A run no longer dies when an agent starts on its prompt later than Herdr's five seconds,
  as Codex did on a long plan review ("still working after startup"): Factory sees the
  turn begin and waits it out, instead of dying or sending the prompt twice.
- An agent start that times out because the pane's shell kept its command line, the line
  editor (ble.sh) stuck in multiline mode, is cleared and tried again, as it used to be:
  Herdr 0.8 reports the timeout under a new code, and the run stopped instead.
- A rerun after a restart of Herdr's server (a reboot, an update) starts the task's agents
  again with Factory's arguments, their sessions resumed. Herdr brings them back with
  their resume alone, and adopted as they were they ran without their effort (the
  planner's `max` fell back to your Claude Code default), model, permissions and dialog
  hooks, so an answer in the approval dialog never reached the gate. A gate now also
  offers its dialog only to an agent that runs with the hook.
- `factory tasks` showed bd's notice that its `--json` output changes in bd 2.0. Factory
  now reads bd's JSON in the envelope bd 2.0 makes its default, which ends the notice and
  keeps the task list, `factory next` and the task lookups working on bd 2.0.
- `factory queue` ran its tasks in one shell with errors ignored: a pull request that
  failed to open closed the bead as approved, with no pull request, a task that needed you
  read as done, and any stop ended the whole queue.
- `factory next` read a bd error, such as a locked database, as nothing ready, and a repo
  without beads too; it says so now.
- A review left by an interrupted run passed for the same round's review on a rerun, its
  old verdict counted; each round's reviews are removed before it asks.
- A failed read of Copilot's comments, such as on a rate limit, read as no comments, and
  the review counted as clean. It ends the Copilot loop with a note now.
- Ctrl-C stopped the run but not its gate, which ran on in the worktree beside a rerun's.
- Factory searched a working agent's whole screen for the startup dialogs it clears, and
  typed Esc, Enter, `q` or `r` into the agent's turn when the screen only showed such a
  dialog's words, as a run on Factory's own code does. It settles only a blocked agent.
- A task that needed you after its approval, as when the memory turn committed a file,
  said "needs a human" without saying why; the guardrails' reasons now go into the
  message and onto the bead.
- A rerun found only some of a task's agents alive and suggested `factory clean --force`,
  which drops the work; it says to quit the others and rerun.
- The `extras/cargo-sccache` wrapper printed a write error on a compile's stderr now and
  then, under `mise exec`, which leaves SIGPIPE ignored.
- A rerun took the branch your checkout was on for the task's base, so a task rerun from
  another branch was rebased onto that one and opened its pull request against it; one
  merged and deleted on GitHub failed the pull request after all the work. A task now
  keeps the base it started from, recorded in Factory's own state for the task, whatever
  the checkout is on, and `--fresh` takes the checkout's anew.
- The guardrails diffed the branch against `main` or `origin/main` by name, which an agent
  can move with `git update-ref`, your `main` with it, so that its commits dropped out of
  every diff they read. Factory now records the commit the branch forks from when it opens
  the task's worktree, and moves it only when it rebases the branch itself before a pull
  request, or when the branch took in newer commits of origin's base, which it fetches to
  tell; the guardrails, the reviewers' prompts and the build's approval read the branch
  from that commit. A base ref that no longer holds it stops the run loudly, as your
  `main` may have been rewritten. `factory clean` removes this state with the task.
- The rebase before a pull request fetched the base through origin's config and fell back
  to your local branch when the fetch failed, both of which an agent can steer to a commit
  of its own: by the remote's URL or refspec, by its tracking ref, or by the repo's git
  config, which reaches a server of the agent's with origin's URL unchanged
  (`core.sshCommand`, a proxy). Factory now records the repo's own git config for reaching
  origin (origin's URLs, URL rewrites, the ssh command, proxies, http and credential
  settings) the first time it runs there, and a fetch or a push stops when any of it has
  changed since, naming the keys; your global config applies as it does to git. It fetches
  the base by its full name from origin's URL into `refs/factory/<bead-id>/upstream/<base>`,
  a ref nothing else writes, and into origin's tracking ref, without following either
  where it is a symbolic ref, rebases onto that, and stops when it cannot fetch. It also stops when the base it
  fetched does not hold the commit the branch was measured from, such as one an agent put
  on your `main` before the task started, or one you have not pushed: the pull request
  would carry it unchecked.
- The gate and the guardrails checked the commit checked out in the worktree, but Factory
  pushed the branch by name: a worktree left on another commit had them pass that commit
  while the push sent the branch's, and a commit made after the gate went out unchecked.
  Factory now gates and guards only the branch's tip, records the commit both passed on,
  and pushes exactly that commit by its id, as the Copilot rounds do. Before the bead is
  closed it checks that origin's copy of the branch is that commit, which an agent's own
  push would not be.
- A worktree whose own git config set `core.worktree` pointed every git call of the
  guardrails at another checkout, a clean one, while the gate ran in the worktree itself.
  The guardrails now refuse a worktree that git does not read as the top of its checkout.
- A worktree whose `.git` file an agent rewrote to name another clone had the gate and the
  guardrails read that clone's refs, history and HEAD. Factory now refuses to gate or
  guard a worktree unless git there reads the task repo's own git dir, through a worktree
  the repo lists.
- The guardrails read a tree other than the branch's when an agent planted a `git replace`
  ref or an `info/grafts` line in the shared git dir: either rewrites what `HEAD` is or
  descends from, so `git diff base...HEAD` showed no added line, no protected path and no
  gitlink, and the guardrails refused nothing. The guardrails, the uncommitted-changes
  check, and the reading of where a branch forks off its base, what it took in from origin
  and what it is rebased onto now ignore replace refs and grafts.
- The guardrails passed a branch whose diff against the base git could not read, since
  every check then read nothing: a line in `.git/shallow`, which an agent can write, cut the
  branch off from the base, so that the two shared no history, and an object gone from the
  repository failed the diff of a file the worktree still matched. The guardrails now fail
  such a branch and say why, with git's error.
- The check for uncommitted changes trusted what an agent can set: the worktree's index and
  git config (a file marked assume-unchanged or skip-worktree, sparse patterns, an
  fsmonitor hook, `core.checkStat=minimal`, `core.ignoreCase`, `core.fileMode=false`,
  `core.symlinks=false`, a submodule's `ignore` setting) and git's conversions
  (`core.autocrlf`, a `text`, `eol` or `filter` attribute in `.git/info/attributes`) hid an
  edited `.factory/gate`, or any other change, while the gate ran on it: a clean filter
  handed git the committed `justfile` for an edited one. Git now compares the worktree
  with HEAD through an index of Factory's own, with those settings at their defaults, and
  Factory holds each tracked file's bytes to the commit's, converted as git would store
  them with only the committed `.gitattributes` and your own git config: `eol=crlf`, Git
  LFS and a global `core.autocrlf` pass, a conversion set in the repo's git dir fails. The
  guardrails name the files that differ.
- Untracked files hid from the check for uncommitted changes behind an untracked
  `.gitignore` that ignores itself, such as a `conftest.py` beside one in `tests/`, behind
  a line added to `info/exclude`, or behind a `core.excludesFile` in the repo's config.
  Each now fails the guardrails.
- Since 0.1.11 the check for uncommitted changes counted your own `.factory/env` in the
  repo's main checkout, where you may keep it untracked and `factory check` reads it, so
  `factory check` failed there. It is left out there again, as the ignored-file check
  leaves it out; in a task's worktree it still counts.
- The guardrails skipped a file whose name git quotes, such as `naïve.rs` with its
  non-ASCII character: not one of its added lines was matched, and it counted as neither
  code, test nor build artifact. A name that reads as a pathspec, such as
  `:(exclude)x.sh`, hid the file's lines too. Such names now count like any other.
- The guardrails skipped an added line that begins with a `+`, such as a suppression in a
  patch file the build applies: the filter that dropped the `+++` file header dropped it
  as well. Only the headers above each hunk are skipped now, and a pattern still sees
  each added line with diff's `+` in front, as one anchored with `^\+` expects.
- The guardrails read no line at all when the repository's git config, which an agent in a
  worktree can write, coloured the diff (`color.diff=always`), named an external diff
  tool, or gave a file a textconv filter. They read git's own diff now, whatever the
  config says.
- One line of a repo's `.factory/guardrails.txt` that grep could not read switched off
  every forbidden pattern: the branch passed whatever it added. Such a line now fails the
  guardrails, which name the file.
- A renamed file read as added in full, so moving a module that already held a
  suppression, or a committed SQLite fixture, failed the branch. A renamed file counts
  only the lines it changed; a copy's count in full.
- A NUL byte hid a text file's lines from the guardrails, though rustc compiles a Rust
  source with one in a comment: git shows a file with a NUL in its first 8000 bytes as
  binary, and grep stops printing lines at one further on. A `binary` or `-diff`
  attribute hid them the same way. A NUL byte added to a file now fails the branch, unless
  the file is named as an image, a PDF, a font, an archive, audio or video and its bytes
  agree, as an image's do; only such a file counts as binary, with no lines to check, and
  every other file's lines are checked all the same.
- A committed build artifact slipped past the build-artifact check when git read it as a
  rename of a deleted file of like content. A rename no longer hides one.
- An agent could approve its own plan or build, abort it, hand the planner a note as yours,
  or have a rerun skip the reviews: the gate's answers (`approved`, `reject.md`,
  `aborted`), what it waits for (`waiting`) and the log of your answers (`decisions.md`)
  were files in the run dir, which the agents write, a resume point there (`state`, such
  as `built 1`) was taken for Factory's own when the task had no base recorded, and the
  planner's `tree-at-ask` and `tree-at-answer` there excused whatever changes it listed as
  yours. Factory now keeps all of them in its own state for the task, which only it, your
  `fy approve`, `reject` and `abort`, and the dialogs' hooks write, and writes your answers
  into the run dir for the planner over whatever is there. A file in the run dir by a name
  Factory kept there before (`approved`, `reject.md`, `aborted`, `allow-protected`,
  `state`, `tree-at-ask`, `tree-at-answer`) stops the next run before any agent works, and
  fails the guardrails: only an agent would put it there. `--fresh` removes one.
- A planner's commit passed the check that planning leaves the code untouched, which read
  only uncommitted changes. A planner turn that commits, or moves HEAD, the task's branch,
  Factory's refs for the task or a replace ref, now stops the run, and says which. The
  repo's other refs, which you, fetches and other tasks move meanwhile (your main, tags, a
  stash), decide nothing for the task.
- A builder could waive its own protected-path check: the waiver was a file in the run
  dir, which the agents write, and the pull request then recorded it as yours. Factory now
  keeps your waiver in its own state for the task, under
  `${XDG_STATE_HOME:-~/.local/state}/factory/tasks/`, which only your answer at the plan's
  approval writes (`p`, the dialog, or
  `factory approve <repo> <bead-id> --allow-protected`). An `allow-protected` file in the
  run dir, or on the branch, waives nothing and fails the guardrails. `factory check` in a
  task's worktree honours the task's waiver. A file committed in the run dir fails them
  too, as no other check reads one.
- A line of `.factory/protected` that git cannot read as a pathspec, such as `:(bogus)x`,
  made git fail in both checks of protected paths, which then read no path and passed; only
  git's own error reached the terminal. The guardrails now fail and say which line.
- An ignored file at a protected path steered the gate unseen. Ignored by the repository's
  `.gitignore` or by your global excludes, it escaped both the uncommitted-changes check
  and the guardrails, yet the gate read it: in a repo whose `.factory/protected` lists
  mise's configs, an ignored `.mise.local.toml` could set
  `CARGO_ENCODED_RUSTFLAGS="--cap-lints=allow"` for every mise shim, and clippy passed.
  Such a file now fails the guardrails, waiver or not. Exempt are `.factory/run/`, and your
  own `.factory/env` in the repo's main checkout, where no agent works.
- A symlink let the gate read what the guardrails did not see. One into an ignored place
  such as `target/`, into `.git` or out of the worktree showed its content in no diff:
  `.cargo -> target/cfg` made an ignored file Cargo's config. One to a directory gave the
  files under it paths that no protected glob names. The guardrails now refuse a symlink
  the branch adds, renames or points elsewhere that leads to such a place, waiver or not,
  and one to a directory unless you waived the protected paths.
- A submodule the branch added, or pointed at another commit, brought in files that the
  gate read and no diff showed, and git config an agent can write (`diff.submodule`,
  `diff.ignoreSubmodules`) could hide even its one `+Subproject commit` line. The
  guardrails now refuse such a submodule, waiver or not, whatever the config says; that
  change is yours to make after the merge.

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
