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
clause --runtime-set docker
```

## Getting Started

```bash
# 1. Make the script executable:
chmod +x clause

# 2. Add the shell alias** so you can run `clause` from any directory:
./clause --alias-create

# 3. Then reload your shell (`source ~/.bashrc` or open a new terminal).
source ~/.bashrc

# 4. Build the container image:**
clause -b

# 5. Start Claude in your project:
cd ~/your-project
clause
```

That's it. Claude Code runs inside the container with your project mounted under `/workspace/`.

## Usage

```
usage: clause [-h] [profile] [options]

arguments:
  profile                 Profile to use (default: 'default')

session options:
  -a, --args <value>      One-shot claude args (overrides clause-args files)
  -t, --terminal          Launch bash instead of claude
  -w, --workspace <path>  Workspace directory (default: $PWD)

prompt options:
  -y, --yes               Auto-answer yes to prompts (destructive
                          confirmations still require typing 'yes')
  -n, --no                Auto-answer no to all prompts

mapping (then exit):
  -m, --map               Add workspace→profile mapping
  -u, --unmap             Remove workspace→profile mapping
  -l, --list              Show current mapping and list all profiles
  -L, --list-all          List all workspace→profile mappings

profile management (then exit):
  -C, --create-profile        Create a new profile (Containerfile + clause-args seeded)
  -D, --delete-profile        Delete a profile and remove its mappings
  -R, --reset-containerfile   Overwrite profile Containerfile with default
  -S, --suggest-updates       Suggest Containerfile updates from sudo log

arguments (then exit):
  -A, --args-view                 Print effective claude args + source
      --args-set <value>          Write workspace .clause-args (this directory)
      --args-set-profile <value>  Write profile clause-args
                                  Default: --effort max --dangerously-skip-permissions

nested podman (then exit):
  -P, --podman-enable     Enable nested podman for profile (marker + Containerfile block)
      --podman-disable    Disable nested podman for profile
      --podman-reset      Remove the profile's nested-podman storage volume

alias management (then exit):
  --alias-create          Add clause alias to .bashrc and/or .zshrc
  --alias-delete          Remove clause alias from .bashrc and/or .zshrc

runtime management (then exit):
  --runtime-set <value>   Set container runtime override (podman or docker)
  --runtime-remove        Remove container runtime override

other:
  -b, --build             Build the container image
  -h, --help              Print this help
```

`clause` runs one command per invocation: the "(then exit)" flags and `-b` are commands, and launching a session is the default when none is given. Combining two commands (for example `clause -m --alias-create`) is an error, raised before anything runs. The session and prompt options plus the profile argument combine freely with any command.

Running `clause` launches Claude Code inside the container with your current directory mounted under `/workspace/` at an encoded subpath (e.g. `/home/tom/projects/myapp` → `/workspace/-home-tom-projects-myapp`). The container's working directory is set to that subpath, so each host workspace gets its own cwd — keeping Claude's per-project state separate when multiple workspaces share a profile.

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `~/.clause/profiles/` with its own `.claude/`, `.claude.json`, `Containerfile`, and `clause-args`. The `default` profile is created automatically on first run.

The default `settings.json` also wires up Claude Code hooks that tint the container terminal's background while Claude is working; they call a small `set-bg.sh` script seeded into the profile's `~/.claude/hooks/` (from `default/.claude/hooks/set-bg.sh`) on first use.

```bash
# Create a profile (also maps this workspace to it; prompts first if the
# workspace is already mapped to a different profile)
clause work -C

# Use a profile
clause work

# Show current mapping and list all profiles
clause -l

# Delete a profile (also removes its workspace mappings and image)
clause work -D
```

### Per-profile Container Images

Every profile gets its own `Containerfile` (copied from `default/Containerfile` when the profile is created) and builds to a profile-specific image `clause-<profile>`.

```bash
# Edit ~/.clause/profiles/work/Containerfile as needed, then build
clause work -b

# Overwrite a profile's Containerfile with the default again
clause work -R
```

- `-b` / `--build` is profile-aware: it builds `clause-<profile>` from the profile's `Containerfile`, first seeding any missing profile files (including the `Containerfile`) from the repo's `default/`. Every image is `clause-<profile>`; there is no shared fallback image.
- `-R` / `--reset-containerfile` overwrites the profile's `Containerfile` with the current default.

### Nested Podman

Opt-in, per profile: run podman *inside* the session (build images, run service containers, use `podman compose`) without giving the session any access to the host container engine. Inner containers run rootless inside the session's user namespace, so the sandbox stays intact: even a full escape from an inner container only lands in the jailed session user.

```bash
# Enable: writes the profile's nested marker and offers to append the
# managed nested-podman block to the profile Containerfile; then rebuild
clause work --podman-enable
clause work -b

# Inside the session, podman just works
podman run --rm docker.io/library/hello-world

