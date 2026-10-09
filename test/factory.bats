#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Unit tests for factory's functions; Herdr, Beads, gh and the agents are stubbed.

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 # the fixtures' git ignores this machine's config
  unset "${!FACTORY_@}"                                    # and the knobs the shell exported
  export FACTORY_GUARDRAILS="$BATS_TEST_DIRNAME/../guardrails.txt"
  # shellcheck source=../factory
  source "$BATS_TEST_DIRNAME/../factory"
  FACTORY_REQUIRE_TESTS=0 # the fixtures below change code without tests on purpose
  TMP=$(mktemp -d)
  toast() { :; }                # no desktop notifications from the tests
  glow() { cat "$1"; }          # nor this machine's glow and its config
  pause_for_pane_reply() { :; } # nor the pause for an agent's reply in its pane
  # the human's answers go to a file the tests read, not to a bead; the real one is kept
  eval "real_$(declare -f record_answer)"
  record_answer() { printf '%s\n' "$2" >>"$TMP/recorded"; }
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

# add_origin: a bare clone of REPO becomes its origin remote
add_origin() {
  git clone -q --bare "$REPO" "$TMP/origin.git"
  git -C "$REPO" remote add origin "$TMP/origin.git"
}

# task_worktree: a factory/toy-9 checkout with its run dir, as a waiting run has it
task_worktree() {
  git -C "$REPO" checkout -q main
  git -C "$REPO" worktree add -q -b factory/toy-9 "$TMP/wt-9"
  mkdir -p "$TMP/wt-9/.factory/run"
}

# the globals human_gate reads for its messages
fake_task() {
  TASK_ID=toy-1
  TASK_TITLE=t
}

# plan_ready: a plan waiting for the human, as plan_phase hands it to human_gate; a note's
# plan round only says that it ran
plan_ready() {
  fake_task
  FACTORY_APPROVAL=ask
  WT=$TMP
  printf 'the plan\n' >"$TMP/plan.md"
  planner_kept_hands_off() { :; }
  tree_state() { :; } # its snapshot of the tree, which is no git repo here
  plan_round() { printf 'plan round %s on the note: %s\n' "$1" "$2"; }
}

# gate_opens [kind]: wait until the gate in $TMP listens for the plan (or the build), as a
# human in a pane would: an answer sent before would be one the gate drops as stale. After a
# minute it gives up and lets the answer go, so that a gate that never opens fails its test
# instead of hanging it; on a busy machine a gate can take many seconds to open.
gate_opens() {
  local _
  for _ in $(seq 600); do
    grep -qs "^${1:-plan} " "$TMP/waiting" && return 0
    sleep 0.1
  done
}

# the branch globals the gates and guards read, as task_context and open_workspace set them
on_work_branch() {
  WT=$REPO
  BASE=main
  BRANCH=work
}

commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "$1"
}

# resolve_task and task_context set globals; print them so tests can assert on output.
# They sit above the tests: a global assigned in a test body and read further down the
# file is a lost subshell change to shellcheck (SC2031).
resolved() {
  resolve_task "$@" 2>/dev/null
  printf '%s: %s\n---\n%s' "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"
}

context_of() {
  task_context "$1"
  printf '%s\n' "$GATE" "$BASE" "$BRANCH" "$PLAN_AGENT $BUILD_AGENT $REVIEW_AGENT"
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

@test "check_efforts: the defaults pass, ultra only for the reviewer, a typo dies" {
  run check_efforts
  [ "$status" -eq 0 ]
  FACTORY_PLAN_EFFORT=max FACTORY_BUILD_EFFORT=low FACTORY_REVIEW_EFFORT=ultra run check_efforts
  [ "$status" -eq 0 ]
  FACTORY_BUILD_EFFORT=ultra run check_efforts
  [ "$status" -eq 1 ]
  [[ $output == *"FACTORY_BUILD_EFFORT=ultra: not an effort level (low, medium, high, xhigh, max)"* ]]
  FACTORY_REVIEW_EFFORT='high xhigh' run check_efforts
  [ "$status" -eq 1 ]
  [[ $output == *"(low, medium, high, xhigh, max, ultra)"* ]]
}

@test "check_push: a run that opens a pull request first checks that origin takes a push without a prompt, and pushes nothing" {
  make_repo
  gh() { :; } # installed
  FACTORY_PR=0
  run check_push "$REPO" # no pull request, no check, origin or not
  [ "$status" -eq 0 ]
  FACTORY_PR=1
  run check_push "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"$REPO has no origin remote to push the pull request's branch to"* ]]
  add_origin
  git() { # the push may not ask for credentials
    [[ $* != *" push "* ]] || printf '%s\n' "${GIT_TERMINAL_PROMPT:-unset}" >>"$TMP/prompt"
    command git "$@"
  }
  run check_push "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/prompt")" = 0 ]
  [ -z "$(git -C "$TMP/origin.git" for-each-ref 'refs/heads/factory/')" ] # a dry run
  # an origin that takes no push: git says why, then Factory what to do
  git -C "$REPO" remote set-url origin "$TMP/gone.git"
  run check_push "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"gone.git"*"origin takes no push from $REPO without a prompt"*"gh auth setup-git"*"FACTORY_PR=0"* ]]
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

@test "guard: patterns that begin with a hash are applied, not read as comments" {
  make_repo
  # Build the bad strings at runtime so this file passes its own guard check.
  local hash='#'
  printf 'a = 1  %s noqa\nb = f()  %s type: ignore\nc = g()  %s nosec\nif d:  %s pragma: no cover\n' \
    "$hash" "$hash" "$hash" "$hash" >"$REPO/tool.py"
  printf '%s shellcheck disable=SC2086\necho hi\n' "$hash" >"$REPO/tool.sh"
  printf '%s[allow(dead_code)]\nfn unused() {}\n%s[ignore]\nfn later() {}\n' "$hash" "$hash" >"$REPO/lib.rs"
  commit_all suppressed
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"tool.py: a = 1  $hash noqa"* ]]
  [[ $output == *"tool.py: b = f()  $hash type: ignore"* ]]
  [[ $output == *"tool.py: c = g()  $hash nosec"* ]]
  [[ $output == *"tool.py: if d:  $hash pragma: no cover"* ]]
  [[ $output == *"tool.sh: $hash shellcheck disable=SC2086"* ]]
  [[ $output == *"lib.rs: ${hash}[allow(dead_code)]"* ]]
  [[ $output == *"lib.rs: ${hash}[ignore]"* ]]
}

@test "guardrails.txt: no line that reads as a pattern is commented out" {
  # The loader drops every line whose first non-blank is a hash, so a comment is a hash
  # and a space, and a pattern never starts with one: [#] stands for a literal hash.
  run -1 grep -nE '^[[:space:]]*#[^[:space:]]' "$FACTORY_GUARDRAILS"
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

@test "agents stub: short, links CLAUDE.md, names the gate" {
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

@test "guard: an uncommitted change under .factory/, such as the gate, counts; only its run dir is Factory's" {
  make_repo
  mkdir -p "$REPO/.factory/run" && printf 'plan\n' >"$REPO/.factory/run/plan.md"
  run tree_dirty "$REPO"
  [ "$status" -eq 1 ]
  printf 'exit 0\n' >>"$REPO/.factory/gate"
  run tree_dirty "$REPO"
  [ "$status" -eq 0 ]
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"uncommitted changes in the worktree"* ]]
}

@test "guard: docs-only change needs no test" {
  make_repo
  printf 'notes\n' >"$REPO/NOTES.md"
  commit_all docs
  run guard_check "$REPO" main
  [ "$status" -eq 0 ]
}

@test "plan approval: terminal answers" {
  plan_ready
  human_gate plan planner "$TMP" <<<"a"
  run human_gate plan planner "$TMP" <<<"b"
  [ "$status" -eq 3 ]
  FACTORY_APPROVAL=auto
  human_gate plan planner "$TMP" </dev/null
  FACTORY_APPROVAL=ask
  ask() {
    printf 'asked %s: %s\n' "$1" "$2"
    printf 'gate in the round: %s\n' "$(gate_waiting "$TMP" || printf closed)"
  }
  role_of() { # the note prompt: the panes are told the terminal has the answer
    printf 'gate while typing: %s\n' "$(gate_waiting "$TMP" || printf closed)" >&2
    printf planner
  }
  run human_gate plan planner "$TMP" <<<$'r\nsplit the module\na'
  [ "$status" -eq 0 ]
  [[ $output != *"no terminal"* ]]
  [[ $output == *"gate while typing: typing"*"asked planner: The human reviewed"*"split the module"*"gate in the round: note"*"plan round 1 on the note: split the module"* ]]
  # only the keys shown mean anything: y, n and an empty note ask again, without re-rendering;
  # after the empty note the gate listens to the panes again
  no_terminal_hint() { # the terminal is gone; a pane answers
    printf 'gate after the note: %s\n' "$(gate_waiting "$TMP" || printf closed)" >&2
    : >"$TMP/approved"
  }
  run human_gate plan planner "$TMP" <<<$'y\nn\nr\n'
  [ "$status" -eq 0 ]
  [[ $output == *"a, p, r or b?"*"a, p, r or b?"*"gate while typing: typing"*"a, p, r or b?"*"gate after the note: plan"*"approved via file"* ]]
  [ "$(grep -c 'plan for toy-1' <<<"$output")" -eq 1 ]
  # a pane's answer that came in while the terminal waited for its key goes before that r
  read() { # every read in the script passes -r first
    if [[ $* == "-r -t "* && ! -e $TMP/seeded ]]; then
      : >"$TMP/seeded"
      : >"$TMP/approved"
    fi
    shift
    builtin read -r "$@"
  }
  run human_gate plan planner "$TMP" <<<$'r\nsplit it\na'
  unset -f read
  [ "$status" -eq 0 ]
  [[ $output == *"approved via file"* ]]
  [[ $output != *"note for the planner"* ]]
}

@test "an approval gate opens afresh: answers left from before go, and a plan waiver with them" {
  plan_ready
  printf 'stale\n' >"$TMP/reject.md"
  : >"$TMP/aborted"
  : >"$TMP/approved"
  : >"$TMP/allow-protected"
  run human_gate plan planner "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  [[ $output != *"via file"* ]]
  [ ! -e "$TMP/reject.md" ]
  [ ! -e "$TMP/aborted" ]
  [ ! -e "$TMP/allow-protected" ]
}

@test "plan approval: the planner's change note is shown once, below the revised plan" {
  fake_task
  [[ $(plan_note_prompt "split it") == *"says: split it"*"plan-changes.md"* ]]
  printf 'the plan\n' >"$TMP/plan.md"
  printf 'split the module in two\n' >"$TMP/plan-changes.md"
  run show_for_approval plan "$TMP"
  [[ $output == *"plan for toy-1"*"the plan"*"changed after your note"*"split the module in two"* ]]
  [ ! -e "$TMP/plan-changes.md" ]
  run show_for_approval plan "$TMP"
  [[ $output != *"changed after your note"* ]]
}

@test "plan approval: the last plan review round's verdicts and where its notes are" {
  fake_task
  printf 'the plan\n' >"$TMP/plan.md"
  run show_for_approval plan "$TMP"
  [[ $output != *"plan review round"* ]]
  printf 'VERDICT: REVISE\n' >"$TMP/plan-review-1.md"
  printf 'VERDICT: APPROVE\n' >"$TMP/plan-review-1-build.md"
  printf 'VERDICT: APPROVE\n' >"$TMP/plan-review-2.md"
  printf 'VERDICT: REVISE\n' >"$TMP/plan-review-2-build.md"
  touch -t 202001010000 "$TMP"/plan-review-*.md # the planner revised the plan after them
  run show_for_approval plan "$TMP"
  [[ $output == *"plan review round 2: APPROVE REVISE (plan changed since), notes in $TMP/plan-review-2.md and $TMP/plan-review-2-build.md"* ]]
  printf 'VERDICT: APPROVE\n' >"$TMP/plan-review-2-build.md"
  touch -t 202001010000 "$TMP/plan.md" # both approved the plan as it stands
  run show_for_approval plan "$TMP"
  [[ $output == *"plan review round 2: APPROVE APPROVE, notes in"* ]]
  touch -t 201901010000 "$TMP"/plan-review-*.md # then a note or an edit changed the plan
  run show_for_approval plan "$TMP"
  [[ $output == *"plan review round 2: APPROVE APPROVE (plan changed since), notes in"* ]]
}

