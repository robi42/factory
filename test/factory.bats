#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Unit tests for the pure parts of factory: task ids, verdicts, gate discovery, guardrails.

setup() {
  export FACTORY_GUARDRAILS="$BATS_TEST_DIRNAME/../guardrails.txt"
  # shellcheck source=../factory
  source "$BATS_TEST_DIRNAME/../factory"
  FACTORY_REQUIRE_TESTS=0 # the fixtures below change code without tests on purpose
  TMP=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP"
}

# make_repo: one commit on main, then a work branch. Sets REPO.
make_repo() {
  REPO="$TMP/repo"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name t
  mkdir -p "$REPO/.factory"
  printf '#!/bin/sh\nexit 0\n' >"$REPO/.factory/gate"
  printf 'echo hi\n' >"$REPO/run.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm base
  git -C "$REPO" checkout -qb work
}

# the globals human_gate reads for its messages
fake_task() {
  TASK_ID=toy-1
  TASK_TITLE=t
}

# the branch globals the gates and guards read, as task_context sets them
on_work_branch() {
  WT=$REPO
  BASE=main
  BRANCH=work
}

commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "$1"
}

@test "bead ids look like prefix-hash" {
  is_bead_id toy-bx4
  is_bead_id bd-a3f8e9
  run ! is_bead_id "Add a farewell function"
  run ! is_bead_id "toy"
}

@test "verdict comes from the last VERDICT line" {
  printf 'notes\nVERDICT: REVISE\nmore\nVERDICT: APPROVE\n' >"$TMP/r.md"
  [ "$(verdict_of "$TMP/r.md")" = APPROVE ]
  printf 'VERDICT:REVISE\n' >"$TMP/r.md"
  [ "$(verdict_of "$TMP/r.md")" = REVISE ]
  printf 'no verdict here\n' >"$TMP/r.md"
  run ! verdict_of "$TMP/r.md"
  run ! verdict_of "$TMP/missing.md"
}

@test "gate: env wins, then .factory/gate, then just ci, else error" {
  make_repo
  FACTORY_GATE="make check" run resolve_gate "$REPO"
  [ "$output" = "make check" ]
  unset FACTORY_GATE
  [ "$(resolve_gate "$REPO")" = "bash .factory/gate" ]
  rm "$REPO/.factory/gate"
  printf 'ci:\n\ttrue\n' >"$REPO/justfile"
  [ "$(resolve_gate "$REPO")" = "just ci" ]
  rm "$REPO/justfile"
  run resolve_gate "$REPO"
  [ "$status" -ne 0 ]
  [[ $output == *"no gate"* ]]
}

@test "protected globs: defaults plus .factory/protected" {
  make_repo
  printf '# keep\nsrc/legacy/*\n\n' >"$REPO/.factory/protected"
  run protected_globs "$REPO"
  [ "${lines[0]}" = ".factory/gate" ]
  [ "${lines[1]}" = ".factory/protected" ]
  [ "${lines[2]}" = ".factory/guardrails.txt" ]
  [ "${lines[3]}" = ".factory/env" ]
  [ "${lines[4]}" = "src/legacy/*" ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "load_repo_env: .factory/env fills unset knobs, the environment wins, bad lines die" {
  make_repo
  printf '# repo defaults\n\nFACTORY_ROUNDS=5\nFACTORY_PR=1\nFACTORY_GATE=just test # verbatim\n' >"$REPO/.factory/env"
  ENV_KNOBS=FACTORY_PR
  FACTORY_ROUNDS=3
  FACTORY_PR=0
  unset FACTORY_GATE
  load_repo_env "$REPO"
  [ "$FACTORY_ROUNDS" = 5 ]
  [ "$FACTORY_PR" = 0 ]
  [ "$FACTORY_GATE" = "just test # verbatim" ]
  run load_repo_env "$TMP/nowhere"
  [ "$status" -eq 0 ]
  printf 'export FACTORY_ROUNDS=5\n' >"$REPO/.factory/env"
  run load_repo_env "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"expected FACTORY_NAME=value"* ]]
  printf 'FACTORY_HOME=/elsewhere\n' >"$REPO/.factory/env"
  run load_repo_env "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"not a knob"* ]]
}

@test "guard: clean committed change passes" {
  make_repo
  printf 'echo hello\n' >"$REPO/run.sh"
  commit_all change
  run guard_check "$REPO" main
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard: nothing committed fails" {
  make_repo
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"no commits"* ]]
}

@test "guard: uncommitted work fails" {
  make_repo
  printf 'echo hello\n' >"$REPO/run.sh"
  commit_all change
  printf 'echo again\n' >>"$REPO/run.sh"
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"uncommitted"* ]]
}

