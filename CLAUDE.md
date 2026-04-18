# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Project Structure

- `Containerfile` — image definition (Ubuntu 24.04, Node.js 22, claude CLI)
- `compose.yaml` — build management only (not used to start containers)
- `clause` — wrapper script that starts an ephemeral container session
- `.claude/` — persisted Claude config directory (gitignored, bind-mounted into container)
- `.claude.json` — persisted Claude settings file (gitignored, bind-mounted into container)

## Building

```bash
podman build -t clause .
```

## Running

```bash
./clause [directory]
```

## Key Decisions

- **Podman, not Docker** — use `podman` commands, not `docker`
- **Ephemeral containers** — `--rm` removes the container on exit; all state is in bind mounts
- **No SSH** — sessions are interactive via `podman run -it`
- **Root user in container** — Claude runs as root inside the container
- **Persistence** — `.claude/` and `.claude.json` are bind-mounted from the project directory
