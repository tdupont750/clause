# clause

A Podman container for running [Claude Code](https://claude.ai/code) CLI in an isolated environment, with persistent settings and credentials across sessions.

## Requirements

- [Podman](https://podman.io/)

## Setup

Build the image:

```bash
podman build -t clause .
```

Make the script executable if it isn't already:

```bash
chmod +x clause
```

## Usage

```bash
# Mount the current directory as the workspace
./clause

# Mount a specific directory as the workspace
./clause ~/projects/myproject
```

This drops you into an interactive bash session inside the container with your chosen directory mounted at `/workspace`. Claude Code is available as `claude`.

On first run, Claude will prompt you to log in. Credentials are persisted and you won't need to log in again.

The container is removed when you exit the session.

## Persistence

All Claude settings, credentials, history, and plugins are stored in `.claude/` and `.claude.json` in this project directory. These are bind-mounted into the container at `/root/.claude/` and `/root/.claude.json` on every run.

| What | Host path |
|------|-----------|
| Credentials, history, plugins, cache | `.claude/` |
| Settings, first-run state | `.claude.json` |

Both paths are gitignored.

## Rebuilding

After changes to `Containerfile`:

```bash
podman build -t clause .
```