@test "approval keys: coloured by what they do at a terminal, plain otherwise" {
  [ "$(key a)$(key p)$(key r)$(key b)" = aprb ] # the tests' stderr is no terminal
  run script -qec "bash -c 'source \"$BATS_TEST_DIRNAME/../factory\"; key a; key p; key r; key b'" /dev/null
  [ "$status" -eq 0 ]
  [[ $output == *$'\033[1;32ma\033[0m\033[1;32mp\033[0m\033[1;33mr\033[0m\033[1;31mb\033[0m'* ]]
}

@test "gate_dialog_shown: a dialog on the screen counts, however herdr writes the screen" {
  herdr() { # the dialog's chip first, the rest after a moment, when a grep -q on the pipe has gone
    printf ' ☐ fy plan\nApprove the plan for toy-1?\n'
    sleep 0.5
    printf 'Enter to select · ↑/↓ to navigate · Esc to cancel\n'
  }
  gate_dialog_shown planner plan
  gate_dialog_shown planner
  run gate_dialog_shown planner build
  [ "$status" -eq 1 ]
  herdr() { return 1; } # no screen to read
  run gate_dialog_shown planner plan
  [ "$status" -eq 1 ]
}

@test "approval dialog: shown in the agent's pane when the gate opens, dismissed once answered elsewhere" {
  plan_ready
  herdr() { # the dialog shows once the prompt for it went in, until Esc; Herdr reads the agent as idle
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent wait"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      "agent read"*)
        if grep -q '^agent prompt' "$TMP/herdr.log" && ! grep -q '^agent send-keys' "$TMP/herdr.log"; then
          printf ' ☐ fy plan\nApprove the plan for toy-1, or type a note to have it revised?\nEnter to select · ↑/↓ to navigate · Esc to cancel\n'
        fi
        ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  # agents started without the hook, by an earlier version, show none
  run human_gate plan planner "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/herdr.log" ]
  printf '{}' >"$TMP/hooks-plan.json"
  run human_gate plan planner "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  grep -q '^agent prompt planner Ask the human with your AskUserQuestion tool: one question, header "fy plan"' "$TMP/herdr.log"
  grep -qx 'agent send-keys planner esc' "$TMP/herdr.log"
  [[ $output == *"planner: dismissed its approval dialog, answered elsewhere"* ]]
  [[ $output == *"talk to the planner, after Esc on its dialog, first if you like"* ]]
  # answered in the dialog itself, it is gone by then: no Esc
  : >"$TMP/herdr.log"
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent wait"*) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  run human_gate plan planner "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'send-keys' "$TMP/herdr.log")" -eq 0 ]
  [ "$(grep -c '^plan approved$' "$TMP/recorded")" -eq 3 ]
}

@test "approval dialog: never typed over a question the agent asks already, nor that one dismissed" {
  plan_ready
  PLAN_AGENT=planner
  printf '{}' >"$TMP/hooks-plan.json"
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent read"*) printf ' ☐ Format\nWhich format?\nEnter to select · ↑/↓ to navigate · Esc to cancel\n' ;;
      "agent wait"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  run human_gate plan planner "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  [[ $output == *"planner asks you something already"* ]]
  [ "$(grep -c 'agent prompt' "$TMP/herdr.log")" -eq 0 ]
  [ "$(grep -c 'send-keys' "$TMP/herdr.log")" -eq 0 ]
  # its approval dialog still open from before, as after a resume, answers this gate too
  : >"$TMP/herdr.log"
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent read"*) grep -q '^agent send-keys' "$TMP/herdr.log" || printf ' ☐ fy plan\nApprove the plan for toy-1?\nEnter to select · ↑/↓ to navigate · Esc to cancel\n' ;;
      "agent wait"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  FACTORY_POLL_SECONDS=1
  (
    gate_opens
    : >"$TMP/approved"
  ) 3>&- &
  run human_gate plan planner "$TMP" </dev/null
  wait
  [ "$status" -eq 0 ]
  [[ $output == *"planner shows the plan's approval dialog already"* ]]
  [[ $output == *"waiting for your answer in the planner's dialog, or with these in another of the task's panes"* ]]
  [ "$(grep -c 'agent prompt' "$TMP/herdr.log")" -eq 0 ]
}

@test "plan approval: files from factory approve / reject, no terminal" {
  plan_ready
  FACTORY_POLL_SECONDS=1
  ask() { # the note's turn: the gate is closed meanwhile, and an approval sent anyway is dropped
    printf 'asked %s: %s\n' "$1" "$2"
    printf 'gate in the round: %s\n' "$(gate_waiting "$TMP" || printf closed)"
    : >"$TMP/approved"
    ( # the human approves once the plan is back, and the gate must still be waiting then
      gate_opens
      sleep 1.5
      if [[ -e $TMP/waiting ]]; then : >"$TMP/still-waiting"; fi
      : >"$TMP/approved"
    ) >/dev/null 2>&1 3>&- &
  }
  pause_for_pane_reply() { printf 'pause for the reply, gate %s\n' "$(gate_waiting "$TMP" || printf closed)"; }
  # the human's reject arrives once the factory waits
  (
    gate_opens
    printf 'too big, split it\n' >"$TMP/reject.md"
  ) 3>&- &
  run human_gate plan planner "$TMP" </dev/null
  wait
  [ "$status" -eq 0 ]
  [[ $output == *"note received via file"*"pause for the reply, gate note"*"asked planner: "*"too big, split it"*"gate in the round: note"* ]]
  [ -e "$TMP/still-waiting" ]
  # the plan comes back after the note, and with it where to answer
  [[ $output == *"note received via file"*"plan for toy-1"*"no terminal to answer from; waiting for your answer in one of the task's panes: !fy approve, !fy reject '<note>' or !fy abort"*"approved via file"*"pause for the reply, gate closed" ]]
  [ "$(cat "$TMP/recorded")" = $'note on the plan: too big, split it\nplan approved' ]
  [ "$(grep -c 'no terminal to answer from' <<<"$output")" -eq 2 ]
  [ ! -e "$TMP/approved" ]
  [ ! -e "$TMP/waiting" ]
  # the gate names itself and this run while it waits; an abort file ends it with 3
  (
    gate_opens
    if [[ -e $TMP/waiting ]]; then cp "$TMP/waiting" "$TMP/seen"; fi
    : >"$TMP/aborted"
    sleep 4
    : >"$TMP/approved" # ends a gate that ignores the abort, so a regression fails instead of hanging
  ) 3>&- &
  run human_gate plan planner "$TMP" </dev/null
  wait
  [ "$status" -eq 3 ]
  [[ $output == *"aborted via file"* ]]
  [ "$(cat "$TMP/seen")" = "plan $$" ]
  [ ! -e "$TMP/waiting" ]
  [ ! -e "$TMP/aborted" ]
}

@test "approve, reject and abort find the task worktree and need a run waiting there" {
  make_repo
  task_worktree
  local run="$TMP/wt-9/.factory/run"
  run cmd_approve "$REPO" toy-9
  [ "$status" -eq 1 ]
  [[ $output == *"nothing of toy-9 waits for approval"* ]]
  [ ! -e "$run/approved" ]
  printf 'plan %s\n' "$$" >"$run/waiting" # a live run at plan approval
  cmd_approve "$REPO" toy-9
  [ -e "$run/approved" ]
  cmd_reject "$REPO" toy-9 "use argparse"
  [ "$(cat "$run/reject.md")" = "use argparse" ]
  run cmd_reject "$REPO" toy-9 " "
  [ "$status" -eq 1 ]
  [[ $output == *"empty note"* ]]
  cmd_abort "$REPO" toy-9
  [ -e "$run/aborted" ]
  rm -f "$run/approved" "$run/reject.md" "$run/aborted"
  printf 'note %s\n' "$$" >"$run/waiting" # the review round after a plan note
  for c in "cmd_approve $REPO toy-9" "cmd_reject $REPO toy-9 later" "cmd_abort $REPO toy-9"; do
    run $c
    [ "$status" -eq 1 ]
    [[ $output == *"the plan of toy-9 is in the review round after your note; answer once it is back"* ]]
  done
  printf 'typing %s\n' "$$" >"$run/waiting" # a note typed at Factory's terminal
  for c in "cmd_approve $REPO toy-9" "cmd_reject $REPO toy-9 later" "cmd_abort $REPO toy-9"; do
    run $c
    [ "$status" -eq 1 ]
    [[ $output == *"Factory's terminal is taking a note on toy-9; finish it there"* ]]
  done
  [ ! -e "$run/approved" ]
  [ ! -e "$run/reject.md" ]
  [ ! -e "$run/aborted" ]
  printf 'build %s\n' "$$" >"$run/waiting"
  run cmd_approve "$REPO" toy-9 --allow-protected
  [ "$status" -eq 1 ]
  [[ $output == *"--allow-protected is for the plan"* ]]
  printf 'questions %s\n' "$$" >"$run/waiting" # questions wait, not an approval
  run cmd_approve "$REPO" toy-9
  [ "$status" -eq 1 ]
  printf 'plan 999999999\n' >"$run/waiting" # a run that is gone
  run cmd_abort "$REPO" toy-9
  [ "$status" -eq 1 ]
  run cmd_approve "$REPO" toy-404
  [ "$status" -eq 1 ]
  [[ $output == *"no worktree"* ]]
}

