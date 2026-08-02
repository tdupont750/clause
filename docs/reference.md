# Reference

Full behavior of `clause`: every command, flag, config key, and precedence rule.
The [README](../README.md) covers installation and the high-level concepts; this
file is the detail behind them.

## Command grammar

`clause` runs one command per invocation: with no command it launches the profile
bound to the current workspace (`default` until you bind one), and naming two
commands is a parse-time error. Session options go before the command. Two
commands have flag-spelled shortcuts: `-b` runs `image build`, and `-p <profile>`
is an alias for `bind <profile>` (including `-p --unset`).

A profile name is only ever typed to `bind <profile>` and `profile create <name>` /
`profile reset <name>` / `profile delete <name>`, where it is required; every other
command (launch, `image`, and `podman` included) acts on the workspace's bound
profile, so profiles named like command words never collide with them. A leading bare
word is an unknown-command error.

Input is validated at parse time, before any side effects: effort levels, model
names, mount paths, config keys, and profile names are all rejected up front rather
than partway through a write.

Every prompt is the same `[y/n/q]` question, destructive ones included, and `-y`/`-n`
answer all of them — so `clause -y profile delete work` deletes without asking, and no
command blocks on input in a script. The reset commands ask once per file or key
rather than once for the batch, so `n` skips just that one and `q` stops the rest.

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is
a directory under `~/.clause/profiles/` with its own `.claude/`, `.claude.json`,
`Containerfile`, `args`, `effort`, and `model`, all seeded from the repo's `default/` template;
the `default` profile is created automatically on first run. Profile files are never
left missing: a launch seeds whatever is absent from `default/` before using the
profile (existing files are never overwritten), so a profile created before a new
template file was added simply gains it on the next run.

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

# Restore clause's shipped configuration for a profile
clause profile reset work

# Delete a profile (also removes its image and nested storage volume)
clause profile delete work
```

### Resetting a profile

`clause profile reset <name>` puts clause's own configuration files back the way they
ship, discarding local edits to them. It rewrites:

| File | Back to |
|------|---------|
| `args` | `--dangerously-skip-permissions` |
| `effort` | `max` |
| `model` | empty (unset) |
| `Containerfile` | the shipped image definition, nested-podman block commented out |
| `.claude/settings.json` | the seeded defaults below |
| `.claude/CLAUDE.md` | the shipped in-container instructions |
| `.claude/hooks/set-bg.sh` | the shipped hook |
| `.claude/output-styles/laconic.md` | the shipped `Laconic` output style |

It deliberately does **not** touch the three template files that hold live state in a
real profile — `.claude.json` (Claude's own state: logins, project history, MCP
config), `.gitconfig` (the profile's git identity), and `.claude/clause-sudo.log` (what
`image suggest` parses) — nor anything else that accumulates under `.claude/`
(credentials, history, projects, plugins). A reset therefore never logs the profile out
or forgets who it commits as; use `profile delete` for a clean slate.

The command asks about each file in turn — `y` restores it, `n` leaves it as it is, `q`
stops without touching the rest — so nothing is overwritten before you have seen its
name. `-y` and `-n` answer every prompt. Afterwards, rebuild to pick up the restored
`Containerfile` — and if nested podman was enabled, re-run `clause podman enable`,
since the restored `Containerfile` ships that block commented out while the profile's
`nested` marker survives the reset:

```bash
clause profile reset work
clause image build
```

### Seeded settings

The seeded `settings.json` ships five defaults:

- Hooks that tint the terminal background while Claude works, via the `set-bg.sh`
  script seeded into the profile's `.claude/hooks/`.
- Two official plugins enabled through `enabledPlugins` (`skill-creator` and
  `claude-md-management`); they auto-install on the profile's first session, so that
  session needs network access.
- `effortLevel: "xhigh"`, which only affects a bare `claude` run in a `-t` terminal,
  since normal launches pass `--effort` explicitly (see [Effort](#effort)).
- `disableRemoteControl: true`, keeping sessions local-only.
- `outputStyle: "Laconic"`, selecting the output style seeded into the profile's
  `.claude/output-styles/laconic.md` (terse, high-signal responses). Switch it per
  session with `/output-style` inside the container, or drop the key to get Claude's
  default style.

Seeding never overwrites an existing file, so profiles created before a default was
added keep their old `settings.json`; add the new keys there by hand (or use
`/plugin` for the plugins) if you want them. Files that are entirely new to the
template are a different case: seeding adds anything missing, so an older profile
gains `.claude/output-styles/laconic.md` on its next launch, but the `outputStyle` key
that selects it only arrives via a hand edit or `clause profile reset <name>`.

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
2. `$WORKSPACE/.clause/args`: workspace-local override. Manage with
   `config set --local args <string>`.
3. `~/.clause/profiles/<profile>/args`: profile default, seeded on profile creation.
   Manage with `config set args <string>`.

Presence decides the tier, here and for every other knob: **a file that exists wins
even when it is empty**, and only an *absent* file falls through to the next tier. An
empty file is that tier saying "no value" — for `args` that means no args at all, for
`effort` and `model` it means the flag is not passed. A workspace has no config files
until you write one, so by default it passes straight through to the profile.

The seeded default is `--dangerously-skip-permissions`; effort and model live in the
sibling `effort` and `model` files and are injected into the args at launch.

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

# Walk every key at one scope, asking y/n/q per key (-y answers them all)
clause config reset --local
clause config reset

# Opt out of args entirely (writes an empty file, distinct from reset)
clause config set args ''
```