@test "guard: touching the gate fails" {
  make_repo
  printf '#!/bin/sh\nexit 0 # relaxed\n' >"$REPO/.factory/gate"
  commit_all "relax gate"
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"protected path changed: .factory/gate"* ]]
}

@test "guard: custom protected glob is enforced" {
  make_repo
  mkdir -p "$REPO/src/legacy"
  printf 'src/legacy/*\n' >"$REPO/.factory/protected"
  commit_all "add protection"
  git -C "$REPO" checkout -q main
  git -C "$REPO" merge -q work
  git -C "$REPO" checkout -q work
  printf 'x\n' >"$REPO/src/legacy/old.txt"
  commit_all "touch legacy"
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"protected path changed: src/legacy/old.txt"* ]]
}

@test "guard: forbidden patterns on added lines fail, except under .factory" {
  make_repo
  # Build the bad strings at runtime so this file passes its own guard check.
  local pipe='||' marker=skip
  printf 'run_thing %s true\n' "$pipe" >"$REPO/run.sh"
  printf 'import pytest\n@pytest.mark.%s\ndef test_x(): pass\n' "$marker" >"$REPO/test_x.py"
  mkdir -p "$REPO/.factory/run"
  printf 'x %s true\n' "$pipe" >"$REPO/.factory/run/log.txt"
  commit_all bad
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"run.sh: run_thing"* ]]
  [[ $output == *"test_x.py: @pytest.mark.$marker"* ]]
  [[ $output != *"log.txt"* ]]
  [[ $output == *"forbidden pattern"* ]]
}

@test "guard: removing a forbidden line is fine" {
  make_repo
  local pipe='||'
  git -C "$REPO" checkout -q main
  printf 'run_thing %s true\n' "$pipe" >"$REPO/run.sh"
  commit_all "bad on main"
  git -C "$REPO" checkout -q work
  git -C "$REPO" merge -q main
  printf 'run_thing\n' >"$REPO/run.sh"
  commit_all fixed
  run guard_check "$REPO" main
  [ "$status" -eq 0 ]
}

@test "verdicts: one word per file, NONE when missing" {
  printf 'VERDICT: APPROVE\n' >"$TMP/a.md"
  printf 'VERDICT: REVISE\n' >"$TMP/b.md"
  [ "$(verdicts "$TMP/a.md" "$TMP/b.md" "$TMP/none.md")" = "APPROVE REVISE NONE" ]
}

@test "guard: committed build artifacts fail" {
  make_repo
  mkdir -p "$REPO/__pycache__"
  printf 'x' >"$REPO/__pycache__/m.cpython-314.pyc"
  commit_all "oops"
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"build artifact committed: __pycache__/m.cpython-314.pyc"* ]]
}

@test "agents stub: written once, links CLAUDE.md, names the gate" {
  make_repo
  write_agents_stub "$REPO"
  [ -L "$REPO/CLAUDE.md" ]
  [ "$(readlink "$REPO/CLAUDE.md")" = AGENTS.md ]
  grep -q 'bash .factory/gate' "$REPO/AGENTS.md"
  [ "$(wc -l <"$REPO/AGENTS.md")" -lt 25 ]
}

@test "guard: code change without a test change fails, with one passes, off when disabled" {
  make_repo
  printf 'def f():\n    return 1\n' >"$REPO/mod.py"
  commit_all "code only"
  FACTORY_REQUIRE_TESTS=1
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"no test files did"* ]]
  FACTORY_REQUIRE_TESTS=0 run guard_check "$REPO" main
  [ "$status" -eq 0 ]
  printf 'from mod import f\ndef test_f():\n    assert f() == 1\n' >"$REPO/test_mod.py"
  commit_all "with test"
  FACTORY_REQUIRE_TESTS=1 run guard_check "$REPO" main
  [ "$status" -eq 0 ]
}

@test "guard: docs-only change needs no test" {
  make_repo
  printf 'notes\n' >"$REPO/NOTES.md"
  commit_all docs
  run guard_check "$REPO" main
  [ "$status" -eq 0 ]
}

@test "plan approval: terminal answers" {
  fake_task
  toast() { :; }
  printf 'the plan\n' >"$TMP/plan.md"
  FACTORY_APPROVAL=ask
  human_gate plan planner "$TMP" <<<"a"
  run human_gate plan planner "$TMP" <<<"b"
  [ "$status" -eq 3 ]
  FACTORY_APPROVAL=auto
  human_gate plan planner "$TMP" </dev/null
  FACTORY_APPROVAL=ask
  ask() { printf 'asked %s: %s\n' "$1" "$2"; }
  run human_gate plan planner "$TMP" <<<$'r\nsplit the module\na'
  [ "$status" -eq 0 ]
  [[ $output == *"asked planner: The human reviewed"*"split the module"* ]]
}

