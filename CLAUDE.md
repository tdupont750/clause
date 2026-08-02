# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Documentation

`docs/reference.md` is the user-facing contract: every command, flag, config key, and
precedence rule lives there. When you change a flag, option, or behavior in `clause`,
update it, and update the Implementation Map below if the change moves a function or an
invariant.

`README.md` is deliberately short: install steps, the usage block, and high-level
concepts only. Touch it when a change alters the usage output (the block must stay in
sync with `./clause -h`, byte for byte) or when it changes a concept the README
describes. Routine flag and behavior detail belongs in `docs/reference.md`, which the
README links at the bottom.

`tests/docs.sh` checks the two sync promises that have drifted before: the README usage
block against `./clause -h`, and the keys in `default/.claude/settings.json` against
`docs/reference.md`. Run it before committing a doc or usage change.

This file describes current behavior only. The full historical design log, including
superseded decisions and their rationale, lives in `docs/decisions.md`, which is
untracked and local-only (gitignored, not part of the published repo); when a change
supersedes something here, update the bullet in place and record the history there if
the file is present.

## Project Structure

- `clause`: wrapper script that starts an ephemeral container session
- `tests/docs.sh`: documentation drift checks (see above)
- `default/`: profile template mirroring a real profile under
  `~/.clause/profiles/<name>/`; seeded into profiles on first use (every `default/<rel>`
  maps to `<profile>/<rel>`)
  - `default/Containerfile`: image definition (Ubuntu 24.04, Node.js 22, claude CLI,
    lazygit, superfile), plus the nested podman block shipped commented out
  - `default/args`: default `claude` args (`--dangerously-skip-permissions`)
  - `default/effort`: default effort level (`xhigh`), injected into the args at launch
  - `default/model`: default model (`claude-opus-5`), injected into the args at launch
  - `default/.claude/settings.json`: default Claude settings (permissions, hooks,
    plugins, effort, output style; itemized in `docs/reference.md`)
  - `default/.claude/CLAUDE.md`: default Claude instructions
  - `default/.claude/hooks/set-bg.sh`: terminal background-color hook (invoked by the
    seeded `settings.json` hooks)
  - `default/.claude/output-styles/laconic.md`: the `Laconic` output style the seeded
    `settings.json` selects via `outputStyle` (force-added past the repo's `.claude/`
    gitignore)
  - `default/.claude.json`: empty Claude state `{}`
  - `default/.gitconfig`: empty git config
  - `default/.claude/clause-sudo.log`: empty sudo activity log (force-added past the
    repo's `.claude/` gitignore)
- `~/.clause/`: runtime state directory (auto-created on first run); `~/.clause/runtime`
  pins the container runtime
- `~/.clause/profiles/`: named profile directories, each with `.claude/`, `.claude.json`,
  `.gitconfig`, `Containerfile`, `args`, `effort`, and `model`
- `~/.clause/profiles/default/`: built-in default profile (auto-created on first run)
- `<workspace>/.clause/`: per-workspace config dir holding the `profile` binding and
  optional `args`/`effort`/`model`/`mount` overrides; lives inside each workspace, so it
  travels with the folder
- `docs/reference.md`: user-facing reference (all commands, flags, config keys,
  precedence)
- `docs/decisions.md`: historical design-decision log (untracked, local-only)

## Building

```bash
./clause image build
```

## Checks

```bash
tests/docs.sh
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

## Implementation Map

What `clause` does for a user is documented in `docs/reference.md`; do not restate it
here. This section is the in-code view: which function owns a behavior, and the
invariants that are not obvious from reading it. Where the two overlap, reference.md is
the contract and this is the map to the code.

### Layered config (`args`, `effort`, `model`, `mount`)

- `resolve_layered` is the shared resolver. Presence decides the tier: a file that
  exists wins even when empty, and only an ABSENT file falls through. Its `raw` and
  `token` modes differ in whitespace-stripping and validation only, never in how
  emptiness is read.
- `resolve_args` (raw) and `resolve_effort` / `resolve_model` (token: invalid file
  values warn and fall through) wrap it. Only the `default` profile falls back to the
  repo `default/` template when a profile file is absent; named profiles do not.
- `resolve_mount_path` is the exception: there is no empty container path, so an empty
  file is ignored rather than honored, and the fallback is `encode_path` of the real
  workspace.
- `apply_flag_to_args <flag> <value>` injects `--effort` then `--model`, replacing an
  existing `<flag>` / `<flag>=` token or appending one, so exactly one of each survives.
  It is a no-op on an empty value. Launch and `status` both call it in that order, which
  is why the `launch:` row cannot disagree with a real launch.
- A one-shot `-a` replaces the whole args line and bypasses the stored `effort`/`model`
  files; only `-e`/`-m` refine it. Under `-t` the resolved args are not passed to the
  container command (bash), but are still resolved and exported as `CLAUSE_ARGS` for the
  in-container `clause` alias.
- `MOUNT_VALUE` is always a final `/workspace/...` path, which is what makes the stored
  file, the `status` row, and `status mount` one string (so re-pinning is idempotent).
  `validate_mount_path` is the only guard on a value that reaches the runtime's argv
  unsanitized, so it runs on write (parse time) and on read. Invalid values split by
  caller: `resolve_mount_path` records `MOUNT_INVALID` and falls back, read-only views
  call `warn_mount_invalid` (stderr, keeping `status mount` stdout clean), and
  `cmd_launch` exits 1 rather than silently re-key Claude's history.
- `mount` is workspace-only. `parse_config_args` rejects a profile-scoped write, and the
  reset-all walk skips it at profile scope.

### Profiles and seeding

- `default/` is the single source of a profile's initial state; no file contents are
  generated in code. `seed_profile` copies missing files only, walking `default_files`
  (a find over `default/`, dotpaths included).
- `bootstrap_state` seeds `~/.clause/profiles/default/` idempotently before any
  non-read-only command. Launch calls `seed_profile` before using a profile, so one that
  predates a new template file gains it silently; `require_profile_files` runs after as a
  post-condition and can now only fire when the repo's own `default/` is incomplete.
- `reseed_profile` (`profile reset`) overwrites every template file except those
  `preserved_on_reset` carves out (`.claude.json`, `.gitconfig`,
  `.claude/clause-sudo.log`). `reset_files` is the shared list, and it is collected into
  an array before prompting: a `while read < <(reset_files)` loop would feed the file
  list to `prompt_reset_item`'s stdin read.
- `validate_profile_name` (`^[a-z0-9][a-z0-9._-]*$`, after lowercasing) runs at parse
  time and again in `require_profile`, so a hand-edited binding cannot feed a traversal
  name into `rm -rf` or the image and volume tags. Read-only views stay tolerant of an
  invalid bound name.
- `ensure_workspace_config_dir` creates `<workspace>/.clause/` with a `.gitignore` of
  `*`, only when absent, never overwriting.

### Parsing

- `set_command` claims the single `COMMAND` (default `launch`); a second is a parse-time
  error naming both. `parse_subcommand` maps `<noun> <verb>` onto the internal `COMMAND`
  values `main` dispatches on. `bind` and `runtime` are parsed inline instead, because
  they take a value or `--unset` rather than a verb.
- `parse_config_args` is separate from `parse_subcommand` because the key/value
  positionals need their own grammar; it reuses `subcommand_error` for missing or unknown
  verbs. Flags precede the key so a dash-prefixed value is taken verbatim.
- `-p` is a case-arm alias for `bind` and `-b` maps to the internal `build` command; both
  claim `COMMAND` via `set_command` (they are commands, not session modifiers), and their
  labels and errors name the token actually typed.
- `status`'s optional `<key>` arm consumes a bare word but deliberately does not `break`
  the parse loop the way `bind` does, so trailing session options keep working. A second
  bare word is its own error, naming both keys, so the unknown-command arm cannot blame
  the wrong token.
- All validation happens at parse time, before side effects: `validate_effort`,
  `validate_model`, `validate_mount_path`, `validate_config_key`, `validate_status_key`,
  `validate_profile_name`. Empty values skip value validation, since empty is a legal
  "no value" everywhere except `mount`.
- `validate_status_key` is a superset of `validate_config_key` (it adds the read-only
  rows and the derived `launch` line), hence a separate list rather than a call.
- `validate_model` checks shape, not a fixed list
  (`^[A-Za-z0-9][A-Za-z0-9._:/@-]*(\[[A-Za-z0-9._-]+\])?$`). The single-token rule is
  load-bearing: the value is re-split with `read -ra` downstream.
- `prompt_ynq` is the prompt primitive (sets `PROMPT_REPLY`), `prompt_yes` the true-on-y
  wrapper, `prompt_reset_item` the per-item variant. All honor `-y`/`-n`, destructive
  prompts included, so a scripted run never blocks. There is no typed-`yes` gate.

### Status rendering

- `STATUS_LABEL_W` is the shared label width, applied by `status_line` for indented rows
  and by the heading rows padding to `STATUS_LABEL_W + 2`, so every group's values start
  at one column.
- The config group is a `source`-then-`value` table. Source-first is load-bearing: only
  the sources are measured (floored at the width of the `source` header, else `value`
  would sit left of the values beneath it), so unbounded-width values all start at one
  column and a long args or `launch:` line runs off to the right instead of blowing out a
  padded column. When no key has a source anywhere, the column would be pure indent, so
  that case falls back to plain `status_line` rows.
- `source_label` maps a `*_SOURCE` to a tier name, not a path, and passes the
  already-short `default template` and one-shot flag labels through.
- There is no binding row: `PROFILE_NAME` is `${binding:-default}`, so one would repeat
  the profile row in every state but the unbound one. That single bit is a note on the
  profile row instead, and notes are collected into an array and joined, since a first
  run is both `unbound` and `not created`. The raw `status binding` key survives the
  row's removal, because a script still has that question.
- `status_key_value` handles `status <key>`, delegated to by `cmd_status` before anything
  prints. It drops everything the table wraps around a value (label, source, parenthesised
  stand-ins), reads through the same resolvers, and only `runtime` probes. Exit is 0 for
  any valid key, empty value included, so "is it set" is a string test.

### Launch and runtime

- `detect_runtime` honors `~/.clause/runtime` first (must be `podman` or `docker` and on
  PATH, hard error otherwise), else auto-detects podman then docker. `probe_runtime` is
  the soft shared probe that `status` uses report-only, so it works with no runtime
  installed.
- The container user is `claude` (UID 1000). Podman maps the host user with
  `--userns=keep-id:uid=1000,gid=1000`, docker with `--user $(id -u):$(id -g)`; either
  way the point is that bind-mounted profile files stay writable.
- The image is always `clause-<profile>`, built from that profile's own `Containerfile`.
  There is no shared fallback image, so launch errors when it is missing.
- `encode_path` (`/` and `.` become `-`) matches the scheme Claude uses for
  `~/.claude/projects` keys, which is why per-project state stays separate when
  workspaces share a profile. It survives only as `resolve_mount_path`'s default.
- `image suggest` rejoins sudo's wrapped continuation lines, collects apt / npm-global /
  pip / gem / cargo / snap installs, and drops candidates whose exact package name is
  already a token on an uncommented line of the target `Containerfile` (exact match, not
  substring, so comment lines never suppress a suggestion).

### Nested podman

- The managed block sits between `# clause-nested-begin` / `# clause-nested-end` in
  `default/Containerfile`, shipped with every payload line prefixed `#~ `. The builder
  strips comment lines, so a disabled block adds nothing to the image.
- `podman enable` writes the profile's `nested` marker and offers to uncomment the block
  in place; a `Containerfile` predating the markers gets the current template block
  appended instead. Toggling edits the `#~ ` prefix only, never deleting, so in-block
  edits survive. The flip side: toggling never refreshes the block text, so picking up a
  newer template block means deleting the marker range and re-enabling.
- The marker, not the `Containerfile`, is what launch reads, so the two can disagree:
  launch adds the devices and security options reference.md lists, warns non-fatally when
  the `Containerfile` has no uncommented podman install, and skips a missing device with a
  warning rather than failing.
- The storage volume is mounted at `/home/claude/.local/share/containers` rather than
  landing in the profile dir so that inner storage gets native overlayfs and
  nested-subuid-owned files stay out of the bind mounts.

### Script conventions

- `set -euo pipefail`. A function whose last statement could be a false test must end
  with an explicit `return 0` (a trailing `[[ ... ]] && ...` would return nonzero and trip
  `set -e` in callers). Use `i=$((i+1))`, never `((i++))` (which returns 1 at 0).
- Cross-function globals are declared in the commented block at the top of the script;
  command bodies use lowercase `local` variables. `CONTAINER_NAME` stays global because
  `cmd_launch` returns instead of exiting, so its EXIT trap fires after the function frame
  is gone.
- Read-only allowlists: `bootstrap_state` skips seeding for `status|profile-list` and
  `config list` (`config help` exits during parsing, before bootstrap runs at all);
  `detect_runtime` only runs for `build|delete-profile|podman-reset|launch`, since
  everything else must work on a runtime-less host.
- The script's only top-level statement is `main "$@"` on the last line. Keep it a bare
  call: wrapping it in a conditional would disable `set -e` inside `main`, and having it
  last means the whole file is parsed before any logic runs (safe to edit while a session
  is live).