# Disable again (offers to strip the Containerfile block)
clause work --podman-disable
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
- Blunt, from the host: `clause work --podman-reset` removes the whole volume after confirmation; it is recreated empty on the next launch. This also deletes inner *volumes*, which may hold data (for example a dev database).

`clause work -D` (delete profile) removes the volume automatically along with the image and mappings.

#### Notes and limitations

- Rebuild after enabling (`clause <profile> -b`); the block adds roughly 200 MB to the image (podman, uidmap, slirp4netns, fuse-overlayfs, podman-compose, lazydocker).
- lazydocker's config and UI state live at `~/.config/lazydocker` inside the image, not in a bind mount: the podman-compose config is baked in, and any state lazydocker saves resets each session.
- Profiles that enabled nested podman before lazydocker was added keep the old block text: run `--podman-disable` then `--podman-enable` (strip and re-append), then rebuild.
- Ports published by inner containers bind inside the session's network namespace: reachable from within the session, not from the host.
- Resource limits on inner containers (`--memory`, `--cpus`) are unavailable (no cgroup delegation).
- The host image cache is not shared; the first pull of an image per profile hits the network, after which the profile volume caches it.
- Hosts that restrict unprivileged user namespaces via AppArmor (Ubuntu 23.10+ hardening) may need a host-side exception if inner podman fails with permission errors while creating user namespaces.

### Claude args

The args appended to `claude` at launch come from one of three places, in this precedence:

1. **`-a, --args <string>`** — one-shot CLI override for this launch only.
2. **`$WORKSPACE/.clause-args`** — workspace-local override. Present (even empty) wins over the profile file. Manage with `--args-set <string>`.
3. **`$PROFILE_DIR/clause-args`** — profile default at `~/.clause/profiles/<profile>/clause-args`, seeded on profile creation. Manage with `--args-set-profile <string>`.

The seeded default content is:

```
--effort max --dangerously-skip-permissions
```

```bash
# One-shot override for this launch
clause work -a '--effort high'

# Print what would actually be used (and from where)
clause work -A

# Write workspace-local override
clause --args-set '--effort low'

# Write profile-wide default
clause work --args-set-profile '--effort max --dangerously-skip-permissions'
```

Args are ignored under `-t/--terminal` (bash mode passes no args); from a `-t` shell, the in-container `clause` alias starts claude with the default max/bypass args (see [Shell Alias](#shell-alias)). An empty args file at either level means "no args" (a present-but-empty file explicitly opts out).

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
clause work -m

# Show the current mapping (plus all profiles)
clause -l

# Remove the current mapping
clause -u

# List all mappings
clause -L

# Skip prompts in scripts
clause work -y
```

## Shell Alias

Add a `clause` alias to your shell so you can run it from any directory without specifying the full path:

```bash
clause --alias-create
```

This checks for `~/.bashrc` and `~/.zshrc` and prompts to append the alias to each file found. If the alias already exists in a file, it is skipped. To remove it:

> **Note:** Only aliases created by `--alias-create` are detected (they contain a `# clause-alias` marker). Manually created `alias clause=...` entries without this marker will not be detected and may result in duplicates.

```bash
clause --alias-delete
```

### Inside the container

The container image bakes its own `clause` alias into the container user's `~/.bashrc`. From any interactive shell inside a session (for example one started with `-t/--terminal`), running `clause` launches `claude --effort max --dangerously-skip-permissions`, matching the seeded profile default. Extra flags pass through: `clause -c` runs `claude --effort max --dangerously-skip-permissions -c`.

The base image also bundles [lazygit](https://github.com/jesseduffield/lazygit) with an `lg` alias. The binary is fetched from the latest GitHub release at build time (arch-aware: x86_64 and arm64).

These lines are baked in at build time, so rebuild to pick them up (`clause -b`). Profiles whose `Containerfile` predates them need `clause <profile> -R` first (or add the lines manually), then a rebuild.

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
| sudo activity log | `~/.clause/profiles/<name>/.claude/clause-sudo.log` | `/home/claude/.claude/clause-sudo.log` |
| Nested podman storage (inner images, containers) | named volume `clause-<name>-containers` | `/home/claude/.local/share/containers` |
| Workspace mappings | `~/.clause/clause.conf` | — |
| Workspace | `$PWD` (or `-w path`) | `/workspace/<encoded-host-path>` |

All runtime state lives in `~/.clause/` and is created automatically on first run. Nothing in the clause repo needs to be gitignored for runtime data.

## Rebuilding

After changes to `Containerfile`:

```bash
clause -b
```

`--build` is profile-aware: it builds the `clause-<profile>` image from the profile's `Containerfile` at `~/.clause/profiles/<profile>/Containerfile`, seeding that file from the repo default first if the profile does not have one yet. The profile must exist (`default` is created automatically on first use).
