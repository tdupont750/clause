# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Project Structure

- `Containerfile` — image definition (Ubuntu 24.04, Node.js 22, claude CLI)
- `compose.yaml` — build management only (not used to start containers)
- `clause` — wrapper script that starts an ephemeral container session
- `~/.clause/` — runtime state directory (auto-created on first run)
- `~/.clause/profiles/` — named profile directories, each with `.claude/` and `.claude.json`
- `~/.clause/profiles/default/` — built-in default profile (auto-created on first run)
- `~/.clause/clause.conf` — workspace→profile mappings (auto-created on first run)

## Building

```bash
podman build -t clause .
```

## Running

```bash
./clause [-p profile] [-w workspace] [-y] [-n] [-t] [-R]
./clause [--create-profile name] [--delete-profile name]
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
