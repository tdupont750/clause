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
clause runtime set docker
```

## Getting Started

```bash
# 1. Make the script executable:
chmod +x clause

# 2. Add the shell alias** so you can run `clause` from any directory:
./clause alias create

# 3. Then reload your shell (`source ~/.bashrc` or open a new terminal).
source ~/.bashrc

# 4. Build the container image:**
clause image build

# 5. Start Claude in your project:
cd ~/your-project
clause
```

That's it. Claude Code runs inside the container with your project mounted under `/workspace/`.

## Usage

```
usage: clause [profile] [session options]     launch Claude (default)
       clause <command> ...                    manage clause, then exit

A bare word is the profile to launch (default: 'default'); everything else is a
command. Run `clause run <profile>` to launch a profile named like a command.

session options (shape the launch; combine with any command):
  -t, --terminal          Launch bash instead of claude
  -w, --workspace <path>  Workspace directory (default: $PWD)
  -a, --args <value>      One-shot claude args (overrides clause-args files)
  -e, --effort <level>    One-shot effort override: low|medium|high|xhigh|max
      --mount <path>      One-shot mount-path override (overrides .clause-mount)
  -y, --yes               Auto-answer yes to prompts (destructive
                          confirmations still require typing 'yes')
  -n, --no                Auto-answer no to all prompts

commands (then exit):
  config   [--profile] <key> [value]      Get/set a config key (keys: args, effort, mount)
           --get <key> | --unset <key> | --list [--show-origin]
  profile  create [name] | delete [name] | list
  image    build [profile] | reset [profile] | suggest [profile]
  map      add [profile] | remove | list | show
  podman   enable [profile] | disable [profile] | reset [profile]
  alias    create | delete
  runtime  set <podman|docker> | unset
  status                                  Effective config for this directory
  run [profile]                           Launch a profile whose name matches a command
  -h, --help                              Print this help
```

`clause` runs one command per invocation. A bare word is a profile to launch, which is the default when no command is given; the subcommands `config`, `profile`, `image`, `map`, `podman`, `alias`, `runtime`, and `status` each manage clause and then exit. Combining two commands (for example `clause status map add`) is an error, raised before anything runs (`map add conflicts with status`). Session options (`-t`, `-w`, `-a`, `-e`, `--mount`, `-y`, `-n`) go before the subcommand, and the target profile can go before it too (`clause work image build`) or be given as the command's trailing argument (`clause image build work`). Because those words are reserved as commands, a profile cannot be named `config`, `profile`, `image`, `map`, `podman`, `alias`, `runtime`, `status`, or `run`; to launch a profile whose name matches a command word, use `clause run <profile>`.

Running `clause` launches Claude Code inside the container with your current directory mounted under `/workspace/` at an encoded subpath (e.g. `/home/tom/projects/myapp` → `/workspace/-home-tom-projects-myapp`). The container's working directory is set to that subpath, so each host workspace gets its own cwd, keeping Claude's per-project state separate when multiple workspaces share a profile. That subpath can be pinned so it survives moving the folder on the host (see [Mount override](#mount-override)).

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `~/.clause/profiles/` with its own `.claude/`, `.claude.json`, `Containerfile`, and `clause-args`. The `default` profile is created automatically on first run.

The default `settings.json` also wires up Claude Code hooks that tint the container terminal's background while Claude is working; they call a small `set-bg.sh` script seeded into the profile's `~/.claude/hooks/` (from `default/.claude/hooks/set-bg.sh`) on first use.

The default `settings.json` ships with two official Claude Code plugins enabled for every new profile, via `enabledPlugins`: `skill-creator` and `claude-md-management` (both from the built-in `claude-plugins-official` marketplace, which the CLI registers and auto-installs on launch). They install on the profile's first session, so that session needs network access. Profiles created before this default are not changed, because seeding never overwrites an existing `settings.json`; enable them by hand with `/plugin` or by adding the same `enabledPlugins` block to that profile's `~/.clause/profiles/<name>/.claude/settings.json`.

The default `settings.json` also sets `effortLevel` to `xhigh` (Claude Code's setting for startup reasoning effort). Normal launches pass `--effort` through `clause-args`, and that flag overrides the setting, so `effortLevel` only takes effect for a bare `claude` run inside a `-t` terminal session, where no `--effort` flag is passed. To change the effort a normal launch uses, set an effort override (see [Effort override](#effort-override)) rather than editing this setting. As with the plugins, existing profiles are not changed.

```bash
# Create a profile (also maps this workspace to it; prompts first if the
# workspace is already mapped to a different profile)
clause profile create work

# Use a profile
clause work

# List all profiles
clause profile list

