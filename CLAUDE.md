# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Documentation

When changing any flag, option, or behavior in `clause`, always update both `CLAUDE.md` and `README.md` to reflect the change. The usage block in `README.md` should stay in sync with `./clause -h`.

## Project Structure

- `Containerfile` — image definition (Ubuntu 24.04, Node.js 22, claude CLI)
- `compose.yaml` — build management only (not used to start containers)
- `clause` — wrapper script that starts an ephemeral container session
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
./clause [profile] [-w workspace] [-y] [-n] [-S] [-t] [-R] [-a] [-m] [-l]
./clause [profile] --profile-create
./clause [profile] --profile-delete
./clause [profile] --profile-create-image
./clause [profile] --profile-delete-image
./clause --alias-create
./clause --alias-delete
./clause -B
```

See `README.md` for full flag documentation.

## Key Decisions

- **Podman, not Docker** — use `podman` commands, not `docker`
- **Ephemeral containers** — `--rm` removes the container on exit; all state is in bind mounts
- **No SSH** — sessions are interactive via `podman run -it`
- **Root user in container** — Claude runs as root inside the container
- **Profiles, not a single state dir** — each named profile under `~/.clause/profiles/` is independent; `default` is always bootstrapped
- **No auto-create for named profiles** — named profiles must be created explicitly with `--profile-create`; only `default` is created automatically on launch
- **~/.clause/clause.conf format** — one `absolute-path=profilename` entry per line; parsed with awk for literal-safe matching
- **Bootstrap on every launch** — `~/.clause/`, `~/.clause/profiles/default/`, and `~/.clause/clause.conf` are created idempotently at startup; no manual setup required
- **`--build` flag, not bare podman** — image build is done via `clause --build`; the script errors with a clear message if the image is missing
- **Positional profile argument** — profile is passed as a positional arg (e.g. `clause myprofile`), not `-p`; defaults to `default`
- **`--profile-create` auto-maps** — after creating a profile scaffold, automatically adds the current workspace→profile mapping
- **`--profile-delete` auto-unmaps** — after deleting a profile directory, automatically removes all its workspace mappings
- **Per-profile `Containerfile`** — running `--profile-create-image` copies the default `Containerfile` into the profile directory; `--build` then builds `clause-<profile>` from it; `--profile-delete-image` removes it and deletes the image
- **`-a`/`--add` for explicit mapping** — adds a workspace→profile mapping without starting a session; warns and prompts if a mapping already exists
- **`-m`/`--mapping` to inspect mapping** — prints the saved workspace→profile mapping for the current workspace, then exits; prints `(no mapping)` if none exists
- **Per-profile `.gitconfig`** — each profile has its own `.gitconfig` bind-mounted at `/root/.gitconfig`; starts empty, persists across sessions
- **Auto session resume** — on `SessionEnd`, a hook writes the session ID to `/workspace/.last-session-id` (i.e. `$WORKSPACE/.last-session-id` on the host); on next launch, if that file exists, clause automatically passes `--resume <id>` to claude and deletes the file; use `-S`/`--new-session` to skip resume; `settings.json` with the hook is auto-created per profile if absent; `.last-session-id` is gitignored
