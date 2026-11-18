# Moving a repo's tasks to bd 1.3

Only for a repo with tasks from bd 1.2, which Factory installed up to 0.2. bd 1.3's first
command that reads the tasks, such as `bd list`, migrates their database for good, keeping
every task; bd 1.2 then cannot read it, there or in a clone that pulls it. bd is upgraded
per machine, so move a machine's repos together.

Where the tasks sync to a remote, one clone migrates them, and none writes meanwhile:

1. Until the last clone has moved, write nothing anywhere: no `fy run`, `add`, `next` or
   `clean`, no `bd create`, `update` or `close`. Keep a copy:
   `bd export --all -o ~/app-tasks.jsonl`.
2. Still on bd 1.2, `bd dolt pull`, then `bd dolt push`, in each clone in turn; then
   `bd dolt pull` once more in each.
3. On one machine, `git pull && mise install` in Factory's checkout, and upgrade bd with the
   `mise use -g` line under [Install](../README.md#install). In the repo, `bd list`
   migrates, `bd recompute-blocked` fixes blocked flags the migration may set wrongly, and
   `bd dolt push` shares the result.
4. In each other clone, `bd dolt pull` on bd 1.2, then upgrade bd and `bd recompute-blocked`.
   The user of [extras/factory-user](../extras/factory-user/) is one more clone, with a bd
   of its own: upgrade it with `sudo -iu factory` and the same line.
5. Add `*.gate.lock*` to the repo's `.gitignore`, for the lock file bd 1.3 keeps there.

Where the tasks never reached the remote, as with `FACTORY_BD_PUSH=0`, bd 1.3 will not
migrate them on its own and blocks writes: instead of steps 2 to 4, run `bd migrate --force`
and `bd recompute-blocked` in the repo, and push nothing.

Run no `bd compact` or `bd flatten` in the clones of step 4, or any cloned later, till a
coming bd release restores their tasks' change history
([beads#7039](https://github.com/gastownhall/beads/issues/7039)).

If a clone gets stuck anyway:

- bd 1.3 says "refusing to auto-apply … pending schema migrations": the clone was upgraded
  before its pull. Pull once with bd 1.2:
  `mise exec github:gastownhall/beads@1.2.2 -- bd dolt pull`.
- That pull fails with "merge conflicts in events": the clone wrote during the move. Export
  its tasks with bd 1.2 (`mise exec … -- bd export --all -o ~/stuck.jsonl`); in a fresh
  clone on bd 1.3, `bd bootstrap --yes`, `bd import ~/stuck.jsonl` and `bd dolt push`.
- The migrated clone's push is refused and its pull says "local changes would be stomped by
  merge: events": another clone pushed meanwhile. Upgrade bd there and `bd dolt push`; then
  `bd dolt pull` and `bd dolt push` in the first.
