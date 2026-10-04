# cargo-sccache

One file, `sccache`: a wrapper to name as Cargo's compiler wrapper, so that a task's fresh
worktree need not compile again much of what an earlier build compiled for the
dependencies. It needs [sccache](https://github.com/mozilla/sccache) on the PATH of every
shell that builds, the agents' included; without it the wrapper runs the compiler alone.

```toml
# ~/.cargo/config.toml for every build, or a .cargo/config.toml in Herdr's worktree
# directory for the task worktrees alone
[build]
rustc-wrapper = "/path/to/factory/extras/cargo-sccache/sccache"
```

Leave `RUSTC_WRAPPER` unset in the environment: it overrides the config, and set to nothing
it turns the wrapper off.

## What is shared

Between worktrees, only what no task can edit: the dependencies.

- What Cargo compiles inside its own directory, the registry crates and git dependencies,
  goes to a second sccache server with direct mode off (`SCCACHE_DIRECT=false`). An object
  is then keyed by its preprocessed text and its flags, not by the paths and line numbers
  of one checkout, so a new worktree finds much of the C and C++ that a dependency's build
  script compiled. An object whose preprocessed text names a path in the worktree, as
  `__FILE__` does in a file generated under `target/`, is compiled again. Registry crates
  themselves are found too, except those that read their build script's output directory
  and the crates that depend on them.
- The workspace's own code keeps sccache's defaults, which key by path. Its C and C++ are
  found again within a worktree and compiled once in each new one. Its Rust crates are not
  cached in the dev profile, where Cargo builds them incrementally.

A dependency's object keeps the paths of the worktree that first compiled it, in its debug
information and in the warnings sccache replays. The second server listens one port above
the first (4227 by default, or on the first one's socket name with `-deps`) and keeps its
cache beside the first one's, under the same name with `-deps` (`~/.cache/sccache-deps` by
default). While it runs, `SCCACHE_SERVER_PORT=4227 sccache --show-stats` shows what the
dependencies got from it.

## Where it steps aside

In Codex's sandbox sccache cannot reach its server, and it fails the compile instead of
running it. The wrapper runs the compiler alone there. It knows the sandbox by
`CODEX_SANDBOX_NETWORK_DISABLED`, which Codex sets and calls experimental. Anywhere else
that sccache cannot work, set `RUSTC_WRAPPER` to nothing.

## Two things to know

- The file's name matters. Build scripts that compile with the `cc` crate put a wrapper
  called sccache in front of the C and C++ compilers too.
- `cargo llvm-cov` puts its own wrapper first, so the C and C++ of a coverage build are not
  cached.

## What not to do instead

Three shorter ways to share more are unsafe.

- One `target/` for all worktrees (`CARGO_TARGET_DIR`, `build.target-dir`). Cargo judges
  freshness by modification time and does not tell checkouts apart: a checkout broken on
  purpose passed its tests on another checkout's binaries.
- Direct mode off for the workspace's code as well. An edit that only moves lines then gets
  the old object back, and an object compiled while a header was being edited can reach
  another worktree.
- `SCCACHE_BASEDIRS` in sccache's default mode. sccache 0.18.0 handed one checkout an
  object compiled against another checkout's header.