@test "plan approval: files from factory approve / reject, no terminal" {
  fake_task
  FACTORY_APPROVAL=ask
  FACTORY_POLL_SECONDS=1
  toast() { :; }
  printf 'the plan\n' >"$TMP/plan.md"
  ask() {
    printf 'asked %s: %s\n' "$1" "$2"
    : >"$TMP/approved" # the human approves after the revision
  }
  # the human's reject arrives while the factory is already waiting
  (
    sleep 2
    printf 'too big, split it\n' >"$TMP/reject.md"
  ) &
  run human_gate plan planner "$TMP" </dev/null
  wait
  [ "$status" -eq 0 ]
  [[ $output == *"no terminal"* ]]
  [[ $output == *"asked planner: "*"too big, split it"* ]]
  [[ $output == *"approved via file"* ]]
  [ ! -e "$TMP/approved" ]
}

@test "approve and reject subcommands find the task worktree" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" worktree add -q -b factory/toy-9 "$TMP/wt-9"
  mkdir -p "$TMP/wt-9/.factory/run"
  cmd_approve "$REPO" toy-9
  [ -e "$TMP/wt-9/.factory/run/approved" ]
  cmd_reject "$REPO" toy-9 "use argparse"
  [ "$(cat "$TMP/wt-9/.factory/run/reject.md")" = "use argparse" ]
  run cmd_approve "$REPO" toy-404
  [ "$status" -eq 1 ]
  [[ $output == *"no worktree"* ]]
}

@test "detect_gate: repo conventions win over language defaults" {
  make_repo
  rm "$REPO/.factory/gate"
  run detect_gate "$REPO"
  [ "$status" -eq 1 ]
  printf '[package]\nname = "x"\n' >"$REPO/Cargo.toml"
  [[ $(detect_gate "$REPO") == cargo* ]]
  printf 'test:\n\ttrue\n' >"$REPO/Makefile"
  [ "$(detect_gate "$REPO")" = "make test" ]
  printf 'ci:\n\ttrue\n' >"$REPO/justfile"
  [ "$(detect_gate "$REPO")" = "just ci" ]
  mkdir -p "$REPO/bin" && printf '#!/bin/sh\ntrue\n' >"$REPO/bin/test" && chmod +x "$REPO/bin/test"
  [ "$(detect_gate "$REPO")" = "./bin/test" ]
  write_gate "$REPO" "$(detect_gate "$REPO")"
  [ -x "$REPO/.factory/gate" ]
  grep -q '^./bin/test$' "$REPO/.factory/gate"
  [ "$(resolve_gate "$REPO")" = "bash .factory/gate" ]
}

# compose_task sets globals; print them so tests can assert on output.
composed() {
  compose_task 2>/dev/null
  printf '%s\n---\n%s' "$TASK_TITLE" "$TASK_DESC"
}

@test "compose_task: title, blank line, multi-line description; comments dropped" {
  VISUAL="" EDITOR=""
  run composed <<'IN'
# a comment first

  Add CSV export

Users want to download the table.
Keep the delimiter configurable.

# trailing comment
IN
  [ "$status" -eq 0 ]
  [ "$output" = $'Add CSV export\n---\nUsers want to download the table.\nKeep the delimiter configurable.' ]
  run composed <<<"Just a title"
  [ "$output" = $'Just a title\n---' ]
  run compose_task <<<$'\n# nothing\n'
  [ "$status" -eq 1 ]
  [[ $output == *"empty title"* ]]
}

@test "pr_body carries task, plan and whatever checks exist" {
  make_repo
  fake_task
  TASK_DESC="details"
  WT=$REPO
  GATE="bash .factory/gate"
  BRANCH=factory/toy-1
  mkdir -p "$REPO/.factory/run"
  printf 'the plan\n' >"$REPO/.factory/run/plan.md"
  run pr_body
  [[ $output == "details"* ]]
  [[ $output == *"Bead toy-1."*"Gate: not run"*"<summary>Plan</summary>"*"the plan"* ]]
  TASK_DESC=""
  run pr_body
  [[ $output == "t"* ]]
  TASK_DESC="details"
  : >"$REPO/.factory/run/gate-2.log"
  printf 'VERDICT: APPROVE\n' >"$REPO/.factory/run/review-2.md"
  printf 'VERDICT: REVISE\n' >"$REPO/.factory/run/review-2-plan.md"
  : >"$REPO/.factory/run/allow-protected"
  run pr_body
  [[ $output == *"passed (gate-2)"*"review-2: APPROVE"*"review-2-plan: REVISE"*"waived by the human"* ]]
}