Config writes target the bound profile by default; `--local` (short `-l`) targets the
workspace override instead, and is required for writes to it. Resetting means "undo my
customization at this tier": `config reset --local args` *deletes* the workspace file
so the workspace passes through to the profile again, while `config reset args`
*re-seeds* the profile file from the repo template (the profile tier restores its
default rather than leaving a hole). The key is optional on `reset` alone: a bare
`clause config reset` walks every key at that scope — `args`, `effort` and `model` at
the profile tier, plus `mount` at the workspace tier, which is the only tier that has
it — asking about each one in turn (`y` resets it, `n` skips it, `q` stops the rest).
Naming a key resets it straight away, without a prompt; `-y` and `-n` answer every
prompt in the walk. Both are distinct from `config set args ''`, which
*writes* a present-but-empty file meaning "no args" — an explicit opt-out that, like any
present file, wins over the tiers below it. An empty value is accepted for every key at
either scope and skips validation; only a non-empty value is shape-checked. Under
`-t/--terminal`, bash itself gets no args, but
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

# Run this one workspace (or this one launch) with no --effort at all
clause config set --local effort ''
clause -e ''
```

- A one-shot `-a/--args` is a complete args override, so it bypasses the stored effort
  files too; only a one-shot `-e` refines an `-a` line.
- A present-but-empty effort file means "no effort" — that tier wins and no `--effort`
  is passed — while an absent file falls through to the next layer. A file holding an
  unrecognized level is ignored with a warning at launch and falls through.
- Because effort is injected into the resolved args, an `--effort` embedded in an `args`
  value is always overridden (at minimum by the seeded profile `max`). Set effort with
  `config set [--local] effort <level>`, not inside `args`.

## Model

Model (`claude --model <name>`) is a layered setting shaped exactly like effort: it
resolves through `-m` one-shot, then workspace `.clause/model`, then profile `model`, and
is injected into the effective args at launch, replacing any `--model` already present so
the final command carries exactly one. Unlike effort, the shipped template is **empty**,
meaning "unset": out of the box no `--model` is passed and `claude` picks its own model,
so a workspace only ever launches with a model it was explicitly given.

Values are validated by shape rather than against a fixed list, so aliases (`opus`,
`sonnet`, `haiku`, `opusplan`), full ids (`claude-opus-5`, `claude-sonnet-4-5-20250929`),
bracketed context variants (`sonnet[1m]`), and provider-qualified ids
(`anthropic.claude-opus-5`, `claude-opus-4-5@20251101`) are all accepted. A value must be
a single token: no whitespace, no shell metacharacters, and no leading `-`.

```bash
# One-shot: run this launch on a different model
clause -m opus

