# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Documentation

When changing any flag, option, or behavior in `clause`, always update both `CLAUDE.md` and `README.md` to reflect the change. The usage block in `README.md` should stay in sync with `./clause -h`.

This file describes current behavior only. The full historical design log, including superseded decisions and their rationale, lives in `docs/decisions.md`; when a change supersedes something here, update the bullet in place and record the history there.

## Project Structure

- `clause`: wrapper script that starts an ephemeral container session
- `default/`: profile template mirroring a real profile under `~/.clause/profiles/<name>/`; seeded into profiles on first use (every `default/<rel>` maps to `<profile>/<rel>`)
  - `default/Containerfile`: image definition (Ubuntu 24.04, Node.js 22, claude CLI, lazygit)
  - `default/args`: default `claude` args (`--dangerously-skip-permissions`)
  - `default/effort`: default effort level (`max`), injected into the args at launch
  - `default/.claude/settings.json`: default Claude settings
  - `default/.claude/CLAUDE.md`: default Claude instructions
  - `default/.claude/hooks/set-bg.sh`: terminal background-color hook (invoked by the seeded `settings.json` hooks)
  - `default/.claude.json`: empty Claude state `{}`
  - `default/.gitconfig`: empty git config
  - `default/.claude/clause-sudo.log`: empty sudo activity log (force-added past the repo's `.claude/` gitignore)
- `~/.clause/`: runtime state directory (auto-created on first run); `~/.clause/runtime` pins the container runtime
- `~/.clause/profiles/`: named profile directories, each with `.claude/`, `.claude.json`, `.gitconfig`, `Containerfile`, `args`, and `effort`
- `~/.clause/profiles/default/`: built-in default profile (auto-created on first run)
- `<workspace>/.clause/`: per-workspace config dir holding the `profile` binding and optional `args`/`effort`/`mount` overrides; lives inside each workspace, so it travels with the folder
- `docs/decisions.md`: historical design-decision log

## Building

```bash
./clause image build
```

## Running

```bash
./clause [-w workspace] [-y] [-n] [-t] [-a <string>] [-e <level>]
./clause config set [--local] <key> <value> # keys: args, effort, mount (mount needs --local)
./clause config get <key>
./clause config reset [--local] <key>
./clause config list                         # workspace + profile config, per scope
./clause profile create [name] | delete [name] | list
./clause image build | suggest               # acts on the bound profile; -b = image build
./clause bind [profile] | --unset             # -p is an alias for bind
./clause podman enable | disable | reset      # acts on the bound profile
./clause alias create | delete
./clause runtime <podman|docker> | --unset
./clause status
```

See `README.md` for full flag documentation.

## Current Behavior

### Runtime and containers

- Podman preferred, Docker supported: `detect_runtime` honors `~/.clause/runtime` first (must be `podman` or `docker` and on PATH, hard errors otherwise), else auto-detects podman then docker. `probe_runtime` is the shared soft probe (`status` uses it report-only, so it works with no runtime installed). Managed with `runtime <podman|docker>` / `runtime --unset`.
- Sessions are ephemeral `--rm` containers, interactive via `podman run -it` (or docker); all state lives in bind mounts. No SSH.
- The container user is `claude` (UID 1000). Podman maps the host user with `--userns=keep-id:uid=1000,gid=1000`; docker uses `--user $(id -u):$(id -g)`. Passwordless sudo is available in-container and logged to the profile's `.claude/clause-sudo.log`.
- The image is always `clause-<profile>`, built by `clause image build` from the profile's own `Containerfile` (seeding missing profile files first). Launch errors if the image is missing; there is no shared fallback image.
- The workspace is bind-mounted at `/workspace/<encoded-host-path>` and the container cwd is set there (`encode_path`: `/` and `.` become `-`, the same scheme Claude uses for `~/.claude/projects` keys), keeping per-project state separate when workspaces share a profile.

### Profiles and seeding

- `default/` is the single source of a profile's initial state. `seed_profile` copies missing files only (never overwrites), walking `default_files` (a find over `default/`, dotpaths included); no file contents are generated in code.
- Bootstrap is lazy: `bootstrap_state` idempotently seeds `~/.clause/profiles/default/` before any non-read-only command. The read-only commands (`status`, `profile list`, `config` get/list, `-h`) never touch disk.
- Named profiles are created only by `profile create` (full seed, then binds the workspace, prompting before rebinding to a different profile). Launch never re-seeds: `require_profile_files` errors listing any missing files (fix with `clause image build`).
- `profile delete` refuses `default`, requires a typed `yes`, and removes the profile dir, the `clause-<profile>` image, and the `clause-<profile>-containers` volume. Bindings are local files, so it cannot unbind other workspaces; a stale binding hard-errors on that workspace's next launch.
- Profile names are validated by `validate_profile_name` (`^[a-z0-9][a-z0-9._-]*$`, after lowercasing): at parse time in `bind` / `profile create` / `profile delete`, and again in `require_profile` so a hand-edited binding cannot feed a traversal name into `rm -rf` or the image/volume tags. Read-only views stay tolerant of an invalid bound name.

### Workspace config and layering

- Per-workspace state lives in `<workspace>/.clause/` (the `profile` binding plus optional `args`, `effort`, `mount` overrides) and travels with the folder; there is no central registry. `ensure_workspace_config_dir` creates the dir with a `.gitignore` of `*` so the enclosing project ignores it automatically (created only when absent, never overwritten).
- Binding: `bind [profile]` writes `<workspace>/.clause/profile` (prompting if already bound); `bind --unset` removes it. Launch uses the bound profile, else `default` (first run from an unbound workspace offers to save the binding, y/n/q). `bind` is the only session-side way to name a profile; launch, `image`, `podman`, `status`, and `config` all act on the bound profile.
- Args resolve via `resolve_args` (raw mode: first line verbatim, a present file wins even if empty): `-a` one-shot, then workspace `.clause/args`, then profile `args`, then (default profile only, when the profile file is absent) the repo `default/args` template. `config reset --local args` deletes the workspace file so args fall through; `config reset args` rewrites the profile file with the template value (never deletes: profile `args`/`effort` are launch-required files); `config set args ''` writes a present-but-empty profile file meaning no args (`config set --local args ''` for the workspace tier).
- Effort resolves via `resolve_effort` (token mode: whitespace-stripped, empty means unset and falls through, invalid file values warn and are skipped): `-e`, then workspace `.clause/effort`, then profile `effort`, then the default template. `apply_effort_to_args` injects exactly one `--effort` into the final args, replacing any `--effort` written inside an args value. Valid levels: `low|medium|high|xhigh|max` (`max` is valid for the CLI flag though not for settings.json `effortLevel`). A one-shot `-a` is a complete args override and bypasses stored effort files; only `-e` refines `-a`. Under `-t` the resolved args are not passed to the container command (bash), but they are still resolved and exported as `CLAUSE_ARGS` so the in-container `clause` alias mirrors them.
- Mount: `<workspace>/.clause/mount` pins the logical path encoded into the container-side workspace path (bind target + cwd) so Claude's path-keyed history survives moving the host folder; the bind-mount source stays the real workspace. Workspace-only (no profile tier; writing `mount` without `--local` is a parse error pointing at `config set --local mount`). Values must be absolute with no trailing slash (`validate_mount_path`); an invalid file value warns and falls through. Applies in both claude and `-t` modes.
- The `config` subcommand manages the three knobs through required verbs: `config <set|get|reset|list> [-l|--local] <key> [<value>]`, parsed by `parse_config_args` (not `parse_subcommand`: the key/value positionals need their own grammar; missing/unknown verbs reuse `subcommand_error`). Writes target the workspace's bound profile by default; `-l/--local` targets the workspace override tier and is required for it (and therefore for every `mount` write). `set` requires an explicit value (`config set args ''` writes empty). `reset` undoes one tier's customization: profile scope restores the repo template value, `--local` scope deletes the override file. Reads are cross-scope and reject `--local`: `config get` prints one raw effective value (no effort injection); `config list` dumps stored values per scope with no cross-tier resolution and no template fallback (`(unset)` / `(empty)`); the effective-value-and-source view is `status`'s job. Non-set verbs reject a trailing value at parse time.
- `status` is the full dashboard: profile, binding, mount, raw args, effort (each with its source), the effort-injected `launch:` line, runtime (soft probe), and image built state. For the `default` profile, `status` and `config get` read absent profile `args`/`effort` from the repo `default/` template via `profile_tier_file` (source shown as `default template`), matching what a launch would seed after bootstrap; named profiles never fall back.

### Command surface and parsing

- One command per invocation: `set_command` claims the single `COMMAND` (default `launch`); a second command flag is a parse-time error naming both. Session modifiers (`-t -w -a -e -y -n`) combine with any command and must precede it.
- Noun-verb subcommands (`config set|get|reset|list`, `profile create|delete|list`, `image build|suggest`, `podman enable|disable|reset`, `alias create|delete`, `status`) plus the inline-parsed top-level words `bind [profile]` / `bind --unset` and `runtime <podman|docker>` / `runtime --unset`. Reserved words: `config profile image podman alias runtime status bind`. `parse_subcommand` maps `<noun> <verb>` onto the internal `COMMAND` values the `main` dispatch uses. Two flag-spelled command shortcuts (not session modifiers, they claim `COMMAND` via `set_command`): `-p` is a case-arm alias for `bind` (same optional profile and `--unset` handling, labels and errors name the token typed), and `-b` maps to the internal `build` command like `image build`.
- Only `profile create`/`delete` take a trailing profile name; every other subcommand acts on the bound profile and rejects one with an error pointing at `bind`. A leading bare word is an unknown-command error: launch takes no profile argument, so profiles may be named like command words without collision.
- Input is validated at parse time before any side effects: `validate_effort`, `validate_mount_path`, `validate_config_key`, `validate_profile_name`.
- Prompts: `prompt_ynq`/`prompt_yes` honor `-y`/`-n`; destructive actions go through `confirm_yes` (typed `yes`; `-y` deliberately does not auto-confirm these, `-n` declines).
- `image suggest` parses the profile's sudo log (rejoining sudo's wrapped continuation lines), collects apt/npm-global/pip/gem/cargo/snap installs, and drops candidates whose exact package name already appears as a token in the target Containerfile (exact match, not substring).
- Help groups the workspace/profile-scoped commands under `commands (then exit):` and the machine-wide `runtime` / `alias` under `global (machine-wide setup):`. `README.md`'s usage block mirrors `./clause -h` byte for byte.