@test "guard: waiver skips only the protected-path check" {
  make_repo
  printf '#!/bin/sh\nexit 0 # relaxed\n' >"$REPO/.factory/gate"
  commit_all "relax gate"
  mkdir -p "$REPO/.factory/run"
  : >"$REPO/.factory/run/allow-protected"
  run guard_check "$REPO" main
  [ "$status" -eq 0 ]
  [[ $output == *"waived"* ]]
  printf 'echo x\n' >>"$REPO/run.sh"
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"uncommitted"* ]]
}

@test "approve --allow-protected and the p answer write the waiver" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" worktree add -q -b factory/toy-9 "$TMP/wt-9"
  mkdir -p "$TMP/wt-9/.factory/run"
  cmd_approve "$REPO" toy-9 --allow-protected
  [ -e "$TMP/wt-9/.factory/run/allow-protected" ]
  [ -e "$TMP/wt-9/.factory/run/approved" ]
  fake_task
  toast() { :; }
  printf 'the plan\n' >"$TMP/plan.md"
  FACTORY_APPROVAL=ask
  human_gate plan planner "$TMP" <<<"p"
  [ -e "$TMP/allow-protected" ]
}

@test "build approval: a approves; r and the reject file hand the note back with 4" {
  make_repo
  printf 'echo more\n' >>"$REPO/run.sh"
  commit_all change
  fake_task
  toast() { :; }
  on_work_branch
  FACTORY_APPROVAL=ask
  FACTORY_POLL_SECONDS=1
  run human_gate build builder "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  [[ $output == *"build for toy-1 on work"*"change"*"run.sh"* ]]
  rc=0
  human_gate build builder "$TMP" <<<$'r\nrename it' || rc=$?
  [ "$rc" -eq 4 ]
  [ "$HUMAN_NOTE" = "rename it" ]
  (
    sleep 2
    printf 'use a table\n' >"$TMP/reject.md"
  ) &
  rc=0
  human_gate build builder "$TMP" </dev/null || rc=$?
  wait
  [ "$rc" -eq 4 ]
  [ "$HUMAN_NOTE" = "use a table" ]
  run human_gate build builder "$TMP" <<<"b"
  [ "$status" -eq 3 ]
}

@test "collect_answers: terminal lines until a dot, or answers.md from factory answer" {
  fake_task
  FACTORY_POLL_SECONDS=1
  toast() { :; }
  printf '1. Which format?\n2. Keep old API?\n' >"$TMP/questions.md"
  run collect_answers "$TMP/questions.md" <<<$'1. CSV\n2. yes\n.'
  [ "$status" -eq 0 ]
  [[ $output == *"the planner asks"* ]]
  [[ $output == *$'1. CSV\n2. yes' ]]
  (
    sleep 2
    printf 'CSV, and yes\n' >"$TMP/answers.md"
  ) &
  run collect_answers "$TMP/questions.md" </dev/null
  wait
  [ "$status" -eq 0 ]
  [[ $output == *"no terminal"*"via file"*"CSV, and yes" ]]
  [ ! -e "$TMP/answers.md" ]
}

@test "answer subcommand writes answers.md into the task worktree" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" worktree add -q -b factory/toy-9 "$TMP/wt-9"
  mkdir -p "$TMP/wt-9/.factory/run"
  cmd_answer "$REPO" toy-9 "1. CSV"
  [ "$(cat "$TMP/wt-9/.factory/run/answers.md")" = "1. CSV" ]
  cmd_answer "$REPO" toy-9 - <<<"from stdin"
  [ "$(cat "$TMP/wt-9/.factory/run/answers.md")" = "from stdin" ]
  run cmd_answer "$REPO" toy-9 "" </dev/null
  [ "$status" -eq 1 ]
}

@test "take_flags: --pr and --auto set knobs, the rest stay in order, unknown flags fail" {
  FACTORY_PR=0
  FACTORY_APPROVAL=ask
  take_flags --pr repo "a task" --auto
  [ "$FACTORY_PR" = 1 ]
  [ "$FACTORY_APPROVAL" = auto ]
  [ "${#ARGS[@]}" -eq 2 ]
  [ "${ARGS[0]}" = repo ]
  [ "${ARGS[1]}" = "a task" ]
  run take_flags --nope repo
  [ "$status" -eq 1 ]
  [[ $output == *"unknown flag: --nope"* ]]
}