# Delete a profile (also removes its workspace mappings and image)
clause profile delete work
```

### Per-profile Container Images

Every profile gets its own `Containerfile` (copied from `default/Containerfile` when the profile is created) and builds to a profile-specific image `clause-<profile>`.

```bash
# Edit ~/.clause/profiles/work/Containerfile as needed, then build
clause image build work

# Overwrite a profile's Containerfile with the default again
clause image reset work
```

- `image build` is profile-aware: it builds `clause-<profile>` from the profile's `Containerfile`, first seeding any missing profile files (including the `Containerfile`) from the repo's `default/`. Every image is `clause-<profile>`; there is no shared fallback image.
- `image reset` overwrites the profile's `Containerfile` with the current default.

### Nested Podman

Opt-in, per profile: run podman *inside* the session (build images, run service containers, use `podman compose`) without giving the session any access to the host container engine. Inner containers run rootless inside the session's user namespace, so the sandbox stays intact: even a full escape from an inner container only lands in the jailed session user.

```bash
# Enable: writes the profile's nested marker and offers to append the
# managed nested-podman block to the profile Containerfile; then rebuild
clause podman enable work
clause image build work

# Inside the session, podman just works
podman run --rm docker.io/library/hello-world

# Disable again (offers to strip the Containerfile block)
clause podman disable work
```

Nested images also bundle [lazydocker](https://github.com/jesseduffield/lazydocker), wired to podman: the `lazydocker` shell function (alias `ld`) starts podman's docker-compatible API socket on demand (`podman system service`) and points `DOCKER_HOST` at it, and a baked-in `~/.config/lazydocker/config.yml` maps compose actions to `podman-compose`. The binary is fetched from the latest GitHub release at build time (arch-aware: x86_64 and arm64).

When nested podman is enabled, `clause` launches the session with:

- `--device /dev/fuse` and `--device /dev/net/tun` (each skipped with a warning if the host lacks it)
- `--security-opt label=disable` (SELinux labeling breaks nested mounts; a no-op on non-SELinux hosts)
- a named volume `clause-<profile>-containers` mounted at `/home/claude/.local/share/containers`, so inner images persist across the ephemeral sessions
- under a Docker host runtime, additionally `seccomp=unconfined` and `apparmor=unconfined`, because Docker's default profiles block the syscalls nested podman needs. This is a real isolation reduction; a Podman host is recommended for nested mode.

#### Cleaning up nested storage

The storage volume grows without bound (inner images, stopped inner containers, build cache, inner volumes). Two cleanup paths:

- Selective, inside a session: `podman system prune -a` (add `podman volume prune` for inner volumes).
- Blunt, from the host: `clause podman reset work` removes the whole volume after confirmation; it is recreated empty on the next launch. This also deletes inner *volumes*, which may hold data (for example a dev database).

`clause profile delete work` (delete profile) removes the volume automatically along with the image and mappings.

#### Notes and limitations

- Rebuild after enabling (`clause image build <profile>`); the block adds roughly 200 MB to the image (podman, uidmap, slirp4netns, fuse-overlayfs, podman-compose, lazydocker).
- lazydocker's config and UI state live at `~/.config/lazydocker` inside the image, not in a bind mount: the podman-compose config is baked in, and any state lazydocker saves resets each session.
- Profiles that enabled nested podman before lazydocker was added keep the old block text: run `clause podman disable <profile>` then `clause podman enable <profile>` (strip and re-append), then rebuild.
- Ports published by inner containers bind inside the session's network namespace: reachable from within the session, not from the host.
- Resource limits on inner containers (`--memory`, `--cpus`) are unavailable (no cgroup delegation).
- The host image cache is not shared; the first pull of an image per profile hits the network, after which the profile volume caches it.
- Hosts that restrict unprivileged user namespaces via AppArmor (Ubuntu 23.10+ hardening) may need a host-side exception if inner podman fails with permission errors while creating user namespaces.

### Claude args

The args appended to `claude` at launch come from one of three places, in this precedence:

1. **`-a, --args <string>`** — one-shot CLI override for this launch only.
2. **`$WORKSPACE/.clause-args`** — workspace-local override. Present (even empty) wins over the profile file. Manage with `config args <string>`.
3. **`$PROFILE_DIR/clause-args`** — profile default at `~/.clause/profiles/<profile>/clause-args`, seeded on profile creation. Manage with `config --profile args <string>`.

The seeded default content is:

```
--effort max --dangerously-skip-permissions
```

```bash
# One-shot override for this launch
clause work -a '--effort high'

# Print the effective args value (scriptable; clause status shows the full launch line)
clause work config --get args

# Write workspace-local override
clause config args '--effort low'

# Write profile-wide default
clause work config --profile args '--effort max --dangerously-skip-permissions'

