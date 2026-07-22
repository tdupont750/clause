# Clause

Meet Claude’s safety-conscious friend, Clause!

Clause mounts your working directory into a tiny container with its own copy of [Claude Code](https://claude.ai/code). Inside that container, Claude can do whatever it wants however it wants, while your host machine and all of its secrets stay safe. Clause supports persistent settings and credentials in named profiles that can use custom container images.

![Clause](images/clause_small.png)

## Why use Clause?

1. You should be running your agents inside a container. Stop raw-dogging the internet. You're going to catch something.

2. Clause is just a single Bash script. No frameworks, packages, runtimes, installs, or opinionated code. Change anything you like.

## Requirements

- [Podman](https://podman.io/) or [Docker](https://www.docker.com/)

`clause` auto-detects whichever is on your `PATH`, preferring Podman. To override:

```bash
clause runtime docker
```

## Getting Started

```bash
# 1. Make the script executable:
chmod +x clause

# 2. Add the shell alias so you can run `clause` from any directory:
./clause alias create

# 3. Reload your shell (or open a new terminal):
source ~/.bashrc

# 4. Build the container image:
clause image build

# 5. Start Claude in your project:
cd ~/your-project
clause
```

That's it. Claude Code runs inside the container with your project mounted under `/workspace/`.

## Usage

```
usage: clause [session options]               launch Claude (default)
       clause <command> ...                    manage clause, then exit

With no command, clause launches the profile bound to this workspace (default:
'default'). Point a workspace at a profile with `clause bind [profile]`.

session options (shape the launch; combine with any command):
  -t, --terminal          Launch bash instead of claude
  -w, --workspace <path>  Workspace directory (default: $PWD)
  -a, --args <value>      One-shot claude args (overrides args files)
  -e, --effort <level>    One-shot effort override: low|medium|high|xhigh|max
  -y, --yes               Auto-answer yes to prompts (destructive
                          confirmations still require typing 'yes')
  -n, --no                Auto-answer no to all prompts

commands (then exit):
  config <key> [value]              Set a profile config key (args, effort)
  config --local <key> [value]      Set a workspace override (args, effort, mount)
  config --get <key>                Print one effective value (raw)
  config --reset <key>              Reset a profile key to its template default
  config --local --reset <key>      Remove a workspace override
  config --list                     Show workspace + profile config
  bind [profile]                    Bind this workspace to a profile (-p)
  bind --unset                      Remove this workspace's binding
  profile create [name]             Create a profile (seeded from default/)
  profile delete [name]             Delete a profile, its image and volume
  profile list                      List profiles
  image build                       Build the bound profile's image (-b)
  image suggest                     Print suggested Containerfile edits
  podman enable                     Enable nested podman for the profile
  podman disable                    Disable nested podman
  podman reset                      Reset the nested storage volume
  status                            Effective config for this directory

global (machine-wide setup):
  runtime <podman|docker>           Pin the container runtime
  runtime --unset                   Clear the runtime override
  alias create                      Install the clause shell alias
  alias delete                      Remove the shell alias

  -h, --help                        Print this help
```

`clause` runs one command per invocation: with no command it launches the profile bound to the current workspace (`default` until you bind one), and naming two commands is a parse-time error. Session options go before the command. Two commands have flag-spelled shortcuts: `-b` runs `image build`, and `-p [profile]` is an alias for `bind [profile]` (including `-p --unset`). A profile name is only ever typed to `bind <profile>` and `profile create <name>` / `profile delete <name>`; every other command (launch, `image`, and `podman` included) acts on the workspace's bound profile, so profiles named like command words never collide with them.

A launch mounts the workspace at an encoded subpath (`/home/tom/projects/myapp` becomes `/workspace/-home-tom-projects-myapp`) and sets the container cwd there, keeping Claude's per-project state separate when workspaces share a profile. The subpath can be pinned so it survives moving the host folder (see [Mount override](#mount-override)).

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `~/.clause/profiles/` with its own `.claude/`, `.claude.json`, `Containerfile`, `args`, and `effort`, all seeded from the repo's `default/` template; the `default` profile is created automatically on first run. A profile later missing one of those files errors at launch (re-seed with `clause image build`) rather than being silently regenerated.

Profile names are lowercased and validated wherever one is typed (`bind`, `profile create`, `profile delete`) and again when read back from a workspace's binding file: lowercase letters, digits, `.`, `_`, and `-`, starting with a letter or digit. Anything else is rejected up front, because the name becomes a directory under `~/.clause/profiles/` and the `clause-<name>` image and volume tags.

The seeded `settings.json` ships four defaults:

- Hooks that tint the terminal background while Claude works, via the `set-bg.sh` script seeded into the profile's `.claude/hooks/`.
- Two official plugins enabled through `enabledPlugins` (`skill-creator` and `claude-md-management`); they auto-install on the profile's first session, so that session needs network access.
- `effortLevel: "xhigh"`, which only affects a bare `claude` run in a `-t` terminal, since normal launches pass `--effort` explicitly (see [Effort override](#effort-override)).
- `disableRemoteControl: true`, keeping sessions local-only.

Seeding never overwrites an existing file, so profiles created before a default was added keep their old `settings.json`; add the new keys there by hand (or use `/plugin` for the plugins) if you want them.

```bash
# Create a profile (also binds this workspace to it; prompts first if the
# workspace is already bound to a different profile)
clause profile create work

# Launch it (profile create already bound this workspace to 'work')
clause

# Bind another workspace to an existing profile
clause bind work

# List all profiles
clause profile list

# Delete a profile (also removes its image and nested storage volume)
clause profile delete work
```

### Per-profile Container Images

Every profile has its own `Containerfile` and builds to its own image `clause-<profile>`; there is no shared fallback image.

```bash
# In a workspace bound to 'work', edit ~/.clause/profiles/work/Containerfile, then build
clause image build
```

`image build` (shortcut: `clause -b`) acts on the workspace's bound profile: it seeds any missing profile files (including the `Containerfile`) from the repo's `default/`, then builds the image from the profile's `Containerfile`. Rerun it after any `Containerfile` change.

### Nested Podman

Opt-in, per profile: run podman *inside* the session (build images, run service containers, use `podman compose`) without giving the session any access to the host container engine. Inner containers run rootless inside the session's user namespace, so even a full escape from an inner container only lands in the jailed session user.

```bash
# Enable: writes the bound profile's nested marker and offers to append the
# managed nested-podman block to its Containerfile; then rebuild
clause podman enable
clause image build

# Inside the session, podman just works
podman run --rm docker.io/library/hello-world

# Disable again (offers to strip the Containerfile block)
clause podman disable
```

Nested images also bundle [lazydocker](https://github.com/jesseduffield/lazydocker), wired to podman: the `lazydocker` shell function (alias `ld`) starts podman's docker-compatible API socket on demand and points `DOCKER_HOST` at it, and a baked-in config maps compose actions to `podman-compose`.

When nested podman is enabled, `clause` launches the session with:

- `--device /dev/fuse` and `--device /dev/net/tun` (each skipped with a warning if the host lacks it)
- `--security-opt label=disable` (SELinux labeling breaks nested mounts; a no-op on non-SELinux hosts)
- a named volume `clause-<profile>-containers` mounted at `/home/claude/.local/share/containers`, so inner images persist across the ephemeral sessions
- under a Docker host runtime, additionally `seccomp=unconfined` and `apparmor=unconfined`, because Docker's default profiles block the syscalls nested podman needs. This is a real isolation reduction; a Podman host is recommended for nested mode.

#### Cleaning up nested storage

The storage volume grows without bound (inner images, stopped inner containers, build cache, inner volumes). Selective, inside a session: `podman system prune -a` (add `podman volume prune` for inner volumes). Blunt, from the host: `clause podman reset` removes the bound profile's whole volume after confirmation; it is recreated empty on the next launch, and inner *volumes* (which may hold data, for example a dev database) are deleted with it. `clause profile delete` removes the volume automatically along with the image.

#### Notes and limitations

- Rebuild after enabling (`clause image build`); the block adds roughly 200 MB to the image (podman, uidmap, slirp4netns, fuse-overlayfs, podman-compose, lazydocker).
- lazydocker's config and UI state live inside the image, not in a bind mount: the podman-compose config is baked in, and any state lazydocker saves resets each session.
- Profiles that enabled nested podman before lazydocker was added keep the old block text: run `clause podman disable` then `clause podman enable` (strip and re-append), then rebuild.
- Ports published by inner containers bind inside the session's network namespace: reachable from within the session, not from the host.
- Resource limits on inner containers (`--memory`, `--cpus`) are unavailable (no cgroup delegation).
- The host image cache is not shared; the first pull of an image per profile hits the network, after which the profile volume caches it.
- Hosts that restrict unprivileged user namespaces via AppArmor (Ubuntu 23.10+ hardening) may need a host-side exception if inner podman fails with permission errors while creating user namespaces.

### Claude args

The args appended to `claude` at launch come from one of three places, in this precedence:

1. `-a, --args <string>`: one-shot override for this launch only.
2. `$WORKSPACE/.clause/args`: workspace-local override; a present file wins even if empty. Manage with `config --local args <string>`.
3. `~/.clause/profiles/<profile>/args`: profile default, seeded on profile creation. Manage with `config args <string>`.

The seeded default is `--dangerously-skip-permissions`; effort lives in the sibling `effort` file and is injected into the args at launch.

```bash
# One-shot override for this launch
clause -a '--effort high'

# Print the effective args value (scriptable; clause status shows the full launch line)
clause config --get args

# Write the bound profile's default
clause config args '--dangerously-skip-permissions'

# Write a workspace-local override
clause config --local args '--effort low'

# Delete the workspace override so args fall through to the profile default
clause config --local --reset args

# Restore the profile default to the shipped template value
clause config --reset args

# Opt out of args entirely (writes an empty file, distinct from --reset)
clause config args ''
```

Config writes target the bound profile by default; `--local` (short `-l`) targets the workspace override instead, and is required for writes to it. Resetting means "undo my customization at this tier": `config --local --reset args` *deletes* the workspace file so args fall through to the profile, while `config --reset args` *rewrites* the profile file with the repo template value (profile `args`/`effort` are required launch files, so the profile tier restores its default rather than leaving a hole). Both are distinct from `config args ''`, which *writes* a present-but-empty file meaning "no args", an explicit opt-out of every layer. Under `-t/--terminal`, bash itself gets no args, but the resolved args are still exported as `CLAUSE_ARGS` for the in-container alias (see [Inside the container](#inside-the-container)).

### Effort override

Effort (`claude --effort <level>`) is a layered setting, seeded as `max` in every profile so you never have to embed `--effort` in an args string. It resolves through the same three layers as args (`-e` one-shot, then workspace `.clause/effort`, then profile `effort`) and is injected into the effective args at launch, replacing any `--effort` already present, so the final command always carries exactly one `--effort`. Valid levels are `low`, `medium`, `high`, `xhigh`, and `max` (the flag accepts `max` even though `settings.json`'s `effortLevel` does not).

```bash
# One-shot: run this launch at high effort
clause -e high

# The bound profile's default effort
clause config effort xhigh

# Workspace-local override (this directory), then inspect it
clause config --local effort high
clause config --get effort

# Drop the workspace override / restore the profile template default (max)
clause config --local --reset effort
clause config --reset effort
```

- A one-shot `-a/--args` is a complete args override, so it bypasses the stored effort files too; only a one-shot `-e` refines an `-a` line.
- An empty or whitespace effort file means "unset" and falls through to the next layer (unlike `args`, where present-but-empty means "no args"); a file holding an unrecognized level is ignored with a warning at launch.
- Because effort is injected into the resolved args, an `--effort` embedded in an `args` value is always overridden (at minimum by the seeded profile `max`). Set effort with `config [--local] effort <level>`, not inside `args`.

## Mount override

Claude keys its per-project state (`~/.claude/projects/…`, history, todos) by the container cwd, so moving a folder on the host changes the encoded path and orphans that history. The mount override pins the container-side path: `clause config --local mount <path>` writes the workspace-local file `$WORKSPACE/.clause/mount` holding a logical absolute host path, which `clause` encodes to form the mount target and cwd. The key lives only at the workspace tier, so the `--local` is mandatory: `config mount <path>` errors rather than guessing the scope. Only the container-side path is pinned; the bind-mount *source* is always the real workspace, so the moved files still mount. Because the file lives inside the workspace it moves with the folder, which is what keeps the pin in effect; pin the current path *before* moving (or, after a move, pin the old path).

```bash
# Before moving /home/tom/projects/myapp somewhere else, pin its path:
cd /home/tom/projects/myapp
clause config --local mount "$(pwd -P)"   # writes ./.clause/mount

# ...move the folder anywhere on the host; the file moves with it...
mv /home/tom/projects/myapp /home/tom/work/myapp

# The container cwd (and Claude's history) is unchanged:
cd /home/tom/work/myapp
clause                              # still /workspace/-home-tom-projects-myapp

# Inspect / clear:
clause status                       # shows the effective "mount:" line + source
clause config --local --reset mount # revert to encoding the real path
```

- Pass the canonical path (use `$(pwd -P)` to resolve symlinks): absolute, no trailing slash, no `.`/`..`. `config --local mount` rejects bad values at parse time; a hand-edited invalid `.clause/mount` is ignored with a warning at launch, falling back to the real path.
- The override changes container *layout*, not `claude` args, so it applies to `-t/--terminal` sessions too.

## Status

`clause status` prints the effective configuration for the current directory: the resolved profile, its workspace binding, the container mount path, the raw `claude` args, the effective effort, the effort-injected `launch:` line a launch actually passes, the container runtime, and whether the image is built, resolving each key to the single value a launch would use and naming its source. It is read-only (it never creates `~/.clause`) and tolerant of a missing profile or runtime, so it is safe to run before anything is set up.

```
$ clause status
profile: work
binding: /home/tom/app → work
mount:   /workspace/-home-tom-app
args:    --dangerously-skip-permissions  (source: ...)
effort:  max  (source: ...)
launch:  --dangerously-skip-permissions --effort max
runtime: podman
image:   clause-work (built)
```

For the built-in `default` profile, the effective views (`status` and `config --get`) read an unseeded profile `args`/`effort` from the repo `default/` template (source `default template`), matching what a launch would use, since a real launch seeds those files before reading them. A present-but-empty file is a real value and is not overridden. Named profiles never fall back: they error at launch on missing files, so their unseeded keys read `(no args)` / `(unset)`.

`clause config --list` is the complementary *stored* view: what each scope actually holds, with no cross-tier resolution and no template fallback. A key with no file reads `(unset)`, a present-but-empty file `(empty)`; `mount` appears only under `workspace` (it has no profile tier).

```
$ clause config --list
workspace (/home/tom/app/.clause):
  args:   (unset)
  effort: (unset)
  mount:  (unset)
profile default (/home/tom/.clause/profiles/default):
  args:   --dangerously-skip-permissions
  effort: max
```

## Workspace Binding

`clause` records which profile a workspace uses in a single file inside the workspace, `<workspace>/.clause/profile`, written by `clause bind [profile]` (shortcut: `clause -p [profile]`). Because the binding lives in the folder it travels with the folder, and there is no central registry to keep in sync. An unbound workspace uses `default`; the first launch from one offers to save that binding (`y` save, `n` continue without saving, `q` exit). If a binding already exists, `bind` prompts before rebinding.

```bash
# Bind this workspace to a profile (the only way to select a non-default profile)
clause bind work

# Show the current binding and mount
clause status

# Remove the current binding
clause bind --unset

# Skip prompts in scripts
clause -y
```

Because bindings are local files they are not enumerable from one place: `profile list` shows the installed profiles and `status` shows the current workspace's binding, but there is no global workspace-to-profile list. For the same reason `profile delete` cannot unbind other workspaces; a workspace still pointing at a deleted profile errors on its next launch until you rebind it.

## Shell Alias

```bash
clause alias create
```

This checks for `~/.bashrc` and `~/.zshrc` and prompts to append a `clause` alias to each file found, skipping files that already have it; `clause alias delete` removes it. Only aliases created by `alias create` are detected (they carry a `# clause-alias` marker); a hand-written `alias clause=...` is invisible to both commands and may end up duplicated.

### Inside the container

The container image bakes its own `clause` alias into the container user's `~/.bashrc`. The alias expands the `CLAUSE_ARGS` environment variable, which every launch sets to the effort-injected args the wrapper resolved for that workspace: the same line `clause status` shows as `launch:`. Running `clause` from any shell inside a session (for example one started with `-t/--terminal`) therefore starts claude exactly as a normal launch would; with the shipped defaults that is `claude --dangerously-skip-permissions --effort max`. Extra flags pass through (`clause -c` appends `-c`), and if `CLAUSE_ARGS` is empty or unset the alias runs bare `claude`.

The base image also bundles [lazygit](https://github.com/jesseduffield/lazygit) with an `lg` alias (fetched from the latest GitHub release at build time; x86_64 and arm64). These lines are baked in at build time, so rebuild to pick up changes; profiles whose `Containerfile` predates them need a manual edit first (or delete the profile's `Containerfile` and rerun `clause image build` to re-seed it).

## Persistence

Each profile's data is stored under `~/.clause/profiles/<name>/` and bind-mounted into the container:

| What | Host path | Container path |
|------|-----------|----------------|
| Credentials, history, plugins, cache, hooks | `~/.clause/profiles/<name>/.claude/` | `/home/claude/.claude/` |
| Settings, first-run state | `~/.clause/profiles/<name>/.claude.json` | `/home/claude/.claude.json` |
| Git configuration | `~/.clause/profiles/<name>/.gitconfig` | `/home/claude/.gitconfig` |
| Containerfile (per profile) | `~/.clause/profiles/<name>/Containerfile` | not mounted (build input) |
| Profile args and effort | `~/.clause/profiles/<name>/args`, `effort` | not mounted (read by `clause` on launch) |
| Workspace config (binding, args, effort, mount) | `<workspace>/.clause/` | not mounted (read by `clause` on launch) |
| sudo activity log | `~/.clause/profiles/<name>/.claude/clause-sudo.log` | `/home/claude/.claude/clause-sudo.log` |
| Nested podman storage (inner images, containers) | named volume `clause-<name>-containers` | `/home/claude/.local/share/containers` |
| Workspace | `$PWD` (or `-w path`) | `/workspace/<encoded-host-path>` (pinnable via `.clause/mount`) |

`~/.clause/` is created automatically on first run, each profile seeded from the repo's `default/` template (the sole source of a profile's initial files; nothing is generated in code). When `clause` first creates a workspace's `.clause/` directory it drops a `.gitignore` containing a single `*`, so the enclosing repo ignores the clause state automatically; the file is created only when absent, so a hand-edited `.gitignore` is never overwritten.