@test "copilot_format picks the bot's comments for one commit as file:line: body" {
  run copilot_format abc123 <<'JSON'
[
  {"user":{"login":"Copilot"},"commit_id":"abc123","original_commit_id":"abc123","path":"hello.py","line":7,"body":"Use f-strings\r\nhere."},
  {"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123","original_commit_id":"old111","path":"hello.py","line":1,"body":"carried along from an earlier review"},
  {"user":{"login":"human"},"commit_id":"abc123","original_commit_id":"abc123","path":"hello.py","line":2,"body":"human"},
  {"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123","original_commit_id":"abc123","path":"test_hello.py","line":null,"original_line":9,"body":"Missing case"}
]
JSON
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "hello.py:7: Use f-strings" ]
  [ "${lines[1]}" = "    here." ]
  [ "${lines[2]}" = "test_hello.py:9: Missing case" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "copilot_verdict_of takes the verdict line of the latest review for a commit" {
  run copilot_verdict_of abc123 <<'JSON'
[
  {"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"old111","state":"COMMENTED","body":"### 🔴 Changes needed\nold"},
  {"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123","state":"COMMENTED","body":"### 🟢 Approval recommended\nThe only comment is a nit."},
  {"user":{"login":"human"},"commit_id":"abc123","state":"APPROVED","body":"lgtm"}
]
JSON
  [ "$output" = "🟢 Approval recommended" ]
  run copilot_verdict_of nothere <<<'[]'
  [ "$output" = "" ]
}

@test "copilot_reply_body lists the addressed comments and any pushback" {
  printf 'hello.py:7: Use f-strings\n    here.\ntest_hello.py:9: Missing case\n' >"$TMP/c.md"
  run copilot_reply_body 2 abcdef0123456 "$TMP/c.md" "$TMP/none.md"
  [ "${lines[0]}" = "Addressed Copilot review round 2 in abcdef0:" ]
  [ "${lines[1]}" = "- hello.py:7" ]
  [ "${lines[2]}" = "- test_hello.py:9" ]
  [ "${#lines[@]}" -eq 3 ]
  printf 'f-strings are not house style here.\n' >"$TMP/r.md"
  run copilot_reply_body 2 abcdef0123456 "$TMP/c.md" "$TMP/r.md"
  [[ $output == *"Not changed, and why:"*"house style"* ]]
}

@test "copilot_summary_of takes the sentence under the verdict, not a details block" {
  run copilot_summary_of abc123 <<'JSON'
[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123","body":"### 🔵 Needs a closer look\n\nRemove the unrelated helper.\n\n<details>\nmore\n</details>"}]
JSON
  [ "$output" = "Remove the unrelated helper." ]
  run copilot_summary_of abc123 <<'JSON'
[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123","body":"### 🟢 Approval recommended\n<details>\nx\n</details>"}]
JSON
  [ "$output" = "" ]
}

@test "take_flags: --no-copilot" {
  FACTORY_COPILOT=1
  take_flags --no-copilot repo id
  [ "$FACTORY_COPILOT" = 0 ]
  [ "${#ARGS[@]}" -eq 2 ]
}

@test "bd_push: skips without a sync remote, pushes with one, warns on failure, off by knob" {
  FACTORY_BD_PUSH=1
  bd() { # stub: config get -> $BD_REMOTE; dolt push -> $BD_PUSH_RC
    case "$*" in
      *"config get sync.remote") printf '%s\n' "$BD_REMOTE" ;;
      *"dolt push")
        printf 'pushing\n'
        return "$BD_PUSH_RC"
        ;;
    esac
  }
  BD_REMOTE="sync.remote (not set in config.yaml)" BD_PUSH_RC=0 run bd_push repo
  [[ $output == *"no sync remote"* ]]
  BD_REMOTE="git+https://x/y.git" BD_PUSH_RC=0 run bd_push repo
  [[ $output == *"beads pushed to git+https://x/y.git"* ]]
  BD_REMOTE="git+https://x/y.git" BD_PUSH_RC=1 run bd_push repo
  [ "$status" -eq 0 ]
  [[ $output == *"beads push failed"* ]]
  FACTORY_BD_PUSH=0 BD_REMOTE="git+https://x/y.git" BD_PUSH_RC=1 run bd_push repo
  [ -z "$output" ]
}

@test "clean: merged task branches go, unmerged stay unless forced" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" branch factory/toy-m
  git -C "$REPO" worktree add -q "$TMP/wt-m" factory/toy-m
  printf 'x\n' >"$TMP/wt-m/m.txt"
  git -C "$TMP/wt-m" add -A && git -C "$TMP/wt-m" -c user.email=t@example.invalid -c user.name=t commit -qm m
  git -C "$REPO" merge -q factory/toy-m
  git -C "$REPO" checkout -qb factory/toy-u
  printf 'u\n' >"$REPO/u.txt"
  commit_all u
  git -C "$REPO" checkout -q main
  herdr() { printf '{"result":{"worktrees":[]}}'; }
  bd() {
    case "$*" in
      *"config get"*) printf 'sync.remote (not set in config.yaml)\n' ;;
      *) printf 'closed\n' ;;
    esac
  }
  bd_field() { printf 'closed\n'; }
  run cmd_clean "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"cleaned factory/toy-m"* ]]
  [[ $output == *"keeping factory/toy-u"* ]]
  [ ! -e "$TMP/wt-m" ]
  run git -C "$REPO" branch --list 'factory/*' --format='%(refname:short)'
  [ "$output" = "factory/toy-u" ]
  run cmd_clean "$REPO" toy-u --force
  [[ $output == *"cleaned factory/toy-u"* ]]
  [ -z "$(git -C "$REPO" branch --list 'factory/*')" ]
}