@test "dialog_hooks: the agents' question dialogs report to factory dialog-hook, told the task and its run dir, as they open, when answered, and as each turn ends" {
  FACTORY_HOME="$TMP/my factory" TASK_ID=toy-9 WT=$TMP/wt-9
  run dialog_hooks plan
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher, .hooks.PostToolUse[0].matcher' <<<"$output" | paste -sd,)" = AskUserQuestion,AskUserQuestion ]
  [ "$(jq -r '.hooks.Stop[0].matcher // "every turn"' <<<"$output")" = "every turn" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' <<<"$output")" = "$TMP/my\\ factory/factory dialog-hook plan toy-9 $TMP/wt-9/.factory/run" ]
  [ "$(jq -r '[.hooks[][0].hooks[0].command] | unique | length' <<<"$output")" -eq 1 ]
}

@test "dialog-hook: Factory's approval dialog answers the gate as approve, reject and abort do; other answers are recorded" {
  make_repo
  task_worktree
  local run="$TMP/wt-9/.factory/run" opts='[{"label":"Approve"},{"label":"Approve, allow protected paths"},{"label":"Abort"}]'
  local q="Approve the plan for toy-9, or type a note to have it revised?"
  hook() { # event [cwd] -> a hook's input with no answer in it
    jq -n --arg e "$1" --arg cwd "${2:-$TMP/wt-9}" --arg tp "$TMP/transcript.jsonl" \
      '{cwd: $cwd, hook_event_name: $e, tool_name: "AskUserQuestion", tool_use_id: "toolu_1", transcript_path: $tp}'
  }
  dialog() { # header question options answer [notes] -> the answered dialog's hook input, as Claude Code sends it
    jq -n --arg cwd "${CWD:-$TMP/wt-9}" --arg h "$1" --arg q "$2" --argjson o "$3" --arg a "$4" --arg n "${5:-}" \
      '{cwd: $cwd, hook_event_name: "PostToolUse", tool_name: "AskUserQuestion", tool_input: {questions: [{header: $h, question: $q, options: $o}]}, tool_response: ({answers: {($q): $a}} + if $n == "" then {} else {annotations: {($q): {notes: $n}}} end)}'
  }
  # the planner's own question: its mark names the tool call. What changed while it was open is
  # the human's, what the planner changed before is not, whatever the agent's cwd.
  mkdir "$TMP/wt-9/src"
  printf 'sneaky\n' >>"$TMP/wt-9/run.sh"
  hook PreToolUse "$TMP/wt-9/src" | cmd_dialog_hook plan toy-9 "$run"
  [ "$(cat "$run/asking-plan")" = "toolu_1	$TMP/transcript.jsonl" ]
  printf 'id,n\n' >"$TMP/wt-9/sample.csv"
  CWD=$TMP/wt-9/src dialog Format "Which format?" '[{"label":"CSV"},{"label":"JSON"}]' CSV "keep the header" | cmd_dialog_hook plan toy-9 "$run"
  [ ! -e "$run/asking-plan" ]
  [ ! -e "$run/tree-at-ask" ]
  [ "$(cat "$run/tree-at-answer")" = "?? sample.csv" ]
  [ "$(cat "$TMP/recorded")" = "the planner asked: Which format? Answer: CSV Notes: keep the header" ]
  dialog Format "Which?" '[{"label":"CSV"}]' "(notes only)" "either works" | cmd_dialog_hook plan toy-9 "$run"
  [ "$(tail -1 "$TMP/recorded")" = "the planner asked: Which? Answer: (no option) Notes: either works" ]
  # Chat about this closes a dialog with no answer: the turn's end clears the mark, and what the
  # human changed meanwhile is still theirs
  hook PreToolUse | cmd_dialog_hook plan toy-9 "$run"
  printf 'more\n' >"$TMP/wt-9/notes.txt"
  hook Stop | cmd_dialog_hook plan toy-9 "$run"
  [ ! -e "$run/asking-plan" ]
  [ "$(tail -1 "$run/tree-at-answer")" = "?? notes.txt" ]
  git -C "$TMP/wt-9" checkout -q -- run.sh
  rm -f "$TMP/wt-9/sample.csv" "$TMP/wt-9/notes.txt" "$run/tree-at-answer"
  # the hook as Claude Code runs it, through main
  run main dialog-hook build toy-9 "$run" < <(hook PreToolUse)
  [ "$status" -eq 0 ]
  [ -e "$run/asking-build" ]
  hook Stop | cmd_dialog_hook build toy-9 "$run"
  [ ! -e "$run/asking-build" ]
  # no run dir: nothing to mark, and an answer says so
  hook PreToolUse | cmd_dialog_hook plan toy-9 "$TMP/gone"
  run cmd_dialog_hook plan toy-9 "$TMP/gone" < <(dialog Format "Which format?" '[{"label":"CSV"}]' CSV)
  [ "$status" -eq 1 ]
  [[ $output == *"no run dir of a task for this dialog; the answer went to the agent only"* ]]
  # an agent's hook from before it was told them finds the task by its cwd
  hook PreToolUse | cmd_dialog_hook plan
  [ -e "$run/asking-plan" ]
  rm -f "$run/asking-plan" "$run/tree-at-ask"
  # Factory's own dialog, while the plan waits
  printf 'plan %s\n' "$$" >"$run/waiting"
  dialog "fy plan" "$q" "$opts" Approve | cmd_dialog_hook plan toy-9 "$run"
  [ -e "$run/approved" ]
  [ ! -e "$run/allow-protected" ]
  rm -f "$run/approved"
  dialog "fy plan" "$q" "$opts" "Approve, allow protected paths" | cmd_dialog_hook plan toy-9 "$run"
  [ -e "$run/approved" ]
  [ -e "$run/allow-protected" ]
  rm -f "$run/approved" "$run/allow-protected"
  dialog "fy plan" "$q" "$opts" Abort | cmd_dialog_hook plan toy-9 "$run"
  [ -e "$run/aborted" ]
  rm -f "$run/aborted"
  local note=$'keep `x` as is, don\'t touch $HOME\nand split it'
  dialog "fy plan" "$q" "$opts" "$note" | cmd_dialog_hook plan toy-9 "$run"
  [ "$(cat "$run/reject.md")" = "$note" ]
  rm -f "$run/reject.md"
  # a dialog for another gate, a closed gate, or a choice Factory did not offer: nothing sent
  printf 'build %s\n' "$$" >"$run/waiting"
  run cmd_dialog_hook plan toy-9 "$run" < <(dialog "fy plan" "$q" "$opts" Approve)
  [ "$status" -eq 1 ]
  [[ $output == *"that dialog was about the plan of toy-9, whose build waits now"* ]]
  rm -f "$run/waiting"
  run cmd_dialog_hook plan toy-9 "$run" < <(dialog "fy plan" "$q" "$opts" Approve)
  [ "$status" -eq 1 ]
  [[ $output == *"nothing of toy-9 waits for approval"* ]]
  printf 'plan %s\n' "$$" >"$run/waiting"
  run cmd_dialog_hook plan toy-9 "$run" < <(dialog "fy plan" "$q" '[{"label":"Approve"},{"label":"Maybe"}]' Maybe)
  [ "$status" -eq 1 ]
  [[ $output == *'choice "Maybe" is none Factory knows'* ]]
  [ ! -e "$run/approved" ]
  [ ! -e "$run/reject.md" ]
  [ ! -e "$run/aborted" ]
}

@test "record_answer: each answer goes into the run dir's decisions and onto the bead" {
  make_repo
  local run="$REPO/.factory/run"
  mkdir -p "$run"
  TASK_ID=toy-1
  bd() { printf '%s\n' "$*" >>"$TMP/bd.log"; }
  real_record_answer "$run" "plan approved"
  real_record_answer "$run" $'note on the plan: split it\nand test it'
  [ "$(grep -c '^- [0-9-]* [0-9:]* ' "$run/decisions.md")" -eq 2 ]
  [[ $(cat "$run/decisions.md") == *"plan approved"*"note on the plan: split it"$'\n'"  and test it" ]]
  [ "$(head -1 "$TMP/bd.log")" = "-C $REPO comment toy-1 Factory: plan approved" ]
  grep -q 'Factory: note on the plan: split it' "$TMP/bd.log"
}

@test "in a task's worktree, as in an agent's pane, the commands take the task from there" {
  make_repo
  task_worktree
  local run="$TMP/wt-9/.factory/run"
  printf 'plan %s\n' "$$" >"$run/waiting"
  cd "$TMP/wt-9"
  task_args use argparse
  [ "${TARGS[*]}" = "$REPO toy-9 use argparse" ]
  task_args "$REPO" toy-9 --allow-protected # a repo and a bead named still win
  [ "${TARGS[*]}" = "$REPO toy-9 --allow-protected" ]
  run main approve --allow-protected
  [ "$status" -eq 0 ]
  [ -e "$run/approved" ]
  [ -e "$run/allow-protected" ]
  run main reject use argparse, not getopt
  [ "$(cat "$run/reject.md")" = "use argparse, not getopt" ]
  run main abort
  [ -e "$run/aborted" ]
  # a repo named with an id of another shape is an error, never a note for the task here
  rm -f "$run/reject.md"
  run main reject "$REPO" my_repo-x7k use argparse
  [ "$status" -eq 1 ]
  [[ $output == *"my_repo-x7k is not a bead id Factory takes"* ]]
  [ ! -e "$run/reject.md" ]
  cd "$REPO" # the repo's own checkout is no task's worktree
  run main approve
  [ "$status" -eq 1 ]
  [[ $output == *"usage: factory approve [<repo> <bead-id>]"* ]]
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

@test "compose_task: a title on the first line keeps the whole description" {
  VISUAL="" EDITOR=""
  run composed <<'IN'
Add CSV export

Users want to download the table.
Keep the delimiter configurable.
IN
  [ "$status" -eq 0 ]
  [ "$output" = $'Add CSV export\n---\nUsers want to download the table.\nKeep the delimiter configurable.' ]
  run composed <<'IN'
Add CSV export
Users want to download the table.
IN
  [ "$output" = $'Add CSV export\n---\nUsers want to download the table.' ]
}

@test "pr_body: the human's decisions, when there were any" {
  fake_task
  WT=$TMP
  mkdir -p "$TMP/.factory/run"
  pr_checks() { :; }
  run pr_body
  [[ $output != *"Decisions"* ]]
  printf -- '- 2026-10-06 14:02 plan approved\n' >"$TMP/.factory/run/decisions.md"
  run pr_body
  [[ $output == *"<summary>Plan</summary>"*"<summary>Decisions</summary>"*"- 2026-10-06 14:02 plan approved"*"</details>" ]]
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
  [[ $output == *"$TAG guardrails: protected-path check waived by the human"* ]]
  printf 'echo x\n' >>"$REPO/run.sh"
  run guard_check "$REPO" main
  [ "$status" -eq 1 ]
  [[ $output == *"uncommitted"* ]]
}

@test "approve --allow-protected and the p answer write the waiver" {
  make_repo
  task_worktree
  printf 'plan %s\n' "$$" >"$TMP/wt-9/.factory/run/waiting"
  cmd_approve "$REPO" toy-9 --allow-protected
  [ -e "$TMP/wt-9/.factory/run/allow-protected" ]
  [ -e "$TMP/wt-9/.factory/run/approved" ]
  plan_ready
  human_gate plan planner "$TMP" <<<"p"
  [ -e "$TMP/allow-protected" ]
}

@test "build approval: a approves; r and the reject file hand the note back with 4" {
  make_repo
  printf 'echo more\n' >>"$REPO/run.sh"
  commit_all change
  fake_task
  on_work_branch
  FACTORY_APPROVAL=ask
  FACTORY_POLL_SECONDS=1
  : >"$TMP/allow-protected" # the plan's approval waived the check for the build
  run human_gate build builder "$TMP" <<<"a"
  [ "$status" -eq 0 ]
  [[ $output == *"build for toy-1 on work"*"change"*"run.sh"* ]]
  [ -e "$TMP/allow-protected" ]
  run human_gate build builder "$TMP" <<<$'p\na'
  [ "$status" -eq 0 ]
  [[ $output == *"a, r or b?"* ]]
  rc=0
  human_gate build builder "$TMP" <<<$'r\nrename it' || rc=$?
  [ "$rc" -eq 4 ]
  [ "$HUMAN_NOTE" = "rename it" ]
  (
    gate_opens build
    printf 'use a table\n' >"$TMP/reject.md"
  ) 3>&- &
  pause_for_pane_reply() { gate_waiting "$TMP" >"$TMP/paused" || printf closed >"$TMP/paused"; }
  rc=0
  human_gate build builder "$TMP" </dev/null || rc=$?
  wait
  [ "$rc" -eq 4 ]
  [ "$HUMAN_NOTE" = "use a table" ]
  [ "$(cat "$TMP/paused")" = closed ]
  run human_gate build builder "$TMP" <<<"b"
  [ "$status" -eq 3 ]
}

@test "prompts: agents reply with what they write; reviews name their step and round" {
  fake_task
  WT=$TMP
  TASK_DESC="" GATE=true MEMORY=""
  base_ref() { printf main; }
  [[ $(review_prompt 2) == *"review-2.md"*"two lines: CODE REVIEW round 2, then VERDICT"*"reply with its content"* ]]
  [[ $(plan_check_prompt 2) == *"review-2-plan.md"*"two lines: CODE REVIEW round 2, then VERDICT"*"reply with its content"* ]]
  [[ $(plan_review_prompt 1) == *"plan-review-1.md"*"two lines: PLAN REVIEW round 1, then VERDICT"*"reply with its content"* ]]
  [[ $(plan_build_check_prompt 1) == *"plan-review-1-build.md"*"two lines: PLAN REVIEW round 1, then VERDICT"*"reply with its content"* ]]
  [[ $(plan_prompt) == *"reply with its content"* ]]
  # the planner asks in its own dialog; the approvals are the human's, in Factory's dialog or typed
  [[ $(plan_prompt) == *"ask the human first with your AskUserQuestion tool"*"The human approves, revises or aborts the plan in a dialog Factory has you show, or by typing !fy approve (--allow-protected"*"!fy reject '<note>' or !fy abort in another pane, an apostrophe inside the quotes as '\''. Never run these yourself"* ]]
  [[ $(plan_prompt) != *"decisions.md"* ]]
  mkdir -p "$TMP/.factory/run" && printf -- '- the planner asked: Which format? Answer: CSV\n' >"$TMP/.factory/run/decisions.md"
  [[ $(plan_prompt) == *"answers and decisions on this task so far are in .factory/run/decisions.md; read them before asking again"* ]]
  protected_globs() { :; }
  BRANCH=work
  [[ $(build_prompt) == *"The human approves, revises or aborts the build in a dialog Factory has you show, or by typing !fy approve, !fy reject '<note>' or !fy abort in another pane, an apostrophe inside the quotes as '\''. Never run these yourself"* ]]
  TASK_ID=toy-1
  [[ $(gate_dialog_prompt plan) == *'header "fy plan", text "Approve the plan for toy-1, or type a note to have it revised?", options "Approve", "Approve, allow protected paths" and "Abort", in that order'*"do not act on it or run anything"* ]]
  [[ $(gate_dialog_prompt build) == *'header "fy build"'*'options "Approve" and "Abort", in that order'* ]]
  [[ $(plan_fix_prompt 1) == *"reply with the plan's content"* ]]
  [[ $(plan_note_prompt "split it") == *"Reply with the content of plan-changes.md"* ]]
  [[ $(revise_prompt 1) == *"content of response-1.md if you wrote it, else with just DONE"* ]]
  [[ $(copilot_fix_prompt 1) == *"content of copilot-1-response.md if you wrote it, else with just DONE"* ]]
  # the step and round sit above the verdict, which still ends the file
  printf 'notes\nCODE REVIEW round 2\nVERDICT: REVISE\n' >"$TMP/review.md"
  [ "$(verdict_of "$TMP/review.md")" = REVISE ]
}

@test "write_plan: the planner's turn ends with its plan, or gets one nudge, then the run stops" {
  fake_task
  WT=$TMP
  TASK_DESC="" GATE=true MEMORY=""
  mkdir -p "$TMP/.factory/run"
  ask() { # nothing the first time, the plan the second
    printf 'asked %s: %.100s\n' "$1" "$2"
    if [[ -e $TMP/asked ]]; then printf 'the plan\n' >"$WT/.factory/run/plan.md"; fi
    : >"$TMP/asked"
  }
  planner_kept_hands_off() { :; }
  tree_state() { :; } # its snapshot of the tree, which is no git repo here
  run write_plan planner
  [ "$status" -eq 0 ]
  [[ $output == *"asked planner: Task toy-1"*"wrote no .factory/run/plan.md; asking again"*"asked planner: You replied, but .factory/run/plan.md does not exist. Do not ask the human"* ]]
  rm -f "$TMP/asked" "$TMP/.factory/run/plan.md"
  ask() { :; }
  run write_plan planner
  [ "$status" -eq 1 ]
  [[ $output == *"planner never wrote .factory/run/plan.md"* ]]
}

@test "write_plan: each planner turn is checked; what the human changes while its dialog is open is theirs, what it changed before asking is not" {
  make_repo
  task_worktree
  fake_task
  WT=$TMP/wt-9
  TASK_DESC="" GATE=true MEMORY=""
  hook() {
    jq -n --arg e "$1" --arg cwd "$WT" '{cwd: $cwd, hook_event_name: $e, tool_name: "AskUserQuestion", tool_input: {questions: [{header: "Fmt", question: "Which?", options: [{label: "A"}]}]}, tool_response: {answers: {"Which?": "A"}}}'
  }
  ask() {
    case $2 in
      "You changed files"*)
        printf 'revert asked: %s\n' "$2"
        git -C "$WT" checkout -q -- run.sh
        ;;
      *)
        printf 'sneaky\n' >>"$WT/run.sh" # the planner's change, before it asks
        hook PreToolUse | cmd_dialog_hook plan toy-9 "$WT/$RUN_DIR"
        printf 'id,n\n' >"$WT/sample.csv" # the human drops a sample in while answering
        hook PostToolUse | cmd_dialog_hook plan toy-9 "$WT/$RUN_DIR"
        hook PreToolUse | cmd_dialog_hook plan toy-9 "$WT/$RUN_DIR" # a second question
        printf 'x,y\n' >"$WT/other.csv"
        hook PostToolUse | cmd_dialog_hook plan toy-9 "$WT/$RUN_DIR"
        printf 'the plan\n' >"$WT/$RUN_DIR/plan.md"
        ;;
    esac
  }
  run write_plan planner
  [ "$status" -eq 0 ]
  [[ $output == *"revert asked: You changed files"*" M run.sh"* ]]
  [[ $output != *"sample.csv"* && $output != *"other.csv"* ]]
  [ -e "$WT/sample.csv" ]
  [ -e "$WT/other.csv" ]
  [ "$(cat "$WT/run.sh")" = "echo hi" ]
}

