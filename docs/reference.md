# Reference

Full behavior of `clause`: every command, flag, config key, and precedence rule.
The [README](../README.md) covers installation and the high-level concepts; this
file is the detail behind them. The historical rationale lives in
[decisions.md](decisions.md).

## Command grammar

`clause` runs one command per invocation: with no command it launches the profile
bound to the current workspace (`default` until you bind one), and naming two
commands is a parse-time error. Session options go before the command. Two
commands have flag-spelled shortcuts: `-b` runs `image build`, and `-p <profile>`
is an alias for `bind <profile>` (including `-p --unset`).

A profile name is only ever typed to `bind <profile>` and `profile create <name>` /
`profile delete <name>`, where it is required; every other command (launch, `image`,
and `podman` included) acts on the workspace's bound profile, so profiles named like
command words never collide with them. A leading bare word is an unknown-command
error.

Input is validated at parse time, before any side effects: effort levels, mount
paths, config keys, and profile names are all rejected up front rather than partway
through a write.

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is
a directory under `~/.clause/profiles/` with its own `.claude/`, `.claude.json`,
`Containerfile`, `args`, and `effort`, all seeded from the repo's `default/` template;
the `default` profile is created automatically on first run. A profile later missing
one of those files errors at launch (re-seed with `clause image build`) rather than
being silently regenerated.

Profile names are lowercased and validated wherever one is typed (`bind`,
`profile create`, `profile delete`) and again when read back from a workspace's
binding file: lowercase letters, digits, `.`, `_`, and `-`, starting with a letter or
digit. Anything else is rejected up front, because the name becomes a directory under
`~/.clause/profiles/` and the `clause-<name>` image and volume tags.

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

### Seeded settings

The seeded `settings.json` ships four defaults:

- Hooks that tint the terminal background while Claude works, via the `set-bg.sh`
  script seeded into the profile's `.claude/hooks/`.
- Two official plugins enabled through `enabledPlugins` (`skill-creator` and
  `claude-md-management`); they auto-install on the profile's first session, so that
  session needs network access.