# Delete the workspace override so args fall through to the profile default
clause config --unset args

# Delete the profile override too
clause work config --profile --unset args

# Opt out of args entirely (writes an empty file, distinct from --unset)
clause config args ''
```

Args are ignored under `-t/--terminal` (bash mode passes no args); from a `-t` shell, the in-container `clause` alias starts claude with the default max/bypass args (see [Shell Alias](#shell-alias)). An empty args file at either level means "no args" (a present-but-empty file explicitly opts out).

Removing versus emptying an override are different operations:

- **`config --unset args`** *deletes* the workspace `.clause-args` file, so args fall through to the profile default (`config --profile --unset args` does the same for the profile `clause-args` file).
- **`config args ''`** *writes* a present-but-empty file, which means "no args": an explicit opt-out of args entirely, even the profile's.

### Effort override

Effort (`claude --effort <level>`) has a dedicated override so you don't have to rewrite the whole args string to change it. It resolves in the same three layers as the args and is injected into the effective args at launch (it replaces an existing `--effort`, or is appended if absent), so the final command always carries exactly one `--effort`:

1. **`-e, --effort <level>`** sets the effort for this launch only.
2. **`$WORKSPACE/.clause-effort`** is a workspace-local default; manage with `config effort <level>` / `config --unset effort`.
3. **`$PROFILE_DIR/effort`** is the profile default at `~/.clause/profiles/<name>/effort`; manage with `config --profile effort <level>` / `config --profile --unset effort`.

Valid levels are `low`, `medium`, `high`, `xhigh`, and `max` (the `--effort` flag accepts `max` even though `settings.json`'s `effortLevel` does not list it).

```bash
# One-shot: run this launch at high effort
clause work -e high

# Workspace-local default (this directory), then inspect it
clause config effort high
clause work config --get effort

# Profile-wide default effort
clause work config --profile effort xhigh

# Clear an override (fall back to the next layer down)
clause config --unset effort
clause work config --profile --unset effort
```

- A one-shot `-a/--args` is a complete args override for that launch, so it bypasses the stored effort files too; only a one-shot `-e` refines an `-a` line.
- An empty or whitespace effort file means "unset" and falls through to the next layer (unlike `.clause-args`, where a present-but-empty file means "no args"); a file holding an unrecognized level is ignored with a warning at launch.
- The override affects normal `claude` launches only. It seeds no files and does not touch `settings.json`, so default behavior is unchanged until you set one, and bare `claude` in a `-t` terminal keeps using `effortLevel` as before.
- `clause status` shows the post-injection launch args and names the effort source; `config --get args` prints only the raw args value (before effort injection) and `config --get effort` the effort, both scriptable.

## Mount override

By default the host workspace is mounted inside the container at an encoded subpath and the container cwd is set to it (`/home/tom/projects/myapp` → `/workspace/-home-tom-projects-myapp`). Claude keys its per-project state (`~/.claude/projects/…`, history, todos) by that cwd, so **moving the folder on the host** changes the encoded path and orphans that history.

The mount override lets you pin the container-side path so it stays constant no matter where the host folder lives. The pin resolves in two layers:

1. **`--mount <path>`** overrides the mount path for this launch only.
2. **`$WORKSPACE/.clause-mount`** is a workspace-local file; manage it with `config mount <path>` / `config --unset mount`.

With neither, the real workspace path is used (unchanged default). The file stores a *logical absolute host path*; `clause` encodes it the same way to form the mount target and cwd. Only the container-side path is pinned: the bind-mount **source is always the real workspace**, so the moved files still mount.

The file lives **inside the workspace**, so it *travels with the folder* when you move it, which is what keeps the pin in effect after the move. Pin the current path **before moving** (or, after a move, pin the old path):

```bash
# Before moving /home/tom/projects/myapp somewhere else, pin its path:
cd /home/tom/projects/myapp
clause config mount "$(pwd -P)"     # writes ./.clause-mount

# ...move the folder anywhere on the host; the file moves with it...
mv /home/tom/projects/myapp /home/tom/work/myapp

# The container cwd (and Claude's history) is unchanged:
cd /home/tom/work/myapp
clause                              # still /workspace/-home-tom-projects-myapp