@test "plan_phase: a rerun after the plan was written reviews it from the round it waits for, without planning again" {
  fake_task
  WT=$TMP
  TASK_DESC="" GATE=true FACTORY_FRESH=0
  PLAN_AGENT=planner BUILD_AGENT=builder REVIEW_AGENT=codex
  local run="$TMP/.factory/run"
  mkdir -p "$run"
  write_plan() {
    printf 'planned\n'
    printf 'the plan\n' >"$run/plan.md"
  }
  planner_kept_hands_off() { :; }
  tree_state() { :; } # its snapshot of the tree, which is no git repo here
  approve_plan() { printf 'to the human, at %s\n' "$(resume_point)"; }
  turn_ends() { printf 'the turn of %s ended\n' "$1"; }
  ask() { printf 'revised at %s\n' "$(resume_point)"; }
  ask_for_file() { # each review takes the next verdict from $TMP/verdicts, and sees the marker
    printf 'x' >>"$TMP/n"
    printf 'review %s at %s\n' "${3##*/}" "$(resume_point)"
    printf 'VERDICT: %s\n' "$(sed -n "$(wc -c <"$TMP/n")p" "$TMP/verdicts")" >"$3"
  }
  # a new plan is marked for round 1 before its review, for round 2 once revised
  : >"$TMP/n"
  printf '%s\n' REVISE APPROVE APPROVE APPROVE >"$TMP/verdicts"
  run plan_phase "$TMP"
  [ "$status" -eq 0 ]
  [[ $output == *"planning"*"planned"*"review plan-review-1.md at written 1"*"revised at written 1"*"review plan-review-2.md at written 2"*"to the human, at reviewed" ]]
  # a rerun at round 2: the plan and round 1's reviews stay, and nobody plans
  rm "$run/plan-review-2.md" "$run/plan-review-2-build.md"
  : >"$TMP/n"
  printf '%s\n' APPROVE APPROVE >"$TMP/verdicts"
  run plan_phase "$TMP" 2
  [ "$status" -eq 0 ]
  [[ $output == *"the plan is already written; not planning again"*"the turn of planner ended"*"plan review round 2"*"review plan-review-2.md"*"review plan-review-2-build.md"*"to the human, at reviewed" ]]
  [[ $output != *"planned"* ]]
  [[ $output != *"plan-review-1"* ]]
  [ "$(cat "$run/plan.md")" = "the plan" ]
  [ -e "$run/plan-review-1.md" ]
  # past the last round: its revision goes on unreviewed, to the human
  run plan_phase "$TMP" 3
  [ "$status" -eq 0 ]
  [[ $output == *"the plan is already written"*"the revision after round 2 goes on unreviewed"*"to the human, at reviewed" ]]
  [[ $output != *"plan review round"* ]]
  # no plan to go on with, or no round given: planned anew, and the marker goes before the
  # planner starts, so that a run stopped while it plans does not take its plan for written
  rm "$run/plan.md"
  printf 'written 2\n' >"$run/state"
  write_plan() {
    printf 'planned at %s\n' "$(resume_point)"
    printf 'the plan\n' >"$run/plan.md"
  }
  : >"$TMP/n"
  printf '%s\n' APPROVE APPROVE >"$TMP/verdicts"
  run plan_phase "$TMP" 2
  [[ $output == *"planning"*"planned at "$'\n'*"review plan-review-1.md at written 1"* ]]
  : >"$TMP/n"
  run plan_phase "$TMP" written
  [[ $output == *"planning"*"planned at "$'\n'*"review plan-review-1.md at written 1"* ]]
  # a note's round at the approval leaves the plan reviewed: a rerun comes back to the gate
  mark reviewed
  : >"$TMP/n"
  printf '%s\n' REVISE APPROVE >"$TMP/verdicts"
  run take_note plan planner "split it"
  [ "$(resume_point)" = reviewed ]
}

@test "run_task: a rerun goes on after the milestone its state names" {
  make_repo
  setup_task() { TASK_ID=toy-1; }
  open_task_workspace() {
    WT=$TMP/wt
    mkdir -p "$WT/$RUN_DIR"
  }
  start_or_adopt_agents() { :; }
  plan_phase() { printf 'plan_phase%s\n' "${2:+ round $2}"; }
  approve_plan() { printf 'approve_plan\n'; }
  build_phase() { printf 'build_phase%s\n' "${2:+ $2}"; }
  finish_task() { printf 'finish_task\n'; }
  FACTORY_FRESH=0
  mkdir -p "$TMP/wt/$RUN_DIR"
  run run_task "$REPO" toy-1
  [ "$status" -eq 0 ]
  [ "$(grep -v '^\S*\[factory' <<<"$output" | paste -sd,)" = plan_phase,build_phase,finish_task ]
  printf 'written 2\n' >"$TMP/wt/$RUN_DIR/state"
  run run_task "$REPO" toy-1
  [[ $output == *"resuming after: written 2"* ]]
  [ "$(grep -v '^\S*\[factory' <<<"$output" | paste -sd,)" = "plan_phase round 2,build_phase,finish_task" ]
  printf 'reviewed\n' >"$TMP/wt/$RUN_DIR/state"
  run run_task "$REPO" toy-1
  [ "$(grep -v '^\S*\[factory' <<<"$output" | paste -sd,)" = approve_plan,build_phase,finish_task ]
  printf 'planned\n' >"$TMP/wt/$RUN_DIR/state"
  run run_task "$REPO" toy-1
  [ "$(grep -v '^\S*\[factory' <<<"$output" | paste -sd,)" = "build_phase resume,finish_task" ]
  printf 'built 1\n' >"$TMP/wt/$RUN_DIR/state"
  run run_task "$REPO" toy-1
  [ "$(grep -v '^\S*\[factory' <<<"$output" | paste -sd,)" = finish_task ]
}