### Defaults shipped in `default/`

- `settings.json`: `permissions.defaultMode = "bypassPermissions"`; `enabledPlugins` enables `skill-creator` and `claude-md-management` (official marketplace, auto-installs on the profile's first networked session); `effortLevel = "xhigh"` (governs only bare `claude` runs in `-t` sessions, since normal launches pass `--effort`); `disableRemoteControl = true` (keeps sessions local-only). Seeding never overwrites, so profiles created earlier keep their existing settings.
- `effort` = `max` and `args` = `--dangerously-skip-permissions`, so a normal launch runs `claude --dangerously-skip-permissions --effort max`.
- `Containerfile` bakes a `clause` alias and lazygit with an `lg` alias into the container `.bashrc`. The `clause` alias expands `$CLAUSE_ARGS`, which every launch sets to the effort-injected resolved args (the same line `status` renders as `launch:`), so `-t` sessions mirror the workspace's real launch command; empty or unset means bare `claude`. Baked at build time: profiles with an older `Containerfile` pick changes up only after a manual edit (or deleting the profile `Containerfile` so `image build` re-seeds it) plus a rebuild.

### Nested podman

- Opt-in per profile: `podman enable` creates the profile's `nested` marker and offers to append the managed Containerfile block (between `# clause-nested-begin` / `# clause-nested-end`; the heredoc lives in the script, not `default/`, so non-nested images stay lean); `podman disable` reverses both. Rebuild required after enabling.
- With the marker, launch adds `--device /dev/fuse --device /dev/net/tun --security-opt label=disable` plus the storage volume; docker additionally gets seccomp/apparmor `unconfined` (its defaults block unshare/mount). Missing devices are skipped with a warning; launch warns (non-fatally) if the Containerfile does not appear to install podman.
- Inner storage lives in the named volume `clause-<profile>-containers` at `/home/claude/.local/share/containers` (persists inner images across sessions, allows native overlayfs, keeps nested-subuid-owned files out of the profile dir). Removed by `profile delete` and by `podman reset` (typed confirmation).
- The nested block also installs lazydocker (with a wrapper function, alias `ld`, that starts `podman system service` on demand and points `DOCKER_HOST` at its socket) and a config mapping compose actions to `podman-compose`.

### Script conventions

- `set -euo pipefail`. A function whose last statement could be a false test must end with an explicit `return 0` (a trailing `[[ ... ]] && ...` would return nonzero and trip `set -e` in callers). Use `i=$((i+1))`, never `((i++))` (which returns 1 at 0).
- Cross-function globals are declared in the commented block at the top of the script; command bodies use lowercase `local` variables. `CONTAINER_NAME` stays global because `cmd_launch` returns instead of exiting, so its EXIT trap fires after the function frame is gone.
- Read-only allowlists: `bootstrap_state` skips seeding for `status|profile-list` and `config` get/list; `detect_runtime` only runs for `build|delete-profile|podman-reset|launch` (everything else must work on a runtime-less host).
- The script's only top-level statement is `main "$@"` on the last line. Keep it a bare call: wrapping it in a conditional would disable `set -e` inside `main`, and having it last means the whole file is parsed before any logic runs (safe to edit while a session is live).
