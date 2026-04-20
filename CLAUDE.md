# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Project Structure

- `Containerfile` — image definition (Ubuntu 24.04, Node.js 22, claude CLI)
- `compose.yaml` — build management only (not used to start containers)
- `clause` — wrapper script that starts an ephemeral container session
- `profiles/` — named profile directories, each with `.claude/` and `.claude.json` bind-mounted into the container
- `profiles/default/` — the built-in default profile (tracked in git as scaffold)
- `~/.clause.conf` — workspace→profile mappings (stored in home directory, auto-created at runtime)

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
- **Profiles, not a single state dir** — each named profile under `profiles/` is independent; `default` always exists
- **No auto-create** — profiles must be created explicitly with `--create-profile`; the script never creates a profile directory on launch
- **~/.clause.conf format** — one `absolute-path=profilename` entry per line; parsed with awk for literal-safe matching; stored in home directory so mappings persist across clause installs
