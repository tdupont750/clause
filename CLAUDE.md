# Claude Container Project

This project builds and runs a Podman container for Claude Code CLI.

## Project Structure

- `Containerfile` — image definition (Ubuntu 24.04, Node.js 22, claude CLI)
- `compose.yaml` — build management only (not used to start containers)
- `clause` — wrapper script that starts an ephemeral container session
- `profiles/` — named profile directories, each with `.claude/` and `.claude.json` bind-mounted into the container
- `profiles/default/` — the built-in default profile
- `clause.conf` — workspace→profile mappings (gitignored, auto-created at runtime)

## Building

```bash
podman build -t clause .
```

## Running

```bash
clause [-y] [-n] [-t] [-R] [-p profile] [-w workspace]
clause [--create-profile name]
clause [--delete-profile name]
```

| Flag | Description |
|------|-------------|
| `-p name` | Profile to use (lowercased). Defaults to `default`. |
| `-w path` | Workspace directory. Defaults to `$PWD`. |
| `-y` | Auto-answer yes to all prompts. |
| `-n` | Auto-answer no to all prompts. |
| `-t` | Launch `bash` instead of `claude`. |
| `-R` | Remove workspace→profile mapping, then exit. |
| `--create-profile name` | Create a new profile scaffold, then exit. |
| `--delete-profile name` | Delete a profile and all its data, then exit. |

## Key Decisions

- **Podman, not Docker** — use `podman` commands, not `docker`
- **Ephemeral containers** — `--rm` removes the container on exit; all state is in bind mounts
- **No SSH** — sessions are interactive via `podman run -it`
- **Root user in container** — Claude runs as root inside the container
- **Persistence** — each profile's `.claude/` and `.claude.json` are bind-mounted from `profiles/<name>/`