# Inspect / clear:
clause map show                     # shows the effective "mount:" line + source
clause config --unset mount        # revert to encoding the real path
```

- Pass the **canonical** path (use `$(pwd -P)` to resolve symlinks). The value must have **no trailing slash** (except root) and no `.`/`..`; otherwise the encoded path won't match what Claude recorded. `--mount` / `config mount` reject a trailing slash at parse time, and a hand-edited `.clause-mount` with an invalid value is ignored with a warning at launch (falling back to the real path).
- The override changes container *layout*, not `claude` args, so it applies to `-t/--terminal` sessions too (the cwd is pinned in bash as well).
- `clause map show` reports the effective mount path and, when overridden, its source.

## Status

`clause status` prints the effective configuration for the current directory in one place: the resolved profile, its workspace mapping, the container mount path, the effective `claude` args, the effective effort, the container runtime, and whether the `clause-<profile>` image is built. For just the three config keys (args, effort, mount) and where each resolves from, use `clause config --list --show-origin` (the `git config --list` analog); `status` is the broader dashboard that also covers the profile, mapping, runtime, and image.

It is read-only (it never creates `~/.clause`) and tolerant of a missing profile or absent container runtime, so it is safe to run before anything is set up: those fields simply report that nothing exists yet.

```
$ clause status
profile: work
mapping: /home/tom/app → work
mount:   /workspace/-home-tom-app
args:    --effort max --dangerously-skip-permissions  (source: ...)
effort:  max  (source: ...)
runtime: podman
image:   clause-work (built)
```

## Workspace Mappings

`clause` remembers which profile to use for each workspace directory in `clause.conf`. On first use from a directory, you'll be prompted to save the mapping.

```
No mapping found. Save /home/tom/projects/myapp → work? [y/n/q]
```

- `y` — save mapping and continue
- `n` — continue without saving
- `q` — exit

If a mapping already exists but you specify a different profile, you'll be prompted to override it.

```bash
# Explicitly add a mapping without starting a session
clause map add work

# Show the current mapping and mount
clause map show

# Remove the current mapping
clause map remove

# List all mappings
clause map list

# Skip prompts in scripts
clause work -y
```

## Shell Alias

Add a `clause` alias to your shell so you can run it from any directory without specifying the full path:

```bash
clause alias create
```

This checks for `~/.bashrc` and `~/.zshrc` and prompts to append the alias to each file found. If the alias already exists in a file, it is skipped. To remove it:

> **Note:** Only aliases created by `alias create` are detected (they contain a `# clause-alias` marker). Manually created `alias clause=...` entries without this marker will not be detected and may result in duplicates.

```bash
clause alias delete
```

### Inside the container

The container image bakes its own `clause` alias into the container user's `~/.bashrc`. From any interactive shell inside a session (for example one started with `-t/--terminal`), running `clause` launches `claude --effort max --dangerously-skip-permissions`, matching the seeded profile default. Extra flags pass through: `clause -c` runs `claude --effort max --dangerously-skip-permissions -c`.

The base image also bundles [lazygit](https://github.com/jesseduffield/lazygit) with an `lg` alias. The binary is fetched from the latest GitHub release at build time (arch-aware: x86_64 and arm64).

These lines are baked in at build time, so rebuild to pick them up (`clause image build`). Profiles whose `Containerfile` predates them need `clause image reset <profile>` first (or add the lines manually), then a rebuild.

## Persistence

Each profile's data is stored under `~/.clause/profiles/<name>/` and bind-mounted into the container:

| What | Host path | Container path |
|------|-----------|----------------|
| Credentials, history, plugins, cache, hooks | `~/.clause/profiles/<name>/.claude/` | `/home/claude/.claude/` |
| Settings, first-run state | `~/.clause/profiles/<name>/.claude.json` | `/home/claude/.claude.json` |
| Git configuration | `~/.clause/profiles/<name>/.gitconfig` | `/home/claude/.gitconfig` |
| Containerfile (per profile) | `~/.clause/profiles/<name>/Containerfile` | — (build input) |
| Claude args (profile) | `~/.clause/profiles/<name>/clause-args` | — (read by `clause` on launch) |
| Claude args (workspace override) | `<workspace>/.clause-args` | — (read by `clause` on launch) |
| Mount path override (workspace) | `<workspace>/.clause-mount` | (read by `clause` on launch) |
| sudo activity log | `~/.clause/profiles/<name>/.claude/clause-sudo.log` | `/home/claude/.claude/clause-sudo.log` |
| Nested podman storage (inner images, containers) | named volume `clause-<name>-containers` | `/home/claude/.local/share/containers` |
| Workspace mappings | `~/.clause/clause.conf` | — |
| Workspace | `$PWD` (or `-w path`) | `/workspace/<encoded-host-path>` (pinnable via `.clause-mount`) |

All runtime state lives in `~/.clause/` and is created automatically on first run. Nothing in the clause repo needs to be gitignored for runtime data.

## Rebuilding

After changes to `Containerfile`:

```bash
clause image build
```

`image build` is profile-aware: it builds the `clause-<profile>` image from the profile's `Containerfile` at `~/.clause/profiles/<profile>/Containerfile`, seeding that file from the repo default first if the profile does not have one yet. The profile must exist (`default` is created automatically on first use).