@test "plan_phase: a revised plan goes back to both reviewers, up to FACTORY_PLAN_ROUNDS" {
  fake_task
  WT=$TMP
  TASK_DESC="" GATE=true
  PLAN_AGENT=planner BUILD_AGENT=builder REVIEW_AGENT=codex
  mkdir -p "$TMP/.factory/run"
  write_plan() { :; }
  planner_kept_hands_off() { :; }
  tree_state() { :; } # its snapshot of the tree, which is no git repo here
  mark() { :; }
  approve_plan() { printf 'to the human\n'; }
  ask() { printf 'revise: %s\n' "$2"; }
  ask_for_file() { # each review takes the next verdict from $TMP/verdicts
    printf 'x' >>"$TMP/n"
    printf 'review %s %s: %s\n' "$1" "${3##*/}" "$2"
    printf 'VERDICT: %s\n' "$(sed -n "$(wc -c <"$TMP/n")p" "$TMP/verdicts")" >"$3"
  }
  : >"$TMP/n"
  printf '%s\n' REVISE APPROVE APPROVE APPROVE >"$TMP/verdicts"
  run plan_phase "$TMP"
  [ "$status" -eq 0 ]
  [[ $output == *"plan review round 1"*"plan verdicts: REVISE APPROVE"*"revise: Reviewers left notes on your plan in .factory/run/plan-review-1.md and .factory/run/plan-review-1-build.md"* ]]
  [[ $output == *"review codex plan-review-2.md: "*"Your notes from the previous review round are in .factory/run/plan-review-1.md"*"review builder plan-review-2-build.md: "*"Your notes from the previous review round are in .factory/run/plan-review-1-build.md"*"plan verdicts: APPROVE APPROVE"*"to the human" ]]
  [ "$(grep -c '^revise:' <<<"$output")" -eq 1 ]
  [[ $output != *"review codex plan-review-1.md: "*"your notes from it"*"review builder plan-review-1-build.md"* ]]
  [[ $output != *"unreviewed"* ]]
  # still objected to in the last round: that revision too, then on to the human
  : >"$TMP/n"
  printf '%s\n' REVISE APPROVE APPROVE REVISE >"$TMP/verdicts"
  run plan_phase "$TMP"
  [ "$(grep -c '^revise:' <<<"$output")" -eq 2 ]
  [[ $output == *"revise: Reviewers left notes on your plan in .factory/run/plan-review-2.md"*"the revision after round 2 goes on unreviewed"*"to the human" ]]
  [[ $output != *"round 3"* ]]
  # one round: the old single revision, and no round-2 review or note summary of the last run left over
  : >"$TMP/n"
  printf 'the last run'"'"'s note\n' >"$TMP/.factory/run/plan-changes.md"
  printf 'the last run'"'"'s plan\n' >"$TMP/.factory/run/plan.md"
  : >"$TMP/.factory/run/allow-protected"
  FACTORY_PLAN_ROUNDS=1 run plan_phase "$TMP"
  [ "$(grep -c '^revise:' <<<"$output")" -eq 1 ]
  [[ $output != *"round 2"* ]]
  [ ! -e "$TMP/.factory/run/plan-review-2.md" ]
  [ ! -e "$TMP/.factory/run/plan-changes.md" ]
  [ ! -e "$TMP/.factory/run/plan.md" ] # write_plan is stubbed here and writes none
  [ ! -e "$TMP/.factory/run/allow-protected" ]
  # and two approvals need none
  : >"$TMP/n"
  printf '%s\n' APPROVE APPROVE >"$TMP/verdicts"
  run plan_phase "$TMP"
  [[ $output != *"revise:"* ]]
  [[ $output == *"to the human" ]]
}

@test "build_phase: a note at the last round's approval still gets a round of its own" {
  fake_task
  WT=$TMP GATE=true BASE=main BRANCH=work
  REVIEW_AGENT=codex PLAN_AGENT=planner BUILD_AGENT=builder
  FACTORY_ROUNDS=1
  mkdir -p "$TMP/.factory/run"
  run_gate() { :; }
  guard_check() { :; }
  base_ref() { printf main; }
  mark() { :; }
  ask() { printf 'asked %s: %.40s\n' "$1" "$2"; }
  ask_for_file() { printf 'VERDICT: %s\n' "$(cat "$TMP/verdict")" >"$3"; }
  human_gate() { # a note the first time, an approval the second
    if [[ -e $TMP/noted ]]; then return 0; fi
    : >"$TMP/noted"
    HUMAN_NOTE="rename the flag"
    return 4
  }
  printf 'APPROVE\n' >"$TMP/verdict"
  build_phase "$TMP" >"$TMP/out" 2>&1
  [ "$VERDICT" = APPROVE ]
  [ "$ROUND" -eq 2 ]
  grep -q 'asked builder: The human reviewed the implementation' "$TMP/out"
  grep -q 'review round 2' "$TMP/out"
  # the reviewers asking for more in that extra round still end the run
  rm -f "$TMP/noted"
  human_gate() { HUMAN_NOTE="rename the flag" && printf 'REVISE\n' >"$TMP/verdict" && return 4; }
  build_phase "$TMP" >"$TMP/out" 2>&1
  [ "$VERDICT" = REVISE ]
  [ "$ROUND" -eq 2 ]
}

@test "plan approval: a note gets a plan round of its own, its reviewers told of the note" {
  make_repo
  fake_task
  WT=$REPO
  TASK_DESC="" GATE=true
  PLAN_AGENT=planner BUILD_AGENT=builder REVIEW_AGENT=codex
  local run="$REPO/.factory/run"
  mkdir -p "$run"
  printf 'VERDICT: REVISE\n' >"$run/plan-review-2.md" # the rounds before were used up
  printf 'VERDICT: APPROVE\n' >"$run/plan-review-2-build.md"
  touch "$run/plan-review-1.md" "$run/plan-review-1-build.md"
  printf 'the human'"'"'s\n' >"$REPO/fixture.csv" # added while the gate waited
  ask() { printf 'asked %s: %.80s\n' "$1" "$2"; }
  ask_for_file() { # the reviewers approve this time
    printf 'review %s %s: %s\n' "$1" "${3##*/}" "$2"
    printf 'VERDICT: APPROVE\n' >"$3"
  }
  run take_note plan planner "keep the fetcher per epoch"
  [ "$status" -eq 0 ]
  [[ $output == *"asked planner: The human reviewed"*"plan review round 3"* ]]
  [[ $output != *"asking it to revert"* ]] # the human's file is not the planner's
  [[ $output == *"review codex plan-review-3.md: "*"Your notes from the previous review round are in .factory/run/plan-review-2.md"*"The human sent this note on the plan: keep the fetcher per epoch"*"review builder plan-review-3-build.md: "* ]]
  [[ $output == *"review builder plan-review-3-build.md: "*"plan-review-2-build.md"*"keep the fetcher per epoch"* ]]
  [[ $output == *"plan verdicts: APPROVE APPROVE"* ]]
  [[ $output != *"plan revision"* ]]
  # an objection gets the planner's revision before the plan goes back to the human, added to
  # its summary; a change to the code in that turn is the planner's to revert, the human's is not
  ask_for_file() { printf 'VERDICT: REVISE\n' >"$3"; }
  ask() {
    printf 'asked %s: %s\n' "$1" "$2"
    case $2 in
      Reviewers*) printf 'sneaky\n' >>"$REPO/run.sh" ;;
      "You changed files"*) git -C "$REPO" checkout -q -- run.sh ;;
    esac
  }
  run take_note plan planner "keep the fetcher per epoch"
  [ "$status" -eq 0 ]
  [[ $output == *"plan review round 4"*"plan revision"*"asked planner: Reviewers left notes on your plan in .factory/run/plan-review-4.md"*"Add to .factory/run/plan-changes.md what you changed now and why, and where the plan no longer follows the note"*"asking it to revert"*" M run.sh"* ]]
  [[ $output != *"fixture.csv"* ]]
  [ -e "$REPO/fixture.csv" ]
  [[ $(plan_fix_prompt 4) != *"plan-changes.md"* ]] # only a note's round has a summary
}

@test "plan rounds: one cut off before the builder's notes does not count, and runs again" {
  fake_task
  WT=$TMP
  TASK_DESC="" GATE=true
  PLAN_AGENT=planner BUILD_AGENT=builder REVIEW_AGENT=codex
  local run="$TMP/.factory/run"
  mkdir -p "$run"
  printf 'the plan\n' >"$run/plan.md"
  printf 'VERDICT: APPROVE\n' >"$run/plan-review-1.md"
  printf 'VERDICT: APPROVE\n' >"$run/plan-review-1-build.md"
  touch -t 202001010000 "$run"/plan-review-1*.md      # a note changed the plan since
  printf 'VERDICT: REVISE\n' >"$run/plan-review-2.md" # Codex's, then a Ctrl-C before the builder's
  [ "$(plan_rounds "$run")" = 1 ]
  run show_for_approval plan "$run"
  [[ $output == *"plan review round 1: APPROVE APPROVE (plan changed since), notes in"* ]]
  ask_for_file() { # what a reviewer finds of the cut-off round when asked
    printf 'review %s %s: left over %s\n' "$1" "${3##*/}" "$([[ -e $3 ]] && printf yes || printf no)"
    printf 'VERDICT: APPROVE\n' >"$3"
  }
  run plan_round 2
  [ "$status" -eq 0 ]
  [[ $output == *"review codex plan-review-2.md: left over no"*"review builder plan-review-2-build.md: left over no"*"plan verdicts: APPROVE APPROVE"* ]]
}

@test "take_flags: the flags set their knobs, the rest stay in order, unknown flags fail" {
  FACTORY_PR=0
  FACTORY_APPROVAL=ask
  FACTORY_COPILOT=1
  FACTORY_FRESH=0
  take_flags --pr repo "a task" --auto --no-copilot --fresh
  [ "$FACTORY_PR" = 1 ]
  [ "$FACTORY_APPROVAL" = auto ]
  [ "$FACTORY_COPILOT" = 0 ]
  [ "$FACTORY_FRESH" = 1 ]
  [ "${#ARGS[@]}" -eq 2 ]
  [ "${ARGS[0]}" = repo ]
  [ "${ARGS[1]}" = "a task" ]
  run take_flags --nope repo
  [ "$status" -eq 1 ]
  [[ $output == *"unknown flag: --nope"* ]]
}

@test "copilot_comments_of picks the bot's comments for one commit as file:line: body" {
  run copilot_comments_of abc123 <<'JSON'
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

@test "copilot_verdict_of and copilot_summary_of skip the overview header a review opens with" {
  local overview_json='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123","body":"<!-- ccr-overview-v2 -->\n\n## Copilot review overview\n\n### 🟢 Approval recommended\n\nThe change does what the task asks.\n\n**Review effort:** Balanced  \n**Findings:** None\n\n<details>\n<summary>What changed</summary>\nmore\n</details>"}]'
  run copilot_verdict_of abc123 <<<"$overview_json"
  [ "$output" = "🟢 Approval recommended" ]
  run copilot_summary_of abc123 <<<"$overview_json"
  [ "$output" = "The change does what the task asks." ]
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

@test "bd_field: the field of a bead, whether bd show gives an array or an object" {
  bd() {
    case "$*" in
      *"show toy-1 --json") printf '[{"id":"toy-1","title":"in an array"}]\n' ;;
      *"show toy-2 --json") printf '{"id":"toy-2","title":"as an object"}\n' ;;
    esac
  }
  [ "$(bd_field repo toy-1 .title)" = "in an array" ]
  [ "$(bd_field repo toy-2 .title)" = "as an object" ]
  [ "$(bd_field repo toy-2 '.description // "none"')" = none ]
}

@test "resolve_task: a known bead id fills the task from bd show, anything else files a new bead" {
  mkdir "$TMP/.beads"
  bd() {
    case "$*" in
      *"show toy-1 --json") printf '[{"id":"toy-1","title":"Add CSV export","description":"as a file"}]\n' ;;
      *"show "*) return 1 ;;
      *"create "*" --silent") printf 'toy-2\n' ;;
    esac
  }
  run resolved "$TMP" toy-1
  [ "$output" = $'toy-1: Add CSV export\n---\nas a file' ]
  run resolved "$TMP" "Add a farewell flag"
  [ "$output" = $'toy-2: Add a farewell flag\n---' ]
  run resolve_task "$TMP" toy-404 # shaped like an id, but bd does not know it
  [[ $output == *"filed toy-2: toy-404"* ]]
  run resolve_task "$TMP/nowhere" toy-1
  [ "$status" -eq 1 ]
  [[ $output == *"no beads in"* ]]
}

