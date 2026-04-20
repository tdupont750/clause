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
./clause [profile] [-w workspace] [-y] [-n] [-b] [-R] [-a] [-m] [-l]
./clause [profile] --create-profile
./clause [profile] --delete-profile
./clause -B
```

See `README.md` for full flag documentation.

## Key Decisions

- **Podman, not Docker** — use `podman` commands, not `docker`
- **Ephemeral containers** — `--rm` removes the container on exit; all state is in bind mounts
- **No SSH** — sessions are interactive via `podman run -it`
- **Root user in container** — Claude runs as root inside the container
- **Profiles, not a single state dir** — each named profile under `~/.clause/profiles/` is independent; `default` is always bootstrapped
- **No auto-create for named profiles** — named profiles must be created explicitly with `--create-profile`; only `default` is created automatically on launch
- **~/.clause/clause.conf format** — one `absolute-path=profilename` entry per line; parsed with awk for literal-safe matching
- **Bootstrap on every launch** — `~/.clause/`, `~/.clause/profiles/default/`, and `~/.clause/clause.conf` are created idempotently at startup; no manual setup required
- **`--build` flag, not bare podman** — image build is done via `clause --build`; the script errors with a clear message if the image is missing
- **Positional profile argument** — profile is passed as a positional arg (e.g. `clause myprofile`), not `-p`; defaults to `default`
- **`--create-profile` auto-maps** — after creating a profile scaffold, automatically adds the current workspace→profile mapping
- **`--delete-profile` auto-unmaps** — after deleting a profile directory, automatically removes all its workspace mappings
- **`-a`/`--add` for explicit mapping** — adds a workspace→profile mapping without starting a session; warns and prompts if a mapping already exists
- **`-m`/`--mapping` to inspect mapping** — prints the saved workspace→profile mapping for the current workspace, then exits; prints `(no mapping)` if none exists
- **Per-profile `.gitconfig`** — each profile has its own `.gitconfig` bind-mounted at `/root/.gitconfig`; starts empty, persists across sessions