# The bound profile's default model
clause config set model claude-opus-5

# Workspace-local override (this directory; inspect with clause status)
clause config set --local model sonnet

# Drop the workspace override / restore the profile template default (unset)
clause config reset --local model
clause config reset model
```

- A one-shot `-a/--args` is a complete args override, so it bypasses the stored model
  files too; only a one-shot `-m` refines an `-a` line.
- A present-but-empty `model` file means "no model" — that tier wins and no `--model` is
  passed — while an absent file falls through. `config set --local model ''` is how you
  pin one workspace back to claude's own default when the profile sets a model, and
  `clause -m ''` does the same for a single launch; a file holding a malformed name is
  ignored with a warning at launch and falls through.
- Because model is injected into the resolved args, a `--model` embedded in an `args`
  value is overridden whenever any tier sets a model. Set the model with
  `config set [--local] model <name>`, not inside `args`.
- Effort is injected before model, so a launch line reads
  `--dangerously-skip-permissions --effort max --model opus`.

## Mount override

Claude keys its per-project state (`~/.claude/projects/…`, history, todos) by the
container cwd, so moving a folder on the host changes the encoded path and orphans that
history. The mount override pins the container-side path:
`clause config set --local mount <path>` writes the workspace-local file
`$WORKSPACE/.clause/mount` holding **the container path itself**, used verbatim as the
mount target and cwd. It is the same string `clause status mount` prints, so
`clause config set --local mount "$(clause status mount)"` means "pin whatever I have
now" and repeating it changes nothing. The key lives only at the workspace tier, so the
`--local` is mandatory: `config set mount <path>` errors rather than guessing the scope.
Only the container-side path is pinned; the bind-mount *source* is always the real
workspace, so the moved files still mount. Because the file lives inside the workspace
it moves with the folder, which is what keeps the pin in effect; pin the current path
*before* moving (or, after a move, pin the old path).

```bash
# Before moving /home/tom/projects/myapp somewhere else, pin where it lands:
cd /home/tom/projects/myapp
clause config set --local mount "$(clause status mount)"   # writes ./.clause/mount

# ...move the folder anywhere on the host; the file moves with it...
mv /home/tom/projects/myapp /home/tom/work/myapp

# The container cwd (and Claude's history) is unchanged:
cd /home/tom/work/myapp
clause                              # still /workspace/-home-tom-projects-myapp

# Inspect / clear:
clause status                       # shows the effective "mount:" line + source
clause config reset --local mount   # revert to encoding the real path
```

Since the value is a container path and not a host path, you can also pick a readable
one instead of the encoded default, which is the cwd you see in the container prompt:

```bash
clause config set --local mount /workspace/myapp
```

- Values are validated on write *and* on read, because the string reaches the container
  runtime's argv unchanged: it must start with `/workspace/` and name a subpath of it,
  with no trailing slash, no `.` or `..` components, and no `:` (which would split the
  mount spec). `config set --local mount` rejects bad values at parse time. A
  hand-edited or outdated `.clause/mount` that fails the same check is reported as a
  warning by `status`, which falls back to the encoded real workspace, and is a hard
  error at launch, which refuses rather than silently re-keying Claude's history.
- Pinning is yours to keep unique. The default encoding guarantees that two host
  workspaces get two container paths; a hand-picked value does not, so two projects both
  pinned to `/workspace/myapp` share one history and todo list within a profile. That is
  occasionally what you want (it is how a moved folder keeps its history) but it is never
  automatic.
- If you have already moved the folder and never pinned it, nothing reports the old
  path any more. Reconstruct it with the same encoding `clause` uses (`/` and `.` both
  become `-`):
  ```bash
  clause config set --local mount "/workspace/$(printf %s /home/tom/projects/myapp | tr './' '--')"
  ```
  or read it off the profile: `ls ~/.clause/profiles/<name>/.claude/projects/`.
- `mount` is the one knob where an empty file is not a value: there is no such thing as
  an empty container path, so an empty `.clause/mount` is ignored and the real workspace
  path is encoded, exactly as if the file were absent.
- The override changes container *layout*, not `claude` args, so it applies to
  `-t/--terminal` sessions too.

## Status, config list, and config help

`clause status` prints the effective configuration for the current directory, resolving
each key to the single value a launch would use and naming its source, in three groups:
the workspace heading with the resolved profile and the container mount
path; the config table with the raw `claude` args, the effective effort and model, and the
injected `launch:` line a launch actually passes; and the environment, with the container
runtime and whether the image is built. It is read-only (it never creates `~/.clause`) and
tolerant of a missing profile or runtime, so it is safe to run before anything is set up.

```
$ clause status
workspace (/home/tom/app):
  profile: work
  mount:   /workspace/-home-tom-app