@test "memory_block: nothing without memories, else the notes block for the prompts" {
  bd() {
    printf '%s\n' "$BD_MEM"
    return "$BD_RC"
  }
  BD_MEM="" BD_RC=1 run memory_block repo
  [ -z "$output" ]
  BD_MEM="No memories stored for this repo." BD_RC=0 run memory_block repo
  [ -z "$output" ]
  BD_MEM=$'style: argparse, not click\nci: just ci' BD_RC=0 run memory_block repo
  [[ $output == *"Notes from earlier work"*"bd recall"*$'style: argparse, not click\nci: just ci' ]]
}

@test "cmd_sync: pull then push; an empty remote is fine, any other pull error is not" {
  mkdir "$TMP/.beads"
  FACTORY_BD_PUSH=0 # sync pushes even when runs do not
  bd() {
    case "$*" in
      *"dolt pull")
        printf '%s\n' "$BD_PULL"
        return "$BD_PULL_RC"
        ;;
      *"config get sync.remote") printf 'git+https://x/y.git\n' ;;
      *"dolt push") printf 'pushed\n' ;;
    esac
  }
  BD_PULL=$'Fetching from origin...\nEverything up-to-date' BD_PULL_RC=0 run cmd_sync "$TMP"
  [ "$status" -eq 0 ]
  [[ $output == *"beads: Everything up-to-date"*"beads pushed to git+https://x/y.git"* ]]
  BD_PULL='error: no branches found on remote' BD_PULL_RC=1 run cmd_sync "$TMP"
  [ "$status" -eq 0 ]
  [[ $output == *"nothing to pull"*"beads pushed"* ]]
  BD_PULL=$'error: remote not reachable\nnetwork is down' BD_PULL_RC=1 run cmd_sync "$TMP"
  [ "$status" -eq 1 ]
  [[ $output == *"beads pull failed: network is down"* ]]
  [[ $output != *"beads pushed"* ]]
}

@test "clean: merged task branches go, unmerged stay unless forced" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" branch factory/toy-m
  git -C "$REPO" worktree add -q "$TMP/wt-m" factory/toy-m
  printf 'x\n' >"$TMP/wt-m/m.txt"
  git -C "$TMP/wt-m" add -A && git -C "$TMP/wt-m" commit -qm m
  git -C "$REPO" merge -q factory/toy-m
  git -C "$REPO" checkout -qb factory/toy-u
  printf 'u\n' >"$REPO/u.txt"
  commit_all u
  git -C "$REPO" checkout -q main
  herdr() { printf '{"result":{"worktrees":[]}}'; }
  bd() {
    case "$*" in
      *"config get"*) printf 'sync.remote (not set in config.yaml)\n' ;;
      *show*) printf '{"status":"closed"}\n' ;;
    esac
  }
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

@test "clean: a task still in planning stays, though its branch has no commits of its own" {
  make_repo
  git -C "$REPO" checkout -q main
  git -C "$REPO" branch factory/toy-p
  herdr() { printf '{"result":{"worktrees":[]}}'; }
  BD_STATUS=in_progress
  bd() {
    case "$*" in
      *"config get"*) printf 'sync.remote (not set in config.yaml)\n' ;;
      *show*) printf '{"status":"%s"}\n' "$BD_STATUS" ;;
      *close*) printf '%s\n' "$*" >>"$TMP/closed" ;;
    esac
  }
  run cmd_clean "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"keeping factory/toy-p: task toy-p is in_progress"* ]]
  [ "$(git -C "$REPO" branch --list 'factory/*' --format='%(refname:short)')" = "factory/toy-p" ]
  [ ! -e "$TMP/closed" ]
  BD_STATUS=closed
  run cmd_clean "$REPO"
  [[ $output == *"cleaned factory/toy-p"* ]]
  [ -z "$(git -C "$REPO" branch --list 'factory/*')" ]
}

@test "planner_kept_hands_off: clean tree passes, dirty tree gets one revert, then dies" {
  make_repo
  WT=$REPO
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
  planner_kept_hands_off planner # files under .factory/run/ are fine
  # the rest of .factory/ is not
  printf 'exit 0\n' >>"$REPO/.factory/gate"
  ask() { printf 'asked %s: %s\n' "$1" "$2"; }
  run planner_kept_hands_off planner
  [ "$status" -eq 1 ]
  [[ $output == *"Revert these changes"*" M .factory/gate"* ]]
  git -C "$REPO" checkout -q -- .
  # given the tree before its turn, only what the turn changed is the planner's
  printf 'the human'"'"'s\n' >"$REPO/fixture.csv"
  local before
  before=$(tree_state "$REPO")
  planner_kept_hands_off planner "$before"
  printf 'sneaky\n' >"$REPO/run.sh"
  ask() { printf 'asked %s: %s\n' "$1" "$2"; }
  run planner_kept_hands_off planner "$before"
  [ "$status" -eq 1 ]
  [[ $output == *"Revert these changes"*" M run.sh"* ]]
  [[ $output != *"fixture.csv"* ]]
  [ -e "$REPO/fixture.csv" ]
}

@test "ask: a prompt Herdr calls stalled that went in late gets its turn waited out, not sent again" {
  herdr() { # the reviewer starts its turn a few looks after the prompt, as Codex did live
    case "$*" in
      "agent get"*)
        printf 'x' >>"$TMP/gets"
        printf '{"result":{"agent":{"agent_status":"done","state_change_seq":%s}}}' "$(($(wc -c <"$TMP/gets") > 3 ? 5 : 4))"
        ;;
      "agent prompt"*)
        printf '%s\n' "$*" >>"$TMP/prompts"
        printf '{"error":{"code":"agent_prompt_stalled","message":"no state change within 5000ms"}}'
        return 1
        ;;
      "agent wait"*)
        printf 'wait\n' >>"$TMP/prompts"
        printf '{"result":{"agent":{"agent_status":"done"}}}'
        ;;
      *) printf '❯ \n' ;;
    esac
  }
  sleep() { :; }
  run ask t-review "review the plan"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent prompt' "$TMP/prompts")" -eq 1 ]
  [ "$(tail -n 1 "$TMP/prompts")" = wait ] # its turn waited out
  [[ $output != *"still"* ]]
  # one that never went in: no state change for 20 s, so it goes again, three times at most
  rm -f "$TMP/gets" "$TMP/prompts"
  agent_seq() { printf 4; }
  sleep() { [[ $1 != 1 ]] || printf s >>"$TMP/slept"; }
  run ask t-review "review the plan"
  [ "$status" -eq 1 ]
  [ "$(grep -c '^agent prompt' "$TMP/prompts")" -eq 3 ]
  [ "$(wc -c <"$TMP/slept")" -eq $((3 * 19)) ] # each stall watched for 20 s
  [[ $output == *"t-review: prompt stalled 3 times"* ]]
}

@test "ask: a turn under way, such as the agent's reply in its pane, ends before the prompt goes in" {
  PLAN_AGENT=planner
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent get"*) printf '{"result":{"agent":{"agent_status":"%s"}}}' "$(cat "$TMP/state")" ;;
      *) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  printf working >"$TMP/state"
  ask planner "the note"
  [ "$(cut -d' ' -f1-2 "$TMP/herdr.log" | paste -sd,)" = "agent get,agent wait,agent read,agent get,agent prompt,agent read" ]
  grep -q '^agent wait planner --until idle --until done --until blocked ' "$TMP/herdr.log"
  printf 'done' >"$TMP/state"
  : >"$TMP/herdr.log"
  ask planner "the note"
  [ "$(cut -d' ' -f1-2 "$TMP/herdr.log" | paste -sd,)" = "agent get,agent read,agent get,agent prompt,agent read" ]
  # a state it cannot read stops it before any prompt, also inside $(...), where errexit is off
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent get"*)
        printf '{"error":{"code":"not_found","message":"no such agent"}}'
        return 1
        ;;
      *) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  : >"$TMP/herdr.log"
  run ask planner "the note"
  [ "$status" -eq 1 ]
  [[ $output == *"no such agent"* ]]
  local out=""
  out=$(
    ask planner "the note" 2>/dev/null
    printf 'went on'
  ) || [ -z "$out" ]
  [[ $out != *"went on"* ]]
  [ "$(grep -c 'agent prompt' "$TMP/herdr.log")" -eq 0 ]
}

@test "ask: an open question dialog is never typed into, nor taken for the end of a turn" {
  fake_task
  PLAN_AGENT=planner
  FACTORY_POLL_SECONDS=0
  : >"$TMP/reads"
  herdr() { # a dialog on the screen for the first two looks; Herdr reads the agent as idle
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent get"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      "agent read"*)
        printf 'x' >>"$TMP/reads"
        if (($(wc -c <"$TMP/reads") <= 2)); then printf '☐ Format\nEnter to select · ↑/↓ to navigate · Esc to cancel\n'; fi
        ;;
      *) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  run ask planner "the plan, please"
  [ "$status" -eq 0 ]
  [[ $output == *"planner is waiting for your input"* ]]
  [ "$(cut -d' ' -f1-2 "$TMP/herdr.log" | paste -sd,)" = "agent get,agent read,agent read,agent read,agent wait,agent read,agent get,agent prompt,agent read" ]
  # a question asked in the turn, which Herdr takes for its end: the human is told, and ask waits
  : >"$TMP/herdr.log"
  : >"$TMP/reads"
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent get"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      "agent read"*)
        if grep -q '^agent prompt' "$TMP/herdr.log"; then
          printf 'x' >>"$TMP/reads"
          if (($(wc -c <"$TMP/reads") <= 2)); then printf '☐ Format\nEnter to select · ↑/↓ to navigate · Esc to cancel\n'; fi
        fi
        ;;
      *) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  run ask planner "the plan, please"
  [ "$status" -eq 0 ]
  [[ $output == *"planner is waiting for your input"* ]]
  [ "$(cut -d' ' -f1-2 "$TMP/herdr.log" | paste -sd,)" = "agent get,agent read,agent get,agent prompt,agent read,agent read,agent read,agent wait,agent read" ]
  # a retry after Herdr refused the prompt waits for an open question too
  : >"$TMP/herdr.log"
  : >"$TMP/reads"
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent get"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      "agent prompt"*)
        if (($(grep -c '^agent prompt' "$TMP/herdr.log") == 1)); then
          printf '{"error":{"code":"agent_blocked","message":"blocked"}}'
          return 1
        fi
        printf '{"result":{"agent":{"agent_status":"done"}}}'
        ;;
      "agent read"*)
        if grep -q '^agent prompt' "$TMP/herdr.log"; then
          printf 'x' >>"$TMP/reads"
          if (($(wc -c <"$TMP/reads") <= 2)); then printf '☐ Format\nEnter to select · ↑/↓ to navigate · Esc to cancel\n'; fi
        fi
        ;;
      *) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  run ask planner "the plan, please"
  [ "$status" -eq 0 ]
  [[ $output == *"planner is waiting for your input"* ]]
  [ "$(grep -c '^agent prompt' "$TMP/herdr.log")" -eq 2 ]
  [[ $(cut -d' ' -f1-2 "$TMP/herdr.log" | paste -sd,) == *"agent prompt"*"agent wait"*"agent prompt"* ]]
}