@test "planner_kept_hands_off: clean tree passes, dirty tree gets one revert, then dies" {
  make_repo
  WT=$REPO
  RUN_DIR=.factory/run
  planner_kept_hands_off planner
  printf 'sneaky\n' >"$REPO/run.sh"
  ask() { git -C "$REPO" checkout -q -- .; } # the planner reverts when told
  run planner_kept_hands_off planner
  [ "$status" -eq 0 ]
  [[ $output == *"asking it to revert"* ]]
  printf 'sneaky\n' >"$REPO/run.sh"
  ask() { :; } # ...or does not
  run planner_kept_hands_off planner
  [ "$status" -eq 1 ]
  [[ $output == *"must not touch code"* ]]
  mkdir -p "$REPO/.factory/run" && printf 'plan\n' >"$REPO/.factory/run/plan.md"
  git -C "$REPO" checkout -q -- .
  planner_kept_hands_off planner # files under .factory/ are fine
}

@test "set_color sends /color to the agent without waiting" {
  herdr() { printf '%s\n' "$*" >"$TMP/herdr.log"; }
  set_color plan purple
  [ "$(cat "$TMP/herdr.log")" = "agent prompt plan /color purple" ]
}

@test "close_extra_panes closes agent-less panes except the one to keep" {
  herdr() {
    case "$*" in
      "pane list"*) printf '{"result":{"panes":[{"pane_id":"w1:p1","agent":null},{"pane_id":"w1:p2","agent":"claude"},{"pane_id":"w1:p3","agent":null}]}}' ;;
      "pane close"*) printf '%s\n' "$*" >>"$TMP/closed" ;;
    esac
  }
  close_extra_panes w1 w1:p1
  [ "$(cat "$TMP/closed")" = "pane close w1:p3" ]
}

@test "wait_for: chunked waits print a heartbeat and return the final state" {
  fake_task
  toast() { :; }
  : >"$TMP/waits"
  herdr() { # agent wait times out five times, then the agent is idle
    case "$*" in
      "agent wait"*)
        printf 'x' >>"$TMP/waits"
        if (($(wc -c <"$TMP/waits") <= 5)); then
          printf '{"error":{"code":"timeout","message":"t"}}'
          return 1
        fi
        printf '{"result":{"agent":{"agent_status":"idle"}}}'
        ;;
      "agent get"*) printf '{"result":{"agent":{"agent_status":"%s"}}}' "$(cat "$TMP/state")" ;;
      "agent read"*) printf '' ;;
    esac
  }
  printf working >"$TMP/state"
  run wait_for planner 3600000 idle "done"
  [ "$status" -eq 0 ]
  [[ $output == *"still waiting on planner (working, 5 min)"* ]]
  [[ ${lines[-1]} == idle ]]
  # past the timeout but still working: one toast, then it keeps waiting
  : >"$TMP/waits"
  run wait_for planner 120000 idle "done"
  [ "$status" -eq 0 ]
  [[ $output == *"planner is still working after 2 min"* ]]
  [[ ${lines[-1]} == idle ]]
  # past the timeout and not working: that is a stall
  : >"$TMP/waits"
  printf unknown >"$TMP/state"
  run wait_for planner 120000 idle "done"
  [ "$status" -eq 1 ]
  [[ $output == *"no idle done within 2 min and it is unknown"* ]]
}

@test "live_agents counts the named agents alive in a workspace" {
  herdr() {
    printf '{"result":{"agents":[{"name":"t-plan","workspace_id":"w1"},{"name":"t-build","workspace_id":"w1"},{"name":"t-review","workspace_id":"w9"},{"name":null,"workspace_id":"w1"}]}}'
  }
  [ "$(live_agents w1 t-plan t-build t-review)" = 2 ]
  [ "$(live_agents w9 t-plan t-build t-review)" = 1 ]
  [ "$(live_agents w2 t-plan)" = 0 ]
}