config:    source     value
  args:    profile    --dangerously-skip-permissions
  effort:  profile    max
  model:   workspace  opus
  launch:             --dangerously-skip-permissions --effort max --model opus

environment:
  runtime: podman
  image:   clause-work (built)
```

The workspace binding is not a row of its own. The resolved profile *is* the binding
whenever there is one (`clause` falls back to `default` only when there is not), so the
`profile:` row carries the one thing a separate binding row would have added, as a note in
parentheses:

```
  profile: work                       # bound to work
  profile: default                    # bound to default, deliberately
  profile: default (unbound)          # no binding, so the fallback
  profile: work (not created)         # bound, but the profile dir does not exist yet
  profile: default (unbound, not created)   # a first run, before anything is seeded
```

An annotated `default` therefore means nobody chose it, and a bare one means somebody did.
Notes combine, since a first run on a fresh machine is both unbound and uncreated (`status`
never seeds).

The `source` column comes first and names the *tier* a value came from (`workspace`,
`profile`, `default template`, or the one-shot flag, such as `-e/--effort`) rather than the
backing file's path, which is that tier's directory plus the key name: `config list` prints
both scopes' directories in its headings if you need the exact file to edit. `mount`
carries its tier inline, in parentheses, and only when overridden. Source-first is what
lets the values line up in one column no matter how long they get: only the sources are
measured (floored at the width of the `source` header), and a long args or `launch:` line
simply runs off to the right. `launch:` has no source of its own, so its cell is blank; and
when no key has a source anywhere, the column disappears and the rows print as plain
`label: value` lines.

A key whose winning tier holds an empty value reads `(none)` with that tier as its
source — an explicit "pass no flag" — as against `(unset)`, which means no tier set it
at all. For the built-in `default` profile, the effective view (`status`) reads an
unseeded profile `args`/`effort`/`model` from the repo `default/` template (source
`default template`), matching what a launch would use, since a real launch seeds those
files before reading them. Named profiles never fall back that way, so a key `status`
sees before the profile's first launch reads `(no args)` / `(unset)`.

### `clause status <key>`

The raw single-row read: it prints just that row's value, one line, verbatim, and nothing
else, so it drops straight into a script. The key is any row the table prints, plus
`binding`, which the table folds into the profile row's note; the table's framing is all
gone: no label, no source, and none of the parenthesised stand-ins.

| key | example output | empty when |
|---|---|---|
| `profile` | `work` | never (falls back to `default`) |
| `binding` | `work` | the workspace has no binding (no table row of its own) |
| `mount` | `/workspace/-home-tom-app` | never (falls back to the encoded real workspace) |
| `args` | `--dangerously-skip-permissions` | no tier sets args, or a tier sets it empty |
| `effort` | `max` | no tier sets it, or a tier sets it empty |
| `model` | `opus` | no tier sets it (the shipped default), or a tier sets it empty |
| `launch` | `--dangerously-skip-permissions --effort max` | args empty with nothing to inject |
| `runtime` | `podman` | no podman or docker on PATH |
| `image` | `clause-work` | never |

```
$ eff=$(clause status effort); echo "[$eff]"
[max]

