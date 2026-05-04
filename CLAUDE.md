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
./clause [profile] [-w workspace] [-y] [-n] [-s] [-t] [-d] [-r] [-a] [-m] [-l]
./clause [profile] --profile-create
./clause [profile] --profile-delete
./clause [profile] --profile-container-create
./clause [profile] --profile-container-delete
./clause [profile] --profile-container-suggest
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
- **No auto-create for named profiles** — named profiles must be created explicitly with `--profile-create`; only `default` is created automatically on launch
- **~/.clause/clause.conf format** — one `absolute-path=profilename` entry per line; parsed with awk for literal-safe matching
- **Bootstrap on every launch** — `~/.clause/`, `~/.clause/profiles/default/`, and `~/.clause/clause.conf` are created idempotently at startup; no manual setup required
- **`--build` flag, not bare container CLI** — image build is done via `clause --build`; the script errors with a clear message if the image is missing
- **Positional profile argument** — profile is passed as a positional arg (e.g. `clause myprofile`), not `-p`; defaults to `default`
- **`--profile-create` auto-maps** — after creating a profile scaffold, automatically adds the current workspace→profile mapping
- **`--profile-delete` auto-unmaps** — after deleting a profile directory, automatically removes all its workspace mappings
- **Per-profile `Containerfile`** — running `--profile-container-create` copies the default `Containerfile` into the profile directory; `--build` then builds `clause-<profile>` from it; `--profile-container-delete` removes it and deletes the image
- **`-a`/`--add` for explicit mapping** — adds a workspace→profile mapping without starting a session; warns and prompts if a mapping already exists
- **`-m`/`--mapping` to inspect mapping** — prints the saved workspace→profile mapping for the current workspace, then exits; prints `(no mapping)` if none exists
- **Per-profile `.gitconfig`** — each profile has its own `.gitconfig` bind-mounted at `/root/.gitconfig`; starts empty, persists across sessions
- **Auto session resume** — on `SessionEnd`, a hook writes the session ID to `/workspace/.clause-session-id` (i.e. `$WORKSPACE/.clause-session-id` on the host); on next launch, if that file exists, clause automatically passes `--resume <id>` to claude and deletes the file; use `-s`/`--new-session` to skip resume; `.clause-session-id` is gitignored
- **`defaults/` — seed files** — `settings.json` and `CLAUDE.md` are copied into `~/.clause/profiles/<name>/.claude/` on first use if the files do not already exist; never overwritten by the script afterward (users can freely modify their profile's copies); deleted only when the profile is deleted
