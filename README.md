# clause

A Podman container for running [Claude Code](https://claude.ai/code) CLI in an isolated environment, with persistent settings and credentials stored in named profiles.

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

Running `clause` launches Claude Code inside the container with your current directory mounted at `/workspace`.

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `profiles/` with its own `.claude/` and `.claude.json`.

```bash
# Create a profile
clause --create-profile work

# Use a profile
clause -p work

# Delete a profile (also removes its workspace mappings)
clause --delete-profile work
```

## Workspace Mappings

`clause` remembers which profile to use for each workspace directory in `clause.conf`. On first use from a directory, you'll be prompted to save the mapping.

```
No mapping found. Save /home/tom/projects/myapp → work? [y/n/q]
```

- `y` — save mapping and continue
- `n` — continue without saving
- `q` — exit

If a mapping already exists but you specify a different profile with `-p`, you'll be prompted to override it.

```bash
# Remove a mapping
clause -R

# Skip prompts in scripts
clause -y -p work
```

## Persistence

Each profile's data is stored under `profiles/<name>/` and bind-mounted into the container:

| What | Host path | Container path |
|------|-----------|----------------|
| Credentials, history, plugins, cache | `profiles/<name>/.claude/` | `/root/.claude/` |
| Settings, first-run state | `profiles/<name>/.claude.json` | `/root/.claude.json` |
| Workspace | `$PWD` (or `-w path`) | `/workspace/` |

Profile data and `clause.conf` are gitignored. The `profiles/default/` scaffold is tracked.

## Rebuilding

After changes to `Containerfile`:

```bash
podman build -t clause .
```