@test "guard: a repo's own .factory/guardrails.txt replaces the default list" {
  make_repo
  printf 'FORBIDDEN_WORD\n' >"$REPO/.factory/guardrails.txt"
  commit_all "own rules"
  local pipe='||'
  printf 'run_thing %s true\nFORBIDDEN_WORD here\n' "$pipe" >"$REPO/run.sh"
  commit_all bad
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"FORBIDDEN_WORD"* ]]
  [[ $output != *"run_thing"* ]]
  [[ $output == *".factory/guardrails.txt"* ]]
}

@test "next claims atomically through bd ready --claim" {
  herdr() { :; }
  claude() { :; }
  codex() { :; }
  bd() {
    printf '%s\n' "$*" >>"$TMP/bd.log"
    printf '[]'
  }
  run cmd_next "$TMP"
  [ "$status" -eq 3 ]
  grep -q 'ready --claim --json' "$TMP/bd.log"
}

@test "rebase_onto_base: up to date, clean rebase, and conflicts handed to the builder" {
  make_repo
  on_work_branch
  GATE=true
  # up to date: nothing to do
  rebase_onto_base builder
  # base moves on another file: clean rebase
  git -C "$REPO" checkout -q main
  printf 'other\n' >"$REPO/other.txt"
  commit_all "base moves"
  git -C "$REPO" checkout -q work
  printf 'mine\n' >"$REPO/mine.txt"
  commit_all "work"
  run rebase_onto_base builder
  [ "$status" -eq 10 ]
  git -C "$REPO" merge-base --is-ancestor main work
  # base changes the same line: conflict, the stubbed builder resolves it
  git -C "$REPO" checkout -q main
  printf 'echo base\n' >"$REPO/run.sh"
  commit_all "base edits run.sh"
  git -C "$REPO" checkout -q work
  printf 'echo work\n' >"$REPO/run.sh"
  commit_all "work edits run.sh"
  ask() {
    printf 'echo both\n' >"$REPO/run.sh"
    git -C "$REPO" add run.sh
    GIT_EDITOR=true git -C "$REPO" rebase --continue >/dev/null 2>&1
  }
  run rebase_onto_base builder
  [ "$status" -eq 10 ]
  [[ $output == *"rebase conflicts in: run.sh"* ]]
  [ "$(cat "$REPO/run.sh")" = "echo both" ]
  git -C "$REPO" merge-base --is-ancestor main work
  # a builder that leaves the rebase unfinished is an error
  git -C "$REPO" checkout -q main
  printf 'echo base2\n' >"$REPO/run.sh"
  commit_all "base again"
  git -C "$REPO" checkout -q work
  printf 'echo work2\n' >"$REPO/run.sh"
  commit_all "work again"
  ask() { :; }
  run rebase_onto_base builder
  [ "$status" -eq 1 ]
  [[ $output == *"still in progress"* ]]
  git -C "$REPO" rebase --abort
}

@test "base_ref after the pull request rebase: origin's main, not the stale local one" {
  make_repo
  on_work_branch
  git clone -q --bare "$REPO" "$TMP/origin.git"
  git -C "$REPO" remote add origin "$TMP/origin.git"
  # upstream main touches a protected file; local main stays behind
  git clone -q -b main "$TMP/origin.git" "$TMP/other"
  git -C "$TMP/other" config user.email t@example.invalid
  git -C "$TMP/other" config user.name t
  printf '#!/bin/sh\nexit 0 # stricter\n' >"$TMP/other/.factory/gate"
  git -C "$TMP/other" add -A
  git -C "$TMP/other" commit -qm "upstream touches the gate"
  git -C "$TMP/other" push -q origin main
  printf 'mine\n' >"$REPO/mine.txt"
  commit_all "work"
  [ "$(base_ref)" = main ]
  GATE=true
  rc=0
  rebase_onto_base builder || rc=$?
  [ "$rc" -eq 10 ]
  [ "$(base_ref)" = origin/main ]
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"protected path changed: .factory/gate"* ]]
  run_gate() { :; }
  gate_then_guards builder rebase-pr
  # origin moves on again and is fetched (a sibling task does that) while local main stays stale
  printf 'later\n' >"$TMP/other/later.txt"
  git -C "$TMP/other" add -A
  git -C "$TMP/other" commit -qm "upstream moves on"
  git -C "$TMP/other" push -q origin main
  git -C "$REPO" fetch -q origin main
  [ "$(base_ref)" = origin/main ]
  gate_then_guards builder copilot-1
}

@test "base_ref: the local main when it is newer than origin's, or when there is no origin" {
  make_repo
  on_work_branch
  [ "$(base_ref)" = main ]
  git clone -q --bare "$REPO" "$TMP/origin.git"
  git -C "$REPO" remote add origin "$TMP/origin.git"
  git -C "$REPO" fetch -q origin
  # an unpushed commit on main touches the gate; a branch cut from it is not blamed for that
  git -C "$REPO" checkout -q main
  printf '#!/bin/sh\nexit 0 # local\n' >"$REPO/.factory/gate"
  commit_all "unpushed gate change"
  git -C "$REPO" checkout -q work
  git -C "$REPO" rebase -q main
  printf 'mine\n' >"$REPO/mine.txt"
  commit_all "work"
  [ "$(base_ref)" = main ]
  guard_check "$REPO" "$(base_ref)"
  run guard_check "$REPO" origin/main
  [ "$status" -eq 1 ]
}