- `effortLevel: "xhigh"`, which only affects a bare `claude` run in a `-t` terminal,
  since normal launches pass `--effort` explicitly (see [Effort](#effort)).
- `disableRemoteControl: true`, keeping sessions local-only.

Seeding never overwrites an existing file, so profiles created before a default was
added keep their old `settings.json`; add the new keys there by hand (or use
`/plugin` for the plugins) if you want them.

## Per-profile container images

Every profile has its own `Containerfile` and builds to its own image
`clause-<profile>`; there is no shared fallback image.

```bash
# In a workspace bound to 'work', edit ~/.clause/profiles/work/Containerfile, then build
clause image build
```

`image build` (shortcut: `clause -b`) acts on the workspace's bound profile: it seeds
any missing profile files (including the `Containerfile`) from the repo's `default/`,
then builds the image from the profile's `Containerfile`. Rerun it after any
`Containerfile` change.

`clause image suggest` reads the profile's sudo log and prints Containerfile lines for
anything you installed ad hoc during a session (apt, npm global, pip, gem, cargo, snap),
skipping packages already named on an uncommented line of the target `Containerfile`.

## Nested podman

Opt-in, per profile: run podman *inside* the session (build images, run service
containers, use `podman compose`) without giving the session any access to the host
container engine. Inner containers run rootless inside the session's user namespace,
so even a full escape from an inner container only lands in the jailed session user.

```bash
# Enable: writes the bound profile's nested marker and offers to uncomment
# the nested-podman block shipped (disabled) in its Containerfile; then rebuild
clause podman enable
clause image build

# Inside the session, podman just works
podman run --rm docker.io/library/hello-world

# Disable again (offers to comment the block back out)
clause podman disable
```

The block sits between `# clause-nested-begin` / `# clause-nested-end` markers in the
profile's `Containerfile`, shipped with every line disabled by a `#~ ` prefix (the
image builder strips comment lines, so a disabled block costs nothing). Enable and
disable toggle that prefix in place rather than appending and deleting text, so any
edits you make inside the block survive toggling. A `Containerfile` created before the
markers existed gets the current block appended from the repo template on enable.

Nested images also bundle [lazydocker](https://github.com/jesseduffield/lazydocker),
wired to podman: the `lazydocker` shell function (alias `ld`) starts podman's
docker-compatible API socket on demand and points `DOCKER_HOST` at it, and a baked-in
config maps compose actions to `podman-compose`.

When nested podman is enabled, `clause` launches the session with:

- `--device /dev/fuse` and `--device /dev/net/tun` (each skipped with a warning if the
  host lacks it)
- `--security-opt label=disable` (SELinux labeling breaks nested mounts; a no-op on
  non-SELinux hosts)
- a named volume `clause-<profile>-containers` mounted at
  `/home/claude/.local/share/containers`, so inner images persist across the ephemeral
  sessions
- under a Docker host runtime, additionally `seccomp=unconfined` and
  `apparmor=unconfined`, because Docker's default profiles block the syscalls nested
  podman needs. This is a real isolation reduction; a Podman host is recommended for
  nested mode.

### Cleaning up nested storage

The storage volume grows without bound (inner images, stopped inner containers, build
cache, inner volumes). Selective, inside a session: `podman system prune -a` (add
`podman volume prune` for inner volumes). Blunt, from the host: `clause podman reset`
removes the bound profile's whole volume after confirmation; it is recreated empty on
the next launch, and inner *volumes* (which may hold data, for example a dev database)
are deleted with it. `clause profile delete` removes the volume automatically along
with the image.

### Notes and limitations

- Rebuild after enabling (`clause image build`); the block adds roughly 200 MB to the
  image (podman, uidmap, slirp4netns, fuse-overlayfs, podman-compose, lazydocker).
- lazydocker's config and UI state live inside the image, not in a bind mount: the
  podman-compose config is baked in, and any state lazydocker saves resets each session.
- Toggling preserves the block text, so template improvements are never picked up
  automatically. To refresh an outdated block (for example one predating lazydocker),
  delete everything from `# clause-nested-begin` through `# clause-nested-end` in the
  profile's `Containerfile`, rerun `clause podman enable` (re-appends the current
  block), then rebuild.
- Ports published by inner containers bind inside the session's network namespace:
  reachable from within the session, not from the host.
- Resource limits on inner containers (`--memory`, `--cpus`) are unavailable (no cgroup
  delegation).
- The host image cache is not shared; the first pull of an image per profile hits the
  network, after which the profile volume caches it.
- Hosts that restrict unprivileged user namespaces via AppArmor (Ubuntu 23.10+
  hardening) may need a host-side exception if inner podman fails with permission
  errors while creating user namespaces.

## Claude args

The args appended to `claude` at launch come from one of three places, in this
precedence:

1. `-a, --args <string>`: one-shot override for this launch only.
2. `$WORKSPACE/.clause/args`: workspace-local override; a present file wins even if
   empty. Manage with `config set --local args <string>`.
3. `~/.clause/profiles/<profile>/args`: profile default, seeded on profile creation.
   Manage with `config set args <string>`.

The seeded default is `--dangerously-skip-permissions`; effort lives in the sibling
`effort` file and is injected into the args at launch.

```bash
# One-shot override for this launch
clause -a '--effort high'

# Write the bound profile's default
clause config set args '--dangerously-skip-permissions'

# Write a workspace-local override
clause config set --local args '--effort low'

# Delete the workspace override so args fall through to the profile default
clause config reset --local args

# Restore the profile default to the shipped template value
clause config reset args

# Opt out of args entirely (writes an empty file, distinct from reset)
clause config set args ''
```

Config writes target the bound profile by default; `--local` (short `-l`) targets the
workspace override instead, and is required for writes to it. Resetting means "undo my
customization at this tier": `config reset --local args` *deletes* the workspace file
so args fall through to the profile, while `config reset args` *rewrites* the profile
file with the repo template value (profile `args`/`effort` are required launch files,
so the profile tier restores its default rather than leaving a hole). Both are distinct
from `config set args ''`, which *writes* a present-but-empty file meaning "no args", an
explicit opt-out of every layer. Under `-t/--terminal`, bash itself gets no args, but
the resolved args are still exported as `CLAUSE_ARGS` for the in-container alias (see
[Inside the container](#inside-the-container)).

## Effort

Effort (`claude --effort <level>`) is a layered setting, seeded as `max` in every
profile so you never have to embed `--effort` in an args string. It resolves through
the same three layers as args (`-e` one-shot, then workspace `.clause/effort`, then
profile `effort`) and is injected into the effective args at launch, replacing any
`--effort` already present, so the final command always carries exactly one `--effort`.
Valid levels are `low`, `medium`, `high`, `xhigh`, and `max` (the flag accepts `max`
even though `settings.json`'s `effortLevel` does not).

```bash
# One-shot: run this launch at high effort
clause -e high

# The bound profile's default effort
clause config set effort xhigh

# Workspace-local override (this directory; inspect with clause status)
clause config set --local effort high

# Drop the workspace override / restore the profile template default (max)
clause config reset --local effort
clause config reset effort
```

- A one-shot `-a/--args` is a complete args override, so it bypasses the stored effort
  files too; only a one-shot `-e` refines an `-a` line.
- An empty or whitespace effort file means "unset" and falls through to the next layer
  (unlike `args`, where present-but-empty means "no args"); a file holding an
  unrecognized level is ignored with a warning at launch.
- Because effort is injected into the resolved args, an `--effort` embedded in an `args`
  value is always overridden (at minimum by the seeded profile `max`). Set effort with
  `config set [--local] effort <level>`, not inside `args`.

## Mount override

Claude keys its per-project state (`~/.claude/projects/…`, history, todos) by the
container cwd, so moving a folder on the host changes the encoded path and orphans that
history. The mount override pins the container-side path:
`clause config set --local mount <path>` writes the workspace-local file
`$WORKSPACE/.clause/mount` holding a logical absolute host path, which `clause` encodes
to form the mount target and cwd. The key lives only at the workspace tier, so the
`--local` is mandatory: `config set mount <path>` errors rather than guessing the scope.
Only the container-side path is pinned; the bind-mount *source* is always the real
workspace, so the moved files still mount. Because the file lives inside the workspace
it moves with the folder, which is what keeps the pin in effect; pin the current path
*before* moving (or, after a move, pin the old path).

```bash
# Before moving /home/tom/projects/myapp somewhere else, pin its path:
cd /home/tom/projects/myapp
clause config set --local mount "$(pwd -P)"   # writes ./.clause/mount

# ...move the folder anywhere on the host; the file moves with it...
mv /home/tom/projects/myapp /home/tom/work/myapp

# The container cwd (and Claude's history) is unchanged:
cd /home/tom/work/myapp
clause                              # still /workspace/-home-tom-projects-myapp

# Inspect / clear:
clause status                       # shows the effective "mount:" line + source
clause config reset --local mount   # revert to encoding the real path
```

- Pass the canonical path (use `$(pwd -P)` to resolve symlinks): absolute, no trailing
  slash, no `.`/`..`. `config set --local mount` rejects bad values at parse time; a
  hand-edited invalid `.clause/mount` is ignored with a warning at launch, falling back
  to the real path.
- The override changes container *layout*, not `claude` args, so it applies to
  `-t/--terminal` sessions too.

## Status and config list

`clause status` prints the effective configuration for the current directory: the
resolved profile, its workspace binding, the container mount path, the raw `claude`
args, the effective effort, the effort-injected `launch:` line a launch actually passes,
the container runtime, and whether the image is built, resolving each key to the single
value a launch would use and naming its source. It is read-only (it never creates
`~/.clause`) and tolerant of a missing profile or runtime, so it is safe to run before
anything is set up.

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

For the built-in `default` profile, the effective view (`status`) reads an unseeded
profile `args`/`effort` from the repo `default/` template (source `default template`),
matching what a launch would use, since a real launch seeds those files before reading
them. A present-but-empty file is a real value and is not overridden. Named profiles
never fall back: they error at launch on missing files, so their unseeded keys read
`(no args)` / `(unset)`.

`clause config list` is the complementary *stored* view: what each scope actually holds,
with no cross-tier resolution and no template fallback. A key with no file reads
`(unset)`, a present-but-empty file `(empty)`; `mount` appears only under `workspace`
(it has no profile tier).

```
$ clause config list
workspace (/home/tom/app/.clause):
  args:   (unset)
  effort: (unset)
  mount:  (unset)
profile default (/home/tom/.clause/profiles/default):
  args:   --dangerously-skip-permissions
  effort: max
```

## Workspace binding

`clause` records which profile a workspace uses in a single file inside the workspace,
`<workspace>/.clause/profile`, written by `clause bind <profile>` (shortcut:
`clause -p <profile>`). Because the binding lives in the folder it travels with the
folder, and there is no central registry to keep in sync. An unbound workspace uses
`default`; the first launch from one offers to save that binding (`y` save, `n` continue
without saving, `q` exit). If a binding already exists, `bind` prompts before rebinding.

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

Because bindings are local files they are not enumerable from one place: `profile list`
shows the installed profiles and `status` shows the current workspace's binding, but
there is no global workspace-to-profile list. For the same reason `profile delete`
cannot unbind other workspaces; a workspace still pointing at a deleted profile errors
on its next launch until you rebind it.

When `clause` first creates a workspace's `.clause/` directory it drops a `.gitignore`
containing a single `*`, so the enclosing repo ignores the clause state automatically;
the file is created only when absent, so a hand-edited `.gitignore` is never
overwritten.

## Container runtime

`clause` prefers Podman and supports Docker. `~/.clause/runtime` pins the choice and is
managed with `clause runtime <podman|docker>` / `clause runtime --unset`; with no pin it
auto-detects podman, then docker. A pinned runtime that is not on `PATH` is a hard
error. `clause status` probes the runtime report-only, so it still works on a host with
no container engine installed.

## Shell alias

```bash
clause alias create
```

This checks for `~/.bashrc` and `~/.zshrc` and prompts to append a `clause` alias to
each file found, skipping files that already have it; `clause alias delete` removes it.
Only aliases created by `alias create` are detected (they carry a `# clause-alias`
marker); a hand-written `alias clause=...` is invisible to both commands and may end up
duplicated.

### Inside the container

The container image bakes its own `clause` alias into the container user's `~/.bashrc`.
The alias expands the `CLAUSE_ARGS` environment variable, which every launch sets to the
effort-injected args the wrapper resolved for that workspace: the same line
`clause status` shows as `launch:`. Running `clause` from any shell inside a session (for
example one started with `-t/--terminal`) therefore starts claude exactly as a normal
launch would; with the shipped defaults that is
`claude --dangerously-skip-permissions --effort max`. Extra flags pass through
(`clause -c` appends `-c`), and if `CLAUSE_ARGS` is empty or unset the alias runs bare
`claude`.

The base image also bundles [lazygit](https://github.com/jesseduffield/lazygit) with an
`lg` alias and [superfile](https://github.com/yorukot/superfile) (binary `spf`) with an
`sf` alias (both fetched from the latest GitHub release at build time; x86_64/amd64 and
arm64). These lines are baked in at build time, so rebuild to pick up changes; profiles
whose `Containerfile` predates them need a manual edit first (or delete the profile's
`Containerfile` and rerun `clause image build` to re-seed it).

## Persistence

Each profile's data is stored under `~/.clause/profiles/<name>/` and bind-mounted into
the container:

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

`~/.clause/` is created automatically on first run, each profile seeded from the repo's
`default/` template (the sole source of a profile's initial files; nothing is generated
in code).
