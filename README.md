# factory

A simple software factory on [Herdr](https://herdr.dev): one task in, one reviewed branch out.

- **Claude Code** plans (Fable 5.1) and builds (Opus 5), each in its own Herdr pane.
  The plan states the design in a few lines: what changes, responsibilities, interfaces.
- **Codex** reviews (GPT 6 Astra, with web search) in a third pane.
- **Reviews are dual.** The plan is checked by Codex and by the builder who has to execute
  it; the build by Codex and by the planner who wrote the plan. Reviewers look for bugs,
  missed requirements, shortcuts, security problems, and design problems. Both must approve.
- **Beads** (`bd`) is the task queue and the memory: tasks are beads, and agents leave
  `bd remember` notes that the next run gets to see.
- **Guardrails** are mechanical, not prose. The factory itself runs your gate
  (`just ci`, or `.factory/gate`) and rejects branches that add suppressions, skipped
  tests, or swallowed errors, change code without touching a test, commit build
  artifacts, or touch protected files. The patterns live in `guardrails.txt`, adapted
  from [ai-guardrails](https://github.com/florianbuetow/ai-guardrails).

Every task gets its own git worktree and Herdr workspace, so you can watch or step in.
The agents are your normal `claude` and `codex` sessions, so your skills, MCP servers,
hooks, `CLAUDE.md` and `AGENTS.md` all apply; the factory adds nothing to them at run
time. Claude runs in its `auto` permission mode; whenever an agent stops for a question
or an approval you get a Herdr toast, answer in the pane, and the factory carries on.

## Setup

```sh
mise install            # just, shfmt, shellcheck, bats, codespell, bd
ln -s "$PWD/factory" ~/.local/bin/factory
factory doctor
```

Herdr must be running. `claude` and `codex` must be logged in. `bd` and whatever your
gate needs must resolve from a fresh login shell (Claude Code runs its commands from one),
so install them globally, e.g. `mise use -g 'ubi:steveyegge/beads[exe=bd]@1.2.2'`.
`factory doctor` checks this.

Optional, and worth it: library docs and GitHub code search for both agents.

```sh
claude plugin install context7@claude-plugins-official
claude mcp add --transport http grep_app https://mcp.grep.app
codex mcp add context7 --url https://mcp.context7.com/mcp
codex mcp add grep_app --url https://mcp.grep.app
```

Codex runs without approvals in the factory, so give grep.app a pass in `~/.codex/config.toml`:

```toml
[mcp_servers.grep_app]
url = "https://mcp.grep.app"
default_tools_approval_mode = "approve"
```

## Use

```sh
factory init   ~/src/app                          # lean bd init, detect + write the gate, AGENTS.md stub
factory add    ~/src/app "Add CSV export" "..."   # file work as beads
factory add    ~/src/app                          # ...or compose title + description in $EDITOR
factory tasks  ~/src/app                          # list open tasks (--all includes closed)
factory next   ~/src/app                          # claim the next ready bead, run it
factory run    ~/src/app "Fix flaky login test"   # a one-off, also filed as a bead
factory queue  ~/src/app                          # work through everything that is ready
factory next   --pr --auto ~/src/app              # flags: open a PR when approved; skip plan approval
factory approve ~/src/app toy-abe                 # approve a waiting plan from anywhere
factory approve ~/src/app toy-abe --allow-protected   # ...when the plan must touch protected files
factory pr      ~/src/app toy-abe                 # open a PR for a task branch a run left behind
factory reject  ~/src/app toy-abe "keep it in one module"   # steer the planner instead
factory answer  ~/src/app toy-abe "1. yes  2. keep the old format"   # planner questions
factory check  <worktree> main                    # gate + guardrails on a branch, no agents
factory status                                    # live factory agents in Herdr
```

A run goes plan (the planner may first ask you questions if the task is ambiguous),
dual plan review (one revision if needed), your approval, build, gate,
guardrails, dual code review, then revise / gate / review again, up to `FACTORY_ROUNDS`
times. With `--pr` (or `FACTORY_PR=1`) an approved branch is pushed and a pull request
opened with `gh`, its body carrying the plan and the check results; the bead records the URL.
At the approval step the factory prints the plan in its terminal, sends a toast,
and waits. Answer there (approve, revise with a note, abort) or from any terminal with
`factory approve <repo> <id>` and `factory reject <repo> <id> "note"`. A note goes to
the planner, the plan comes back revised, and you are asked again. You can also edit
`plan.md` directly or talk to the planner in its Herdr pane first; the builder reads the
file. `--auto` (or `FACTORY_PLAN_APPROVAL=auto`) skips the step for unattended queues. Planner questions
work the same way: answer in the terminal (end with a line containing only `.`) or with
`factory answer <repo> <id> "..."`; up to three rounds, then the plan comes. On approval
the bead is closed and you get a toast; merge the `factory/<bead-id>` branch when you are
happy. Otherwise the bead stays in progress with a comment saying what happened, and the
workspace stays open for you.

Run artifacts live in `.factory/run/` inside the worktree, ignored by git: `plan.md`,
`questions.md` (planner, only when asked), `plan-review.md` (Codex), `plan-review-build.md` (builder), `review-N.md` (Codex),
`review-N-plan.md` (planner), `response-N.md` (builder's pushback), `gate-N.log`.
The gate script `.factory/gate` and `.factory/protected` (one glob per line) are
committed, and the agents may not change them, unless you waive that for one task at plan
approval (`p` instead of `a`, or `--allow-protected`), which a bootstrap task like "add the
gate" needs. The waiver skips only the protected-path check; the PR body records it.

`factory init` writes a short `AGENTS.md` (with `CLAUDE.md` linking to it) only when a
repo has neither. Keep it to what the code cannot tell a new engineer: how to verify,
layout where not obvious, rules and reasons. Workflow lives in the prompts, not there.

## The gate

The gate is your repo's definition of done. The factory runs it itself and never takes
an agent's word for it. It is resolved once per run, in this order, and printed at start:

1. `FACTORY_GATE`, any shell command.
2. `.factory/gate` in the repo, run as `bash .factory/gate`. A committed script, e.g.
   `set -eu` followed by `python3 -m pytest -q`. `factory init` writes it for you from the
   repo's own convention (`bin/test`, `just ci`, a Makefile target, or the language
   default for Cargo, npm, pyproject, Go, Mix, Gradle, Maven); you review and commit it.
3. The repo's own convention, detected: `bin/test`, `just ci`, a Makefile `ci`/`check`/`test`
   target, or the language default for Cargo, npm, pyproject, Go, Mix, Gradle, Maven.
   The run says so at start; add `.factory/gate` when you want it explicit and protected.
4. Otherwise the run refuses to start and says what to add.

After each build or revision the factory runs the gate in the worktree, output to
`.factory/run/gate-N.log`, exit code zero means pass. On failure the builder gets the
last forty lines of the log and one round to fix, rerun, and commit. Guardrails run only
after the gate passes, reviews only after both. The final close-out checks that a passing
gate log exists for the approved round.

Put everything language-specific in the gate: tests, linters, type checks, coverage
thresholds, semgrep rules, architecture tests. The factory stays language-agnostic.
`.factory/gate` is protected, so agents cannot relax it. `factory check <worktree> <base>`
runs gate plus guardrails on any branch without agents.

## Knobs

| env | default |
|---|---|
| `FACTORY_PLAN_MODEL` | `claude-fable-5-1` |
| `FACTORY_BUILD_MODEL` | `claude-opus-5` |
| `FACTORY_REVIEW_MODEL` | `gpt-6-astra` |
| `FACTORY_ROUNDS` | `3` |
| `FACTORY_CLAUDE_PERMISSIONS` | `auto` (any Claude Code permission mode) |
| `FACTORY_TURN_TIMEOUT_MS` | `3600000` |
| `FACTORY_GATE` | discovered: `.factory/gate`, then the repo's convention |
| `FACTORY_REQUIRE_TESTS` | `1`: a change to code files must also touch a test file |
| `FACTORY_PLAN_APPROVAL` | `ask`: you approve each plan in the factory terminal; `auto` skips |
| `FACTORY_PR` | `0`; `1` pushes the approved branch and opens a pull request with `gh` |
| `FACTORY_GUARDRAILS` | `guardrails.txt` next to the script |

## Develop

```sh
just ci      # shfmt, shellcheck, guardrails applied to ourselves, codespell, bats
```

## License

MIT, see `LICENSE`.
