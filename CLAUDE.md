# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Documentation

When changing any flag, option, or behavior in `clause`, always update both `CLAUDE.md` and `docs/reference.md` to reflect the change. `docs/reference.md` is the user-facing detail doc: every command, flag, config key, and precedence rule lives there.

`README.md` is deliberately short: install steps, the usage block, and high-level concepts only. Touch it when a change alters the usage output (the block must stay in sync with `./clause -h`, byte for byte) or when it changes a concept the README describes; routine flag and behavior detail belongs in `docs/reference.md`, which the README links at the bottom.

This file describes current behavior only. The full historical design log, including superseded decisions and their rationale, lives in `docs/decisions.md`, which is untracked and local-only (gitignored, not part of the published repo); when a change supersedes something here, update the bullet in place and record the history there if the file is present.

## Project Structure

- `clause`: wrapper script that starts an ephemeral container session
- `default/`: profile template mirroring a real profile under `~/.clause/profiles/<name>/`; seeded into profiles on first use (every `default/<rel>` maps to `<profile>/<rel>`)
  - `default/Containerfile`: image definition (Ubuntu 24.04, Node.js 22, claude CLI, lazygit, superfile), plus the nested podman block shipped commented out
  - `default/args`: default `claude` args (`--dangerously-skip-permissions`)
  - `default/effort`: default effort level (`max`), injected into the args at launch
  - `default/model`: default model (empty = unset, so no `--model` is injected)
  - `default/.claude/settings.json`: default Claude settings
  - `default/.claude/CLAUDE.md`: default Claude instructions
  - `default/.claude/hooks/set-bg.sh`: terminal background-color hook (invoked by the seeded `settings.json` hooks)
  - `default/.claude.json`: empty Claude state `{}`
  - `default/.gitconfig`: empty git config
  - `default/.claude/clause-sudo.log`: empty sudo activity log (force-added past the repo's `.claude/` gitignore)
- `~/.clause/`: runtime state directory (auto-created on first run); `~/.clause/runtime` pins the container runtime
- `~/.clause/profiles/`: named profile directories, each with `.claude/`, `.claude.json`, `.gitconfig`, `Containerfile`, `args`, `effort`, and `model`
- `~/.clause/profiles/default/`: built-in default profile (auto-created on first run)
- `<workspace>/.clause/`: per-workspace config dir holding the `profile` binding and optional `args`/`effort`/`model`/`mount` overrides; lives inside each workspace, so it travels with the folder
- `docs/reference.md`: user-facing reference (all commands, flags, config keys, precedence)
- `docs/decisions.md`: historical design-decision log (untracked, local-only)

## Building

```bash
./clause image build
```

## Running

```bash
./clause [-w <path>] [-y] [-n] [-t] [-a <value>] [-e <level>] [-m <name>]
./clause config set [--local] <key> <value> # keys: args|effort|model|mount (mount needs --local)
./clause config reset [--local] [<key>]      # no key resets every key at that scope
./clause config list                         # workspace + profile config, per scope
./clause config help                         # what every key means and accepts
./clause profile create <name> | reset <name> | delete <name> | list
./clause image build | suggest               # acts on the bound profile; -b = image build
./clause bind <profile> | --unset             # -p is an alias for bind
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
- Bootstrap is lazy: `bootstrap_state` idempotently seeds `~/.clause/profiles/default/` before any non-read-only command. The read-only commands (`status`, `profile list`, `config list`, `config help`, `-h`) never touch disk.
- Named profiles are created only by `profile create` (full seed, then binds the workspace, prompting before rebinding to a different profile). Profile-tier files are never left missing: launch calls `seed_profile` before using the profile, so one that predates a new template file gains it silently instead of failing. `require_profile_files` still runs right after as a post-condition, but it can now only fire when the repo's own `default/` is incomplete, and says so.
- `profile reset <name>` restores clause's shipped configuration: `reseed_profile` overwrites every template file except the ones `preserved_on_reset` carves out (`.claude.json`, `.gitconfig`, `.claude/clause-sudo.log`), so the profile keeps its login, history, git identity and sudo log and loses only local edits to the files clause ships. `reset_files` is the shared list, walked with a `prompt_reset_item` (y/n/q) per file so nothing is overwritten before its name is on screen (`n` skips, `q` stops the rest, `-y`/`-n` answer them all); the list is collected into an array first, because the prompt reads stdin and a `while read < <(reset_files)` loop would feed it the file list. It reminds you to rebuild, plus warns when the `nested` marker survives a Containerfile whose block is commented out again.
- `profile delete` refuses `default`, prompts (y/n/q, so `-y` confirms it), and removes the profile dir, the `clause-<profile>` image, and the `clause-<profile>-containers` volume. Bindings are local files, so it cannot unbind other workspaces; a stale binding hard-errors on that workspace's next launch.
- Profile names are validated by `validate_profile_name` (`^[a-z0-9][a-z0-9._-]*$`, after lowercasing): at parse time in `bind` / `profile create` / `profile delete`, and again in `require_profile` so a hand-edited binding cannot feed a traversal name into `rm -rf` or the image/volume tags. Read-only views stay tolerant of an invalid bound name.

### Workspace config and layering

- Per-workspace state lives in `<workspace>/.clause/` (the `profile` binding plus optional `args`, `effort`, `model`, `mount` overrides) and travels with the folder; there is no central registry. `ensure_workspace_config_dir` creates the dir with a `.gitignore` of `*` so the enclosing project ignores it automatically (created only when absent, never overwritten).
- Binding: `bind <profile>` writes `<workspace>/.clause/profile` (prompting if already bound); `bind --unset` removes it. Launch uses the bound profile, else `default` (first run from an unbound workspace offers to save the binding, y/n/q). `bind` is the only session-side way to name a profile; launch, `image`, `podman`, `status`, and `config` all act on the bound profile.
- Presence decides the tier, for every knob (`resolve_layered`): a file that exists wins even when empty (that tier says "no value", so nothing is injected), and only an ABSENT file falls through to the next tier. So the workspace tier has no files by default and passes through; writing one there overrides the profile, and writing an empty one switches the knob off for that directory alone. The `raw`/`token` modes now differ only in whitespace-stripping and validation, not in how emptiness is read.
- Args resolve via `resolve_args` (raw mode: first line verbatim): `-a` one-shot, then workspace `.clause/args`, then profile `args`, then (default profile only, when the profile file is absent) the repo `default/args` template. `config reset --local args` deletes the workspace file so args fall through; `config reset args` re-seeds the profile file from the template (never deletes); `config set args ''` writes a present-but-empty file meaning no args (`--local` for the workspace tier).
- Effort resolves via `resolve_effort` (token mode: whitespace-stripped, invalid file values warn and fall through): `-e`, then workspace `.clause/effort`, then profile `effort`, then the default template. Valid levels: `low|medium|high|xhigh|max` (`max` is valid for the CLI flag though not for settings.json `effortLevel`). A one-shot `-a` is a complete args override and bypasses stored effort files; only `-e` refines `-a`. Under `-t` the resolved args are not passed to the container command (bash), but they are still resolved and exported as `CLAUSE_ARGS` so the in-container `clause` alias mirrors them.
- Model resolves via `resolve_model`, shaped exactly like `resolve_effort` (token mode, same tiers, same `-a` bypass with only `-m` refining it), but its shipped template is empty, so out of the box no `--model` is injected and claude picks its own model. `validate_model` checks shape, not a fixed list (`^[A-Za-z0-9][A-Za-z0-9._:/@-]*(\[[A-Za-z0-9._-]+\])?$`), so aliases, full ids, `sonnet[1m]`-style variants, and provider-qualified ids all pass while whitespace, shell metacharacters, and leading `-` are rejected; the single-token rule matters because the value is re-split with `read -ra` downstream.
- An empty value is legal everywhere a value is written or passed, and skips validation: `config set [--local] <key> ''` at either scope, and the `-e ''` / `-m ''` one-shots (which suppress a flag for a single launch). Validation only applies to non-empty values.
- `apply_flag_to_args <flag> <value>` is the shared injector for both: it replaces an existing `<flag>` / `<flag>=` token in the resolved args or appends one, guaranteeing exactly one of each in the final command, and is a no-op on an empty value. Launch and `status` call it as `--effort` then `--model`, so the rendered line is stable.
- Mount: `<workspace>/.clause/mount` pins the logical path encoded into the container-side workspace path (bind target + cwd) so Claude's path-keyed history survives moving the host folder; the bind-mount source stays the real workspace. Workspace-only (no profile tier; writing `mount` without `--local` is a parse error pointing at `config set --local mount`). Values must be absolute with no trailing slash (`validate_mount_path`); an invalid file value warns and falls through. It is the one knob where an empty file is not a value (there is no empty container path), so `resolve_mount_path` ignores an empty line and encodes the real workspace. Applies in both claude and `-t` modes.
- The `config` subcommand manages the four knobs through required verbs: `config <set|reset|list|help> [-l|--local] <key> [<value>]`, parsed by `parse_config_args` (not `parse_subcommand`: the key/value positionals need their own grammar; missing/unknown verbs reuse `subcommand_error`). Writes target the workspace's bound profile by default; `-l/--local` targets the workspace override tier and is required for it (and therefore for every `mount` write). `set` requires an explicit value (`config set args ''` writes empty). `reset` undoes one tier's customization: profile scope re-seeds from the repo template, `--local` scope deletes the override file so the workspace passes through again. `reset` is the one verb whose key is optional: bare `config reset [--local]` walks every key at that scope (workspace `args effort model mount`, profile `args effort model` since mount has no profile tier) through the same per-key `config_reset_key`, asking `prompt_reset_item` (y/n/q) before each one — nothing is written before its name is on screen, `n` skips it, `q` stops the rest, and `-y`/`-n` answer them all. A named key still resets straight away, unprompted. The only read is `config list` (rejects `--local`): it dumps stored values per scope with no cross-tier resolution and no template fallback (`(unset)` / `(empty)`); the effective-value-and-source view is `status`'s job. Non-set verbs reject a trailing value at parse time. `config help` (also `config -h`, or `-h` after any verb) prints the key reference and exits from inside `parse_config_args`, like `-h` everywhere else, so it never dispatches through `main` and never touches disk; `config_help` interpolates each knob's shipped value with `template_value_for`, reading `default/` so the help cannot drift from what is seeded.
- `status` is the full dashboard, printed as three groups under headings: `workspace (<path>):` (profile, binding, mount), `config:` (raw args, effort, model, then the effort- and model-injected `launch:` line), and `environment:` (runtime via the soft probe, image built state). The workspace path is the first heading, so the binding line no longer repeats it. Every value starts at one column: `STATUS_LABEL_W` is the shared label width, applied by `status_line` for indented rows and by the heading rows padding to `STATUS_LABEL_W + 2`. The config group is a two-column table whose `source` column names the tier, not the path: `source_label` maps a resolved `*_SOURCE` to `workspace` / `profile` and passes the already-short `default template` and one-shot flag labels through, since the path is just tier + key and `config list` prints both scopes' directories. Its width is measured over the rows that have a source, floored at the width of the `value` header (else `source` would sit a column right of the sources beneath it); `launch:` has no source and is the longest line by construction, so it is left out of the measure and printed unpadded, which also keeps every line free of trailing whitespace. The header row itself is suppressed when no key has a source. `mount` keeps its source inline in parentheses, only when overridden. It distinguishes a tier explicitly asking for no flag (`(none)`, with that tier as the source) from nothing being set anywhere (`(unset)`). For the `default` profile, `status` reads absent profile `args`/`effort`/`model` from the repo `default/` template via `profile_tier_file` (source shown as `default template`), matching what a launch would seed after bootstrap; named profiles never fall back.

### Command surface and parsing

- One command per invocation: `set_command` claims the single `COMMAND` (default `launch`); a second command flag is a parse-time error naming both. Session modifiers (`-t -w -a -e -y -n`) combine with any command and must precede it.
- Noun-verb subcommands (`config set|reset|list|help`, `profile create|reset|delete|list`, `image build|suggest`, `podman enable|disable|reset`, `alias create|delete`, `status`) plus the inline-parsed top-level words `bind <profile>` / `bind --unset` and `runtime <podman|docker>` / `runtime --unset` (both require their value or `--unset`; bare `bind`, like bare `runtime`, is a parse error). Reserved words: `config profile image podman alias runtime status bind`. `parse_subcommand` maps `<noun> <verb>` onto the internal `COMMAND` values the `main` dispatch uses. Two flag-spelled command shortcuts (not session modifiers, they claim `COMMAND` via `set_command`): `-p` is a case-arm alias for `bind` (same required profile and `--unset` handling, labels and errors name the token typed), and `-b` maps to the internal `build` command like `image build`.
- Only `profile create`/`reset`/`delete` take a trailing profile name, and for them it is required (omitting it is a parse error); every other subcommand acts on the bound profile and rejects one with an error pointing at `bind`. A leading bare word is an unknown-command error: launch takes no profile argument, so profiles may be named like command words without collision.
- Input is validated at parse time before any side effects: `validate_effort`, `validate_model`, `validate_mount_path`, `validate_config_key`, `validate_profile_name` (empty values skip value validation, since empty is a legal "no value").
- Prompts: every prompt is the same y/n/q question, destructive ones included, and all of them honor `-y`/`-n`, so a scripted run never blocks on input. `prompt_ynq` is the primitive (sets `PROMPT_REPLY`), `prompt_yes` the true-on-y wrapper, and `prompt_reset_item` the reset-loop variant that asks once per file or key (`n` skips it, `q` stops the rest) so nothing is written before you see its name. There is no typed-`yes` gate: `-y` is the confirmation for `profile delete`, `podman reset`, `alias delete`, and `runtime --unset` too.
- `image suggest` parses the profile's sudo log (rejoining sudo's wrapped continuation lines), collects apt/npm-global/pip/gem/cargo/snap installs, and drops candidates whose exact package name already appears as a token on an uncommented line of the target Containerfile (exact match, not substring; comment lines, including the shipped disabled nested block, never suppress a suggestion).
- Help groups the workspace/profile-scoped commands under `commands (then exit):` and the machine-wide `runtime` / `alias` under `global (machine-wide setup):`. `README.md`'s usage block mirrors `./clause -h` byte for byte.

### Defaults shipped in `default/`

- `settings.json`: `permissions.defaultMode = "bypassPermissions"`; `enabledPlugins` enables `skill-creator` and `claude-md-management` (official marketplace, auto-installs on the profile's first networked session); `effortLevel = "xhigh"` (governs only bare `claude` runs in `-t` sessions, since normal launches pass `--effort`); `disableRemoteControl = true` (keeps sessions local-only). Seeding never overwrites, so profiles created earlier keep their existing settings.
- `effort` = `max`, `args` = `--dangerously-skip-permissions`, and `model` = empty (unset), so a normal launch runs `claude --dangerously-skip-permissions --effort max` and lets claude pick its own model until a tier sets one.
- `Containerfile` bakes a `clause` alias, lazygit with an `lg` alias, and superfile (binary `spf`) with an `sf` alias into the container `.bashrc`. The `clause` alias expands `$CLAUSE_ARGS`, which every launch sets to the effort- and model-injected resolved args (the same line `status` renders as `launch:`), so `-t` sessions mirror the workspace's real launch command; empty or unset means bare `claude`. Baked at build time: profiles with an older `Containerfile` pick changes up only after a manual edit (or deleting the profile `Containerfile` so `image build` re-seeds it) plus a rebuild.

### Nested podman

- Opt-in per profile: the managed Containerfile block ships commented out in `default/Containerfile` (between `# clause-nested-begin` / `# clause-nested-end`, every payload line prefixed `#~ `; the builder strips comment lines, so a disabled block adds nothing to the image) and seeds into every profile with the rest of the template. `podman enable` creates the profile's `nested` marker and offers to uncomment the block in place (a Containerfile predating the markers gets the current template block appended instead); `podman disable` removes the marker and offers to re-comment it. Toggling edits the `#~ ` prefix only, never deleting, so in-block edits survive disable/enable; the flip side is that toggling never refreshes the block text: to pick up a newer template block, delete the marker range and rerun `podman enable`. Rebuild required after toggling.
- With the marker, launch adds `--device /dev/fuse --device /dev/net/tun --security-opt label=disable` plus the storage volume; docker additionally gets seccomp/apparmor `unconfined` (its defaults block unshare/mount). Missing devices are skipped with a warning; launch warns (non-fatally) if the Containerfile does not appear to install podman on an uncommented line (so a still-commented block warns).
- Inner storage lives in the named volume `clause-<profile>-containers` at `/home/claude/.local/share/containers` (persists inner images across sessions, allows native overlayfs, keeps nested-subuid-owned files out of the profile dir). Removed by `profile delete` and by `podman reset` (both prompt first).
- The nested block also installs lazydocker (with a wrapper function, alias `ld`, that starts `podman system service` on demand and points `DOCKER_HOST` at its socket) and a config mapping compose actions to `podman-compose`.

### Script conventions

- `set -euo pipefail`. A function whose last statement could be a false test must end with an explicit `return 0` (a trailing `[[ ... ]] && ...` would return nonzero and trip `set -e` in callers). Use `i=$((i+1))`, never `((i++))` (which returns 1 at 0).
- Cross-function globals are declared in the commented block at the top of the script; command bodies use lowercase `local` variables. `CONTAINER_NAME` stays global because `cmd_launch` returns instead of exiting, so its EXIT trap fires after the function frame is gone.
- Read-only allowlists: `bootstrap_state` skips seeding for `status|profile-list` and `config list` (`config help` exits during parsing, before bootstrap runs at all); `detect_runtime` only runs for `build|delete-profile|podman-reset|launch` (everything else must work on a runtime-less host).
- The script's only top-level statement is `main "$@"` on the last line. Keep it a bare call: wrapping it in a conditional would disable `set -e` inside `main`, and having it last means the whole file is parsed before any logic runs (safe to edit while a session is live).