$ [[ -n "$(clause status model)" ]] && echo pinned || echo "no model"
no model

$ podman run --rm -it "$(clause status image)" bash

$ clause config set --local mount "$(clause status mount)"   # pin the current cwd
```

`mount` is the one row whose value is also a `config` value: `status` prints exactly what
`config set --local mount` accepts, so the line above is idempotent.

Consequences of "raw" worth knowing: a tier explicitly passing no flag and nothing set
anywhere are both a single empty line, so the `(none)` / `(unset)` distinction above is
visible only in the table; `profile` never reports that it is unbound or uncreated and
`image` never reports whether it is built, since those notes are meta; and `binding` is
empty for an unbound workspace, where `profile` still resolves to `default`, which makes
`[[ -n "$(clause status binding)" ]]` the way to ask whether this workspace is bound. Exit status is 0 for any
valid key, empty value included, and 1 only for a usage error (an unknown key, or more than
one), so "is it set" is a string test, not an exit-code test. Session one-shots apply
(`clause -e xhigh status effort` prints `xhigh`), and resolver warnings still go to stderr,
so stdout stays clean under `$(...)`. Only `status runtime` probes for a container runtime;
the other keys resolve nothing they do not need.

### `clause config list`

`clause config list` is the complementary *stored* view: what each scope actually holds,
with no cross-tier resolution and no template fallback. A key with no file reads
`(unset)`, a present-but-empty file `(empty)`; `mount` appears only under `workspace`
(it has no profile tier).

```
$ clause config list
workspace (/home/tom/app/.clause):
  args:   (unset)
  effort: (unset)
  model:  (unset)
  mount:  (unset)
profile default (/home/tom/.clause/profiles/default):
  args:   --dangerously-skip-permissions
  effort: max
  model:  (empty)
```

### `clause config help`

`clause config help` is the reference view: neither stored nor effective values, but what
each key *means* — the verbs, every key with the values it accepts and the value the
repo template ships, and the resolution order. It reads the shipped values out of
`default/` as it prints, so it cannot drift from what a profile is actually seeded with.
`clause config -h`, and `-h` after any config verb, print the same thing.

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
effort- and model-injected args the wrapper resolved for that workspace: the same line
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
| Credentials, history, plugins, cache, hooks, output styles | `~/.clause/profiles/<name>/.claude/` | `/home/claude/.claude/` |
| Settings, first-run state | `~/.clause/profiles/<name>/.claude.json` | `/home/claude/.claude.json` |
| Git configuration | `~/.clause/profiles/<name>/.gitconfig` | `/home/claude/.gitconfig` |
| Containerfile (per profile) | `~/.clause/profiles/<name>/Containerfile` | not mounted (build input) |
| Profile args, effort and model | `~/.clause/profiles/<name>/args`, `effort`, `model` | not mounted (read by `clause` on launch) |
| Workspace config (binding, args, effort, model, mount) | `<workspace>/.clause/` | not mounted (read by `clause` on launch) |
| sudo activity log | `~/.clause/profiles/<name>/.claude/clause-sudo.log` | `/home/claude/.claude/clause-sudo.log` |
| Nested podman storage (inner images, containers) | named volume `clause-<name>-containers` | `/home/claude/.local/share/containers` |
| Workspace | `$PWD` (or `-w path`) | `/workspace/<encoded-host-path>` by default, or the container path `.clause/mount` names |

`~/.clause/` is created automatically on first run, each profile seeded from the repo's
`default/` template (the sole source of a profile's initial files; nothing is generated
in code).
