# Extras

Things that are useful next to Factory but not part of it.

- `claude-marketplace/`: a tiny Claude Code plugin marketplace. Currently `metals-lsp`,
  a Scala language server plugin the official marketplace lacks.
- `cargo-sccache/`: a compiler wrapper for Cargo that, through sccache, lets a task's
  fresh worktree reuse much of what an earlier build compiled for the dependencies. Its
  README has the setup.
- `factory-user/`: a recipe for running Factory, Herdr and the agents as a user of their
  own, which holds only its clones, a GitHub token for them and the agents' logins, for
  `--auto` runs that nobody watches.
