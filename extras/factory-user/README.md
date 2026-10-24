# Factory as a user of its own

`--auto` skips your approvals, and the agents run as whoever runs Factory: with your keys,
your signing agent, your cloud and registry credentials, and every repo in your home. Run
Factory, Herdr and the agents as a user of their own, and a run reaches only what that
user holds: its clones, a GitHub token for those repos, and the agents' logins. This
recipe sets that up on Linux, for a user named `factory`. A VM or a container keeps out
more, at the price of an image with your toolchains in it.

## What stays out of reach, and what does not

Out of reach: your home and all in it (keys, 1Password, browser profiles, other repos,
shell history), your git identity and signing, and credentials for anything else.

Within reach:
- What the token allows: on the repos it names, pushing any branch, `main` too where no
  rule protects it, and opening and commenting on pull requests. Name only the repos
  Factory works on, and let the token expire.
- The Claude and OpenAI accounts the user logs in with, which a run spends.
- The network, and whatever listens on localhost without a password.
- Files the system leaves readable to all, `/tmp`, and the CPU and disk a gate can use.

## The user (once, as you)

```sh
sudo useradd --create-home --shell /bin/bash factory
sudo chmod 700 /home/factory
chmod 700 ~   # your own home closed to other users, if it is not already
```

Put it in no group that reaches root or other users' files, such as `wheel` or `docker`.
It shares the system's packages: git, jq, mise and Herdr where your package manager
installed them, and the libraries your builds link against.

## Its tools and logins (once, as `factory`)

`sudo -iu factory` opens its login shell. Its own tools go first on its PATH, in its login
shells, where Claude Code runs its commands, and in the shells of Herdr's panes:

```sh
line='export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"'
printf '%s\n' "$line" >>~/.bash_profile
printf '%s\n' "$line" >>~/.bashrc
exec bash -l
mise use -g claude codex gh 'ubi:gastownhall/beads[exe=bd]@1.2.2'
git clone https://github.com/robi42/factory.git ~/factory   # pull there to update
(cd ~/factory && mise trust && mise install)
mkdir -p ~/.local/bin
ln -s ~/factory/factory ~/.local/bin/factory
ln -s ~/factory/factory ~/.local/bin/fy
```

Then its logins; Claude Code's and Codex's print a link to open in your browser:

```sh
claude                                # log in, then /exit
codex login
gh auth login --with-token <token.txt # the token below; remove the file afterwards
git config --global credential.https://github.com.helper \
  '!/home/factory/.local/share/mise/shims/gh auth git-credential'
git config --global user.name 'Your Name'
git config --global user.email 'you@example.com'
```

Not `gh auth setup-git`: it names the binary of the gh version it runs from, which a mise
upgrade removes, and pushes then ask for a password.

The token is a fine-grained personal access token (GitHub: Settings, Developer settings,
Fine-grained tokens) for the repos Factory works on and no others, with Contents and Pull
requests read and write; Workflows too if a task may change `.github/workflows/`. Copilot
reviews need Copilot on the account; `FACTORY_COPILOT=0` turns them off.

Its commits go unsigned, as it holds no signing key; a squash merge on GitHub is signed by
GitHub. Its Claude Code and Codex start from their defaults, with none of your settings,
skills, hooks or MCP servers: copy over what a run should have, and no credential it
should not.

## The repos (once each, as `factory`)

```sh
git clone https://github.com/you/app.git ~/src/app
cd ~/src/app
mise trust && mise install   # the repo's own tools, if it has a mise.toml
bd bootstrap --yes           # its tasks, from origin
```

Copy over your `.factory/env` if the repo has one. A toolchain that installs per user,
such as rustup's, the user installs for itself.

`bd bootstrap` takes the tasks from origin's `refs/dolt/data`, where a clone with a sync
remote pushes them, Factory after each task. If origin has none yet, put them there from
your clone first: `bd dolt remote add origin git+https://github.com/you/app.git`, then
`bd dolt push`. Both clones then hold the tasks: file and change them in one of them, the
user's say (`sudo -iu factory fy add ~/src/app "..."`), or `bd dolt pull` before you
change them in the other.

## Running

```sh
sudo -iu factory
herdr                                 # its own Herdr server, apart from yours
fy doctor                             # then, in a pane of that Herdr
fy queue --auto --pr ~/src/app
```

Detach with `ctrl+b q`: its server, the agents and the queue go on, and
`sudo -iu factory herdr` attaches again. `--auto` skips your approvals, but a question of
the planner's still waits for your answer in its pane.

Factory's toasts go to the terminal you attach from, which shows them as desktop
notifications if it can, with this in the user's `~/.config/herdr/config.toml`:

```toml
[ui.toast]
delivery = "terminal"
```

With no client attached, none reach you: look in now and then, or keep one attached. With
sshd running and your key in the user's `~/.ssh/authorized_keys`,
`herdr --remote ssh://factory@localhost` attaches your own Herdr client over SSH instead.

## Undo

```sh
sudo userdel --remove factory
```

Then delete the token on GitHub. The user's Claude and Codex logins go with its home.
