#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# The compiler wrapper in extras/cargo-sccache. The sccache on the PATH is a stub that notes
# how it was called and then runs the compiler, and the compiler prints its arguments.

setup() {
  WRAPPER="$BATS_TEST_DIRNAME/../extras/cargo-sccache/sccache"
  TMP=$(mktemp -d)
  REGISTRY="$TMP/cargo/registry/src/index/dep-1.0.0"
  mkdir -p "$TMP/bin" "$TMP/behind" "$TMP/bare" "$TMP/self" "$TMP/work" "$REGISTRY" "$TMP/cargo/git/checkouts/dep-abc/1234567"
  cat >"$TMP/bin/sccache" <<'EOF'
#!/bin/sh
printf '%s\n' "sccache direct=${SCCACHE_DIRECT-} port=${SCCACHE_SERVER_PORT-} socket=${SCCACHE_SERVER_UDS-} cache=${SCCACHE_DIR-}: $*" >>"$LOG"
case $1 in -*) exit 0 ;; esac
exec "$@"
EOF
  cat >"$TMP/cc" <<'EOF'
#!/bin/sh
printf '%s\n' compiled "$@"
exit "${CC_STATUS:-0}"
EOF
  cat >"$TMP/behind/sccache" <<'EOF'
#!/bin/sh
echo behind >>"$LOG"
EOF
  chmod +x "$TMP/bin/sccache" "$TMP/behind/sccache" "$TMP/cc"
  ln -s "$(command -v bash)" "$TMP/bare/bash" # a PATH with bash, for the wrapper itself, and nothing else
  ln -s "$WRAPPER" "$TMP/self/sccache"        # the wrapper as the sccache on the PATH
  export LOG="$TMP/log" CARGO_HOME="$TMP/cargo" HOME="$TMP/home"
  unset CODEX_SANDBOX_NETWORK_DISABLED SCCACHE_DIRECT SCCACHE_DIR SCCACHE_SERVER_PORT SCCACHE_SERVER_UDS XDG_CACHE_HOME CC_STATUS
  PLAIN="sccache direct= port= socket= cache=:" # what the stub notes when the wrapper sets nothing
  cd "$TMP/work" || return 1
}

teardown() {
  rm -rf "$TMP"
}

@test "cargo-sccache: hands the compiler and its arguments to sccache" {
  PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" --cfg 'feature="a b"'
  [ "$status" -eq 0 ]
  [ "$output" = "compiled"$'\n'"--cfg"$'\n''feature="a b"' ]
  [ "$(cat "$LOG")" = "$PLAIN $TMP/cc --cfg feature=\"a b\"" ]
}

@test "cargo-sccache: the compiler's status and its input pass through" {
  CC_STATUS=3 PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [ "$status" -eq 3 ]
  PATH="$TMP/bin:$PATH" run "$WRAPPER" cat <<<"piped source"
  [ "$output" = "piped source" ]
}

@test "cargo-sccache: runs the compiler alone in Codex's sandbox" {
  export CODEX_SANDBOX_NETWORK_DISABLED=1
  PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" --cfg 'feature="a b"'
  [ "$output" = "compiled"$'\n'"--cfg"$'\n''feature="a b"' ]
  [ ! -e "$LOG" ]
  CC_STATUS=3 PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [ "$status" -eq 3 ]
  PATH="$TMP/bin:$PATH" run "$WRAPPER" cat <<<"piped source"
  [ "$output" = "piped source" ]
}

@test "cargo-sccache: runs the compiler alone when sccache is not installed" {
  run env PATH="$TMP/bare" "$WRAPPER" "$TMP/cc" -c x.c
  [ "$output" = "compiled"$'\n'"-c"$'\n'"x.c" ]
}

@test "cargo-sccache: as the first sccache on the PATH it uses the next one" {
  PATH="$TMP/self:$TMP/bin:$TMP/behind:$PATH" run timeout 10 "$WRAPPER" "$TMP/cc" -c x.c
  [ "$output" = "compiled"$'\n'"-c"$'\n'"x.c" ]
  [ "$(cat "$LOG")" = "$PLAIN $TMP/cc -c x.c" ]
}

@test "cargo-sccache: as the only sccache on the PATH it runs the compiler alone" {
  run timeout 10 env PATH="$TMP/self:$TMP/bare" "$WRAPPER" "$TMP/cc" -c x.c
  [ "$output" = "compiled"$'\n'"-c"$'\n'"x.c" ]
  run timeout 10 env PATH="$TMP/self:$TMP/bare" "$WRAPPER"
  [ "$status" -eq 2 ]
}

@test "cargo-sccache: a dependency in Cargo's registry goes to a second server, direct mode off" {
  cd "$REGISTRY"
  PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [ "$output" = "compiled"$'\n'"-c"$'\n'"x.c" ]
  [ "$(cat "$LOG")" = "sccache direct=false port=4227 socket= cache=$TMP/home/.cache/sccache-deps: $TMP/cc -c x.c" ]
}

@test "cargo-sccache: the second server sits beside the one the environment names" {
  cd "$REGISTRY"
  SCCACHE_SERVER_PORT=5000 SCCACHE_DIR=/x/cache XDG_CACHE_HOME=/unused PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [ "$(cat "$LOG")" = "sccache direct=false port=5001 socket= cache=/x/cache-deps: $TMP/cc -c x.c" ]
  SCCACHE_SERVER_UDS=/run/s.sock XDG_CACHE_HOME=/x PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [ "$(tail -n 1 "$LOG")" = "sccache direct=false port= socket=/run/s.sock-deps cache=/x/sccache-deps: $TMP/cc -c x.c" ]
}

@test "cargo-sccache: a git dependency too, and Cargo's home through a symlink" {
  ln -s "$TMP/cargo" "$TMP/cargo-link"
  cd "$TMP/cargo/git/checkouts/dep-abc/1234567"
  CARGO_HOME="$TMP/cargo-link" PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [[ $(cat "$LOG") == "sccache direct=false port=4227 "* ]]
}

@test "cargo-sccache: the workspace's own code keeps sccache's defaults" {
  mkdir -p "$TMP/work/registry/src/index/dep-1.0.0" # the same names, outside Cargo's home
  cd "$TMP/work/registry/src/index/dep-1.0.0"
  PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c x.c
  [ "$(cat "$LOG")" = "$PLAIN $TMP/cc -c x.c" ]
  cd "$TMP/cargo" # Cargo's home itself is not a dependency's source
  PATH="$TMP/bin:$PATH" run "$WRAPPER" "$TMP/cc" -c y.c
  [ "$(tail -n 1 "$LOG")" = "$PLAIN $TMP/cc -c y.c" ]
}

@test "cargo-sccache: sccache's own commands go to sccache" {
  PATH="$TMP/bin:$PATH" run "$WRAPPER" --show-stats
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "$PLAIN --show-stats" ]
}