@test "asking: the transcript tells whether a marked question is open; without one, the screen: a dialog in the prompt box's place" {
  WT=$TMP PLAN_AGENT=t-plan
  local run="$TMP/.factory/run" tp="$TMP/transcript.jsonl"
  mkdir -p "$run"
  herdr() { cat "$TMP/screen"; }
  : >"$TMP/screen" # an editor or the transcript view: nothing of the dialog shows
  : >"$tp"
  printf 'toolu_1\t%s\n' "$tp" >"$run/asking-plan"
  asking t-plan
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","is_error":true}]}}\n' >>"$tp"
  run asking t-plan # Esc wrote the result, and ran no hook
  [ "$status" -eq 1 ]
  [ ! -e "$run/asking-plan" ]
  printf ' ☐ Fmt\nWhich?\n❯ 1. CSV\nEnter to select · ↑/↓ to\nnavigate · Esc to cancel\n────\n' >"$TMP/screen" # wrapped in a narrow pane
  asking t-plan
  printf 'Review your answers\nReady to submit your answers?\n❯ 1. Submit answers\n  2. Cancel\n' >"$TMP/screen"
  asking t-plan
  # the agent's own text quoting a footer or the review step, above its prompt box, asks
  # nothing, with a status line below the box or not, and a draft typed in it or not
  printf 'It reads Enter to select · ↑/↓ to navigate\n\n✻ Done\n────\n❯ \n────\n  Opus 5.5\n  ⏵⏵ auto mode on\n' >"$TMP/screen"
  run asking t-plan
  [ "$status" -eq 1 ]
  printf '● Then: Ready to submit your answers?\n\n✻ Worked for 5s · done 9:41 PM\n── plan ─\n❯ 2 more\n──\n  ⏵⏵ auto mode on\n' >"$TMP/screen"
  run asking t-plan
  [ "$status" -eq 1 ]
  # the reviewer, Codex, asks in no such dialog, whatever its screen quotes
  printf 'Enter to select · ↑/↓ to navigate\n' >"$TMP/screen"
  run asking t-review
  [ "$status" -eq 1 ]
  # a session that keeps no transcript: its mark holds until the agent's prompt is back
  printf 'toolu_2\t%s\n' "$TMP/none.jsonl" >"$run/asking-plan"
  : >"$TMP/screen" # the editor
  asking t-plan
  printf '❯ Ask me which format\n──\n  dialog waiting · Showing detailed transcript · ctrl+o to toggle\n' >"$TMP/screen"
  asking t-plan # the transcript view, its sticky prompt above
  [ -e "$run/asking-plan" ]
  printf '✻ Done\n────\n❯ \n────\n' >"$TMP/screen"
  run asking t-plan
  [ "$status" -eq 1 ]
  [ ! -e "$run/asking-plan" ]
}

@test "await_answer: Factory's own approval dialog, left from a gate that has ended, goes with Esc" {
  fake_task
  BUILD_AGENT="t-build"
  : >"$TMP/keys"
  herdr() {
    case "$*" in
      "agent read"*)
        printf 'x' >>"$TMP/reads"
        if [[ -s $TMP/keys ]] || (($(wc -c <"$TMP/reads") > 20)); then # gone, or a regression gives up
          printf '❯ \n'
        else
          printf ' ☐ fy build\nApprove the build for toy-1?\n❯ 1. Approve\nEnter to select · ↑/↓ to navigate · Esc to cancel\n'
        fi
        ;;
      "agent send-keys"*) printf '%s\n' "$*" >>"$TMP/keys" ;;
      *) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  run await_answer t-build
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/keys")" = "agent send-keys t-build esc" ]
  [[ $output == *"t-build: dismissed an approval dialog no gate waits for"* ]]
  [[ $output != *"waiting for your input"* ]]
}

@test "dismiss_dialog: waits for the session to record its Esc, so that the next ask finds no question open" {
  fake_task
  WT=$TMP BUILD_AGENT=t-build
  local run="$TMP/.factory/run" tp="$TMP/transcript.jsonl"
  mkdir -p "$run"
  printf '{}' >"$run/hooks-build.json"
  : >"$tp"
  printf 'toolu_1\t%s\n' "$tp" >"$run/asking-build" # the approval dialog's hook marked it
  herdr() {
    printf '%s\n' "$*" >>"$TMP/herdr.log"
    case "$*" in
      "agent wait"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
      "agent read"*) grep -q '^agent send-keys' "$TMP/herdr.log" || printf ' ☐ fy build\nApprove the build for toy-1?\nEnter to select · ↑/↓ to navigate · Esc to cancel\n' ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  sleep() { # time passes: the session writes the dismissed call's result a moment after the Esc
    printf 's' >>"$TMP/slept"
    (($(wc -c <"$TMP/slept") < 3)) || printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","is_error":true}]}}\n' >>"$tp"
  }
  run dismiss_dialog build t-build "$run"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^agent send-keys t-build esc$' "$TMP/herdr.log")" -eq 1 ]
  [[ $output == *"t-build: dismissed its approval dialog, answered elsewhere"* ]]
  [ ! -e "$run/asking-build" ]
  [ "$(cat "$TMP/slept")" = sss ]
  run await_answer t-build
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ask_for_file: asks once more when the file is missing, then gives up" {
  ask() { # the agent writes the file only when asked again
    printf 'asked %s: %s\n' "$1" "$2"
    [[ -e $TMP/asked ]] && printf 'the plan\n' >"$TMP/plan.md"
    : >"$TMP/asked"
  }
  run ask_for_file planner "write the plan" "$TMP/plan.md"
  [ "$status" -eq 0 ]
  [[ $output == *"asked planner: write the plan"*"missing; asking again"*"asked planner: You replied, but $TMP/plan.md does not exist"* ]]
  [ "$(grep -c '^asked planner' <<<"$output")" -eq 2 ]
  : >"$TMP/plan.md" # an empty file does not count either
  ask() { :; }
  run ask_for_file planner "write the plan" "$TMP/plan.md"
  [ "$status" -eq 1 ]
  [[ $output == *"planner never wrote $TMP/plan.md"* ]]
}

@test "herr_code and herr_msg read a herdr error; plain text is the message as is" {
  local err='{"error":{"code":"timeout","message":"agent wait timed out"}}'
  [ "$(herr_code "$err")" = timeout ]
  [ "$(herr_msg "$err")" = "agent wait timed out" ]
  [ -z "$(herr_code '{"error":{"message":"m"}}')" ]
  [ -z "$(herr_code 'herdr: connection refused')" ]
  [ "$(herr_msg 'herdr: connection refused')" = "herdr: connection refused" ]
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

@test "unblock: each question the agent asks is announced, and a wait on the human never times out" {
  fake_task
  : >"$TMP/waits"
  herdr() {
    case "$*" in
      "agent get"*) printf '{"result":{"agent":{"agent_status":"blocked"}}}' ;;
      "agent read"*) printf 'Which format?\nEnter to select · ↑/↓ to navigate · Esc to cancel\n' ;;
      "agent wait"*)
        printf '%s\n' "$*" >>"$TMP/waits"
        case $(wc -l <"$TMP/waits") in
          2) printf '{"result":{"agent":{"agent_status":"blocked"}}}' ;; # it asks again
          4) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
          *) printf '{"result":{"agent":{"agent_status":"working"}}}' ;;
        esac
        ;;
    esac
  }
  run unblock planner
  [ "$status" -eq 0 ]
  [ "$(grep -c 'planner is waiting for your input' <<<"$output")" -eq 2 ]
  # past the turn timeout, a question still open gets one reminder, and the wait goes on
  : >"$TMP/chunks"
  herdr() {
    case "$*" in
      "agent wait"*)
        printf 'x' >>"$TMP/chunks"
        if (($(wc -c <"$TMP/chunks") <= 3)); then
          printf '{"error":{"code":"timeout","message":"t"}}'
          return 1
        fi
        printf '{"result":{"agent":{"agent_status":"done"}}}'
        ;;
      "agent get"*) printf '{"result":{"agent":{"agent_status":"blocked"}}}' ;;
      "agent read"*) printf 'Enter to select · ↑/↓ to navigate · Esc to cancel\n' ;;
    esac
  }
  run wait_for planner 60000 idle "done"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'planner is still waiting for your input after 1 min' <<<"$output")" -eq 1 ]
  [[ ${lines[-1]} == "done" ]]
}

@test "settle_dialogs: a question to the human is left alone, even with an option that reads like a startup dialog" {
  fake_task
  : >"$TMP/keys"
  herdr() {
    case "$*" in
      "agent read"*) printf ' ☐ Risk\nGo on?\n❯ 1. Yes, I accept the risk\n  2. No\nEnter to select · ↑/↓ to navigate · Esc to cancel\n' ;;
      "agent send-keys"*) printf '%s\n' "$*" >>"$TMP/keys" ;;
      "agent get"*) printf '{"result":{"agent":{"agent_status":"blocked"}}}' ;;
      "agent wait"*) printf '{"result":{"agent":{"agent_status":"done"}}}' ;;
    esac
  }
  sleep() { :; }
  run settle_dialogs t-plan quiet
  [ "$status" -eq 0 ]
  run settle_dialogs t-plan
  [ "$status" -eq 0 ]
  [[ $output == *"t-plan is blocked on a dialog I could not clear; answer it in its pane"* ]]
  [ ! -s "$TMP/keys" ]
}

@test "settle_dialogs: Codex's folder trust dialog gets Enter, as the old one did" {
  fake_task
  : >"$TMP/keys"
  herdr() {
    case "$*" in
      "agent read"*)
        if [[ -s $TMP/keys ]]; then
          printf '› Ask Codex to do anything\n'
        else
          printf '  Folder access\n  Trust this folder? Codex can read, edit, and run files here, subject to your\n› 1. Trust and continue\n  2. Quit\n'
        fi
        ;;
      "agent send-keys"*) printf '%s\n' "$*" >>"$TMP/keys" ;;
      "agent get"*) printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    esac
  }
  sleep() { :; }
  run settle_dialogs t-review
  [ "$status" -eq 0 ]
  [[ $output == *"t-review: accepting Codex trust dialog (attempt 1)"* ]]
  [ "$(cat "$TMP/keys")" = "agent send-keys t-review enter" ]
}

@test "settle_dialogs: an unknown dialog goes to the human once and the run waits; a stuck start dies" {
  fake_task
  : >"$TMP/waits"
  : >"$TMP/keys"
  herdr() {
    case "$*" in
      "agent read"*)
        # once the human has answered, a known dialog follows
        if [[ -s $TMP/waits && ! -s $TMP/keys ]]; then
          printf '2 hooks need review\nPress enter to view hooks\n'
        else
          printf 'Something new?\n› 1. Yes\n'
        fi
        ;;
      "agent send-keys"*) printf '%s\n' "$*" >>"$TMP/keys" ;;
      "agent get"*) printf '{"result":{"agent":{"agent_status":"%s"}}}' "$(cat "$TMP/state")" ;;
      "agent wait"*)
        printf 'x' >>"$TMP/waits"
        printf '{"result":{"agent":{"agent_status":"idle"}}}'
        ;;
    esac
  }
  sleep() { :; }
  printf blocked >"$TMP/state"
  run settle_dialogs t-review
  [ "$status" -eq 0 ]
  [ "$(grep -c 'could not clear' <<<"$output")" -eq 1 ]
  [ -s "$TMP/waits" ]
  [ "$(cat "$TMP/keys")" = "agent send-keys t-review esc" ]
  : >"$TMP/waits"
  printf working >"$TMP/state"
  run settle_dialogs t-review
  [ "$status" -eq 1 ]
  [[ $output == *"t-review: still working, and nothing on its screen Factory knows to clear"* ]]
}

@test "live_agents counts the named agents alive in a workspace" {
  herdr() {
    printf '{"result":{"agents":[{"name":"t-plan","workspace_id":"w1"},{"name":"t-build","workspace_id":"w1"},{"name":"t-review","workspace_id":"w9"},{"name":null,"workspace_id":"w1"}]}}'
  }
  [ "$(live_agents w1 t-plan t-build t-review)" = 2 ]
  [ "$(live_agents w9 t-plan t-build t-review)" = 1 ]
  [ "$(live_agents w2 t-plan)" = 0 ]
}

