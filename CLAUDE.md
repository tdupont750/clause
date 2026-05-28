# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Documentation

When changing any flag, option, or behavior in `clause`, always update both `CLAUDE.md` and `README.md` to reflect the change. The usage block in `README.md` should stay in sync with `./clause -h`.

## Project Structure

- `defaults/Containerfile` — image definition (Ubuntu 24.04, Node.js 22, claude CLI)
- `clause` — wrapper script that starts an ephemeral container session
- `defaults/settings.json` — default Claude settings seeded into new profiles on first use
- `defaults/CLAUDE.md` — default Claude instructions seeded into new profiles on first use
- `~/.clause/` — runtime state directory (auto-created on first run)
- `~/.clause/profiles/` — named profile directories, each with `.claude/`, `.claude.json`, and `.gitconfig`
- `~/.clause/profiles/default/` — built-in default profile (auto-created on first run)
- `~/.clause/clause.conf` — workspace→profile mappings (auto-created on first run)

## Building

```bash
./clause --build
```

## Running

```bash
./clause [profile] [-w workspace] [-y] [-n] [-t] [-m] [-u] [-l] [-L] [-a <string>]
./clause [profile] -C | --create-profile
./clause [profile] -D | --delete-profile
./clause [profile] -R | --reset-containerfile
./clause [profile] -A | --args-view
./clause            --args-set <string>
./clause [profile]  --args-set-profile <string>
./clause [profile] -S | --suggest-updates
./clause --alias-create
./clause --alias-delete
./clause -b
```

See `README.md` for full flag documentation.

## Key Decisions

- **Podman preferred, Docker supported** — `clause` auto-detects the container runtime at startup, preferring `podman` over `docker`; all container calls go through `$CONTAINER_CLI`; the override is stored in `~/.clause/runtime` and managed with `--runtime-set` / `--runtime-remove`
- **Ephemeral containers** — `--rm` removes the container on exit; all state is in bind mounts
- **No SSH** — sessions are interactive via the container runtime CLI (`podman run -it` or `docker run -it`)
- **Non-root user in container** — Claude runs as the in-image `claude` user (UID 1000); host UID is mapped via `--userns=keep-id:uid=1000,gid=1000` (podman) or `--user $(id -u):$(id -g)` (docker) so bind-mounted profile files stay writable. Passwordless `sudo` is available for ad-hoc installs; every sudo invocation is logged to `~/.clause/profiles/<name>/.claude/clause-sudo.log`
- **Profiles, not a single state dir** — each named profile under `~/.clause/profiles/` is independent; `default` is always bootstrapped
- **No auto-create for named profiles** — named profiles must be created explicitly with `--create-profile`; only `default` is created automatically on launch
- **~/.clause/clause.conf format** — one `absolute-path=profilename` entry per line; parsed with awk for literal-safe matching
- **Bootstrap is lazy** — `~/.clause/`, `~/.clause/profiles/default/`, and `~/.clause/clause.conf` are created idempotently the first time a non-read-only command runs; `-l` / `-L` and `-h` are pure read-only and never touch disk
- **`--build` flag, not bare container CLI** — image build is done via `clause --build`; the script errors with a clear message if the image is missing
- **Positional profile argument** — profile is passed as a positional arg (e.g. `clause myprofile`), not `-p`; defaults to `default`
- **`--create-profile` seeds a fully-formed profile** — copies all four `defaults/` files (`Containerfile`, `clause-args`, `settings.json`, `CLAUDE.md`), writes an empty `.claude.json`, touches `.gitconfig` and `clause-sudo.log`, and adds the current workspace→profile mapping. The launch path's "Init profile runtime data" block keeps an idempotent lazy seed as a fallback so profiles created before this change still get filled in on next use
- **`--delete-profile` auto-unmaps and removes image** — after deleting a profile directory, removes all its workspace mappings and the `clause-<profile>` image if present
- **Per-profile `Containerfile`** — every profile has its own `Containerfile`; `--build` builds `clause-<profile>` from it; `--reset-containerfile` overwrites it with the current default
- **Claude args layering** — args appended to `claude` resolve in this order: (1) `-a/--args <string>` one-shot CLI override; (2) workspace-local `<workspace>/.clause-args` (present-file wins, even empty → no args); (3) profile-level `~/.clause/profiles/<name>/clause-args` (seeded default: `--effort max --dangerously-skip-permissions`). Setters: `--args-set` writes the workspace file, `--args-set-profile` writes the profile file. `-A/--args-view` prints the effective args and reports the source. All args are ignored under `-t`
- **`-m`/`--map` for explicit mapping** — adds a workspace→profile mapping without starting a session; warns and prompts if a mapping already exists. Removed counterpart is `-u`/`--unmap`
- **`-l`/`--list` combined view** — prints the current workspace mapping and lists all profiles
- **`-L`/`--list-all` for every mapping** — prints the full contents of `~/.clause/clause.conf`
- **Per-profile `.gitconfig`** — each profile has its own `.gitconfig` bind-mounted at `/home/claude/.gitconfig`; starts empty, persists across sessions
- **Encoded workspace mount** — the host workspace is bind-mounted at `/workspace/<encoded-host-path>` and `-w` sets the container cwd to the same path, where `<encoded-host-path>` is the host workspace with `/` and `.` replaced by `-` (same scheme Claude uses for `~/.claude/projects/`). This keeps Claude's per-project state (logs, todos, history) separated by host workspace even when multiple workspaces share a profile
- **`defaults/` — seed files** — `settings.json`, `CLAUDE.md`, `Containerfile`, and `clause-args` are seeded into the profile on first use if missing; never overwritten by the script afterward (users can freely modify their profile's copies); deleted only when the profile is deleted
- **`bypassPermissions` by default** — `defaults/settings.json` ships with `permissions.defaultMode = "bypassPermissions"`. Profiles created before this change keep whatever was already in their `settings.json`.