@test "gate_then_guards: a guard failure says why" {
  make_repo
  on_work_branch
  GATE=true
  run_gate() { :; }
  printf 'wip\n' >"$REPO/wip.txt"
  run gate_then_guards builder copilot-1
  [ "$status" -eq 1 ]
  [[ $output == *"guardrails failed after copilot-1:"* ]]
  [[ $output == *"uncommitted changes in the worktree"* ]]
}

@test "branch names: slug from the title, found again by bead id" {
  [ "$(slugify 'Add a --farewell CLI flag!')" = "add-a-farewell-cli-flag" ]
  local long
  long=$(slugify 'Ünïcödé & spaces   everywhere, and a very long title that keeps going')
  [[ $long =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
  [ "${#long}" -le 40 ]
  [[ $long == *spaces-everywhere* ]]
  [ "$(bead_of_branch factory/toy-abe-add-a-farewell-cli-flag)" = toy-abe ]
  [ "$(bead_of_branch factory/toy-abe)" = toy-abe ]
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" branch factory/toy-9-some-title
  [ "$(branch_of "$REPO" toy-9)" = factory/toy-9-some-title ]
  [ -z "$(branch_of "$REPO" toy-90)" ]
  git -C "$REPO" worktree add -q "$TMP/wt-9" factory/toy-9-some-title
  [ "$(worktree_of "$REPO" toy-9)" = "$TMP/wt-9" ]
  [ -z "$(worktree_of "$REPO" toy-90)" ]
}

@test "worktree_path: short directory under Herdr's worktree dir, from its config when set" {
  printf '[ui]\nx = 1\n[worktrees]\ndirectory = "~/wt"\n[other]\ndirectory = "nope"\n' >"$TMP/herdr.toml"
  HERDR_CONFIG_PATH=$TMP/herdr.toml run worktree_path /home/me/src/app toy-abe
  [ "$output" = "$HOME/wt/app/factory-toy-abe" ]
  HERDR_CONFIG_PATH=$TMP/missing.toml run worktree_path /home/me/src/app toy-abe
  [ "$output" = "$HOME/.herdr/worktrees/app/factory-toy-abe" ]
}

@test "existing_pr: the branch's open pull request, or nothing" {
  WT=$TMP
  BRANCH=factory/toy-1
  gh() { printf '%s\n' "$GH_OUT"; }
  GH_OUT="https://example.test/pr/7" run existing_pr
  [ "$output" = "https://example.test/pr/7" ]
  gh() { return 1; }
  run existing_pr
  [ -z "$output" ]
}

@test "on_interrupt notes the bead and exits 130" {
  fake_task
  STEP=building
  WS=w9
  WT=$TMP
  bd() { printf '%s\n' "$*" >"$TMP/bd.log"; }
  run on_interrupt "$TMP"
  [ "$status" -eq 130 ]
  [[ $output == *"interrupted during building"* ]]
  grep -q "comment toy-1 Factory: interrupted during building" "$TMP/bd.log"
}

@test "resume markers: planned, built <round>, cleared by --fresh" {
  WT=$TMP
  mkdir -p "$TMP/.factory/run"
  FACTORY_FRESH=0
  [ -z "$(resume_point)" ]
  mark planned
  [ "$(resume_point)" = planned ]
  mark built 2
  [ "$(resume_point)" = "built 2" ]
  FACTORY_FRESH=1
  [ -z "$(resume_point)" ]
  [ ! -e "$TMP/.factory/run/state" ]
}

@test "show_md: glow renders when present, plain indent otherwise" {
  printf '# Plan\n' >"$TMP/plan.md"
  glow() { printf 'GLOW %s stdin=%s\n' "$1" "$(cat)"; }
  run show_md "$TMP/plan.md" <<<"the human's answer"
  [ "$output" = "GLOW $TMP/plan.md stdin=" ]
  unset -f glow
  mkdir -p "$TMP/bin" && ln -s "$(command -v sed)" "$TMP/bin/sed"
  PATH=$TMP/bin run show_md "$TMP/plan.md"
  [ "$output" = "    # Plan" ]
}

@test "help and unknown command" {
  run main help
  [ "$status" -eq 0 ]
  [[ $output == *"factory run"* ]]
  run main bogus
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command"* ]]
}