@test "start_or_adopt_agents: fresh agents drop the marks of questions their predecessors left open; live ones keep them" {
  fake_task
  PLAN_AGENT=toy-1-plan BUILD_AGENT=toy-1-build REVIEW_AGENT=toy-1-review
  WS=w1 WT=$TMP BUILD_PANE=p0 FACTORY_HOME=$TMP/factory
  local run="$TMP/$RUN_DIR" tp="$TMP/transcript.jsonl" f
  mkdir -p "$run"
  : >"$tp" # the dead session's: the call, never its result
  printf 'toolu_1\t%s\n' "$tp" >"$run/asking-plan"
  printf 'toolu_2\t%s\n' "$tp" >"$run/asking-build"
  : >"$run/tree-at-ask"
  herdr() {
    case "$*" in
      "agent list"*) printf '{"result":{"agents":[]}}' ;;
      "pane list"*) printf '{"result":{"panes":[]}}' ;;
      "pane split"*) printf '{"result":{"pane":{"pane_id":"p1"}}}' ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  prime_shell() { :; }
  start_agent() { printf '%s\n' "$1" >>"$TMP/started"; }
  run start_or_adopt_agents "$TMP/repo"
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$TMP/started")" = toy-1-plan,toy-1-build,toy-1-review ]
  for f in asking-plan asking-build tree-at-ask; do
    [ ! -e "$run/$f" ]
  done
  # the task's live agents are adopted with their questions, which may still be open
  printf 'toolu_1\t%s\n' "$tp" >"$run/asking-plan"
  herdr() {
    case "$*" in
      "agent list"*) printf '{"result":{"agents":[{"name":"toy-1-plan","workspace_id":"w1"},{"name":"toy-1-build","workspace_id":"w1"},{"name":"toy-1-review","workspace_id":"w1"}]}}' ;;
      *) printf '{"result":{}}' ;;
    esac
  }
  settle_dialogs() { :; }
  run start_or_adopt_agents "$TMP/repo"
  [ "$status" -eq 0 ]
  [[ $output == *"reusing the live agents of toy-1"* ]]
  [ -e "$run/asking-plan" ]
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
  [[ $output == *"(see $REPO/.factory/guardrails.txt)"* ]]
}

@test "task_order: blockers first, then in progress, priority and newest; a cycle ends the walk" {
  run task_order <<'JSON'
[{"id":"t-c","title":"c","status":"open","priority":2,"created_at":"2026-10-01T00:00:03Z","dependencies":[{"depends_on_id":"t-b","type":"blocks"}]},
 {"id":"t-b","title":"b","status":"open","priority":2,"created_at":"2026-10-01T00:00:02Z","dependencies":[{"depends_on_id":"t-a","type":"blocks"},{"depends_on_id":"t-closed","type":"blocks"}]},
 {"id":"t-a","title":"a","status":"open","priority":2,"created_at":"2026-10-01T00:00:09Z"},
 {"id":"t-p","title":"p","status":"open","priority":1,"created_at":"2026-10-01T00:00:08Z"},
 {"id":"t-w","title":"w","status":"in_progress","priority":3,"created_at":"2026-10-01T00:00:07Z"},
 {"id":"t-r","title":"r","status":"open","priority":2,"created_at":"2026-10-01T00:00:01Z","dependencies":[{"depends_on_id":"t-c","type":"related"}]},
 {"id":"t-z","title":"z","status":"open","priority":3,"created_at":"2026-10-01T00:00:00Z"}]
JSON
  [ "$status" -eq 0 ]
  [ "$output" = $'◐ t-w ● P3 w\n○ t-p ● P1 p\n○ t-a ● P2 a\n○ t-b ● P2 b\n○ t-c ● P2 c\n○ t-r ● P2 r\n○ t-z ● P3 z' ]
  run task_order <<'JSON'
[{"id":"t-x","title":"x","status":"open","priority":2,"created_at":"2","dependencies":[{"depends_on_id":"t-y","type":"blocks"}]},
 {"id":"t-y","title":"y","status":"open","priority":2,"created_at":"1","dependencies":[{"depends_on_id":"t-x","type":"blocks"}]},
 {"id":"t-z","title":"z","status":"open","priority":2,"created_at":"3"}]
JSON
  [ "$output" = $'○ t-z ● P2 z\n○ t-x ● P2 x\n○ t-y ● P2 y' ]
  run task_order 1 <<<'[{"id":"t-1","title":"one","status":"in_progress","priority":0,"created_at":"1"}]'
  [ "$output" = $'\e[38;2;255;180;84m◐\e[m t-1 \e[1;38;2;240;113;120m● P0\e[m one' ]
}

@test "task_order: a parent's and conditional blockers count; tasks next skips come last" {
  run task_order <<'JSON'
[{"id":"t-e","title":"e","status":"open","priority":3,"created_at":"1","dependencies":[{"depends_on_id":"t-q","type":"blocks"}]},
 {"id":"t-q","title":"q","status":"open","priority":3,"created_at":"2"},
 {"id":"t-k","title":"k","status":"open","priority":0,"created_at":"3","dependencies":[{"depends_on_id":"t-e","type":"parent-child"}]},
 {"id":"t-g","title":"g","status":"open","priority":0,"created_at":"4","dependencies":[{"depends_on_id":"t-q","type":"conditional-blocks"}]},
 {"id":"t-d","title":"d","status":"deferred","priority":0,"created_at":"5"},
 {"id":"t-h","title":"h","status":"hooked","priority":0,"created_at":"6"}]
JSON
  [ "$output" = $'○ t-q ● P3 q\n○ t-g ● P0 g\n○ t-k ● P0 k\n○ t-e ● P3 e\n◇ t-h ● P0 h\n❄ t-d ● P0 d' ]
}

@test "cmd_tasks: the open tasks in order without arguments, bd list as it is with them" {
  mkdir -p "$TMP/.beads"
  bd() {
    printf '%s\n' "$*" >>"$TMP/bd.log"
    printf '[{"id":"t-2","title":"two","status":"open","priority":2,"created_at":"2","dependencies":[{"depends_on_id":"t-1","type":"blocks"}]},{"id":"t-1","title":"one","status":"open","priority":2,"created_at":"1"}]'
  }
  run cmd_tasks "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" = $'○ t-1 ● P2 one\n○ t-2 ● P2 two' ]
  run cmd_tasks "$TMP" --all
  [ "$(cat "$TMP/bd.log")" = "-C $TMP list --json -n 0"$'\n'"-C $TMP list --all" ]
  bd() { printf '[]'; }
  run cmd_tasks "$TMP"
  [ "$status" -eq 0 ]
  [[ $output == *"no open tasks in $TMP"* ]]
}

@test "next claims atomically through bd ready --claim" {
  bd() {
    printf '%s\n' "$*" >>"$TMP/bd.log"
    printf '[]'
  }
  run cmd_next "$TMP"
  [ "$status" -eq 3 ]
  grep -q 'ready --claim --json' "$TMP/bd.log"
}

@test "cmd_queue: runs tasks until none is ready, warns about a failed one, stops at max" {
  cmd_next() { # one scripted status per call, from stdin
    local rc
    read -r rc || rc=3
    printf 'next %s\n' "$1"
    return "$rc"
  }
  run cmd_queue repo <<<$'0\n2\n3\n0'
  [ "$status" -eq 0 ]
  [ "$(grep -c '^next repo' <<<"$output")" -eq 3 ]
  [[ $output == *"task stopped with status 2; continuing"*"queue finished after 2 task(s)"* ]]
  run cmd_queue repo 2 <<<$'0\n0\n0'
  [ "$(grep -c '^next repo' <<<"$output")" -eq 2 ]
  [[ $output == *"queue finished after 2 task(s)"* ]]
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
  add_origin
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
  add_origin
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

@test "repo_prefix: the initials of several words, else a word's first and last character" {
  [ "$(repo_prefix AllesBuien)" = ab ]
  [ "$(repo_prefix Blik)" = bk ]
  [ "$(repo_prefix factory)" = fy ]
  [ "$(repo_prefix game2048)" = g8 ]
  [ "$(repo_prefix phoenix_livesvelte_demo)" = pld ]
  [ "$(repo_prefix HTTPServer)" = hs ]
  [ "$(repo_prefix my.repo)" = mr ]
  [ "$(repo_prefix go)" = go ]
  [ "$(repo_prefix x)" = x ]
  [ "$(repo_prefix 2048-game)" = ge ]
  [ -z "$(repo_prefix 2048)" ] # no letter: bd picks
}

@test "init: a short prefix from the repo's name, and a --prefix of the human's wins" {
  git init -q "$TMP/AllesBuien"
  git init -q "$TMP/2048"
  bd() { printf '%s\n' "$*" >>"$TMP/bd.log"; }
  cd "$TMP/AllesBuien"
  run cmd_init . --prefix zz
  [ "$status" -eq 0 ]
  run cmd_init "$TMP/2048"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/bd.log")" = "init --non-interactive --skip-agents --skip-hooks --prefix ab --prefix zz"$'\n'"init --non-interactive --skip-agents --skip-hooks" ]
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

@test "task_context: branch from the slugged title unless the task has one, base from the checkout" {
  make_repo
  fake_task
  TASK_TITLE='Add CSV export!'
  run context_of "$REPO"
  [ "${lines[0]}" = "bash .factory/gate" ]
  [ "${lines[1]}" = work ]
  [ "${lines[2]}" = factory/toy-1-add-csv-export ]
  [ "${lines[3]}" = "toy-1-plan toy-1-build toy-1-review" ]
  # a rerun after the title changed stays on the branch it started on
  git -C "$REPO" branch factory/toy-1-old-slug
  run context_of "$REPO"
  [ "${lines[2]}" = factory/toy-1-old-slug ]
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
  [[ $output == *"interrupted during building"*"continue with: factory run [flags] $TMP toy-1"* ]]
  grep -q "comment toy-1 Factory: interrupted during building" "$TMP/bd.log"
}

@test "resume markers: written <round>, reviewed, planned, built <round>, cleared by --fresh" {
  WT=$TMP
  mkdir -p "$TMP/.factory/run"
  FACTORY_FRESH=0
  [ -z "$(resume_point)" ]
  mark written 2
  [ "$(resume_point)" = "written 2" ]
  mark reviewed
  [ "$(resume_point)" = reviewed ]
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

@test "die inside a command substitution stops the main shell, not just the subshell" {
  run bash -c 'source "$1"; FACTORY_PID=$$; trap "exit 7" USR1; x=$(die boom) || true; echo continued' _ "$BATS_TEST_DIRNAME/../factory"
  [ "$status" -eq 7 ]
  [[ $output == *"error:"*"boom"* ]]
  [[ $output != *continued* ]]
}

@test "copilot_loop: a round answered without a commit is replied to and ends the loop" {
  make_repo
  on_work_branch
  mkdir -p "$REPO/.factory/run"
  FACTORY_COPILOT_ROUNDS=3
  copilot_request() { :; }
  copilot_wait() { :; }
  copilot_verdict() { printf 'Changes recommended'; }
  copilot_comments() { printf 'run.sh:1: use set -e\n'; }
  ask() { :; }
  copilot_reply() { printf 'replied round %s on %s\n' "$2" "$3"; }
  copilot_resolve() { printf 'resolved %s\n' "$2"; }
  run copilot_loop builder https://example.invalid/pull/7
  [ "$status" -eq 1 ]
  sha=$(git -C "$REPO" rev-parse HEAD)
  [[ $output == *"replied round 1 on $sha"*"resolved $sha"*"answered without changes"* ]]
  [[ $output != *"round 2"* ]]
}

@test "help and unknown command" {
  run main help
  [ "$status" -eq 0 ]
  [[ $output == *"factory run"* ]]
  [[ $output == *"factory reject  <repo> <bead-id> '<note>'"* ]]
  [[ $output != *"factory answer"* && $output != *"dialog-answer"* ]]
  [[ $output == *"FACTORY_PLAN_EFFORT=max"*"FACTORY_BUILD_EFFORT=xhigh"*"FACTORY_REVIEW_EFFORT=xhigh"* ]]
  cd "$TMP" # no task's worktree, so the usage
  run main reject
  [[ $output == *"usage: factory reject [<repo> <bead-id>] '<note>'"* ]]
  run main answer
  [[ $output == *"unknown command"* ]]
  run main bogus
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command"* ]]
}
