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

# the globals approve_plan reads for its messages
fake_task() {
  TASK_ID=toy-1
  TASK_TITLE=t
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
  [ "${lines[2]}" = "src/legacy/*" ]
  [ "${#lines[@]}" -eq 3 ]
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
  FACTORY_PLAN_APPROVAL=ask
  approve_plan planner "$TMP/plan.md" <<<"a"
  run approve_plan planner "$TMP/plan.md" <<<"b"
  [ "$status" -eq 3 ]
  FACTORY_PLAN_APPROVAL=auto
  approve_plan planner "$TMP/plan.md" </dev/null
  FACTORY_PLAN_APPROVAL=ask
  ask() { printf 'asked %s: %s\n' "$1" "$2"; }
  run approve_plan planner "$TMP/plan.md" <<<$'r\nsplit the module\na'
  [ "$status" -eq 0 ]
  [[ $output == *"asked planner: The human reviewed"*"split the module"* ]]
}

@test "plan approval: files from factory approve / reject, no terminal" {
  fake_task
  FACTORY_PLAN_APPROVAL=ask
  FACTORY_POLL_SECONDS=1
  toast() { :; }
  printf 'the plan\n' >"$TMP/plan.md"
  ask() {
    printf 'asked %s: %s\n' "$1" "$2"
    : >"$TMP/plan.approved" # the human approves after the revision
  }
  # the human's reject arrives while the factory is already waiting
  (
    sleep 2
    printf 'too big, split it\n' >"$TMP/plan-reject.md"
  ) &
  run approve_plan planner "$TMP/plan.md" </dev/null
  wait
  [ "$status" -eq 0 ]
  [[ $output == *"no terminal"* ]]
  [[ $output == *"asked planner: "*"too big, split it"* ]]
  [[ $output == *"approved via file"* ]]
  [ ! -e "$TMP/plan.approved" ]
}

@test "approve and reject subcommands find the task worktree" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" worktree add -q -b factory/toy-9 "$TMP/wt-9"
  mkdir -p "$TMP/wt-9/.factory/run"
  cmd_approve "$REPO" toy-9
  [ -e "$TMP/wt-9/.factory/run/plan.approved" ]
  cmd_reject "$REPO" toy-9 "use argparse"
  [ "$(cat "$TMP/wt-9/.factory/run/plan-reject.md")" = "use argparse" ]
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

@test "pr_body carries task, plan and checks" {
  make_repo
  fake_task
  TASK_DESC="details"
  WT=$REPO
  GATE="bash .factory/gate"
  BRANCH=factory/toy-1
  mkdir -p "$REPO/.factory/run"
  printf 'the plan\n' >"$REPO/.factory/run/plan.md"
  run pr_body 2
  [[ $output == "Bead toy-1: t"* ]]
  [[ $output == *"details"*"the plan"*"passed (round 2)"*"factory/toy-1"* ]]
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

@test "help and unknown command" {
  run main help
  [ "$status" -eq 0 ]
  [[ $output == *"factory run"* ]]
  run main bogus
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command"* ]]
}
