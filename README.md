# clause

A Podman container for running [Claude Code](https://claude.ai/code) CLI in an isolated environment, with persistent settings and credentials stored in named profiles.

## Requirements

- [Podman](https://podman.io/)

## Setup

Make the script executable if it isn't already:

```bash
chmod +x clause
```

Build the container image:

```bash
clause --build-container
```

## Usage

```
usage: clause [-h] [profile] [options]

arguments:
  profile             Profile to use (default: 'default')

session options:
  -w, --workspace     Workspace directory (default: $PWD)
  -b, --bash          Launch bash instead of claude

prompt options:
  -y, --yes           Auto-answer yes to all prompts
  -n, --no            Auto-answer no to all prompts

mapping management (then exit):
  -a, --add           Add workspace→profile mapping
  -R, --remove        Remove workspace→profile mapping
  -l, --list          List all workspace→profile mappings

profile management (then exit):
  --create-profile    Create a new profile scaffold and add mapping
  --delete-profile    Delete a profile and remove its mappings

other:
  --build-container   Build the container image
  -h, --help          Print this help
```

Running `clause` launches Claude Code inside the container with your current directory mounted at `/workspace`.

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `~/.clause/profiles/` with its own `.claude/` and `.claude.json`. The `default` profile is created automatically on first run.

```bash
# Create a profile (also adds a workspace→profile mapping)
clause work --create-profile

# Use a profile
clause work

# Delete a profile (also removes its workspace mappings)
clause work --delete-profile
```

## Workspace Mappings

`clause` remembers which profile to use for each workspace directory in `clause.conf`. On first use from a directory, you'll be prompted to save the mapping.

```
No mapping found. Save /home/tom/projects/myapp → work? [y/n/q]
```

- `y` — save mapping and continue
- `n` — continue without saving
- `q` — exit

If a mapping already exists but you specify a different profile, you'll be prompted to override it.

```bash
# Explicitly add a mapping without starting a session
clause work --add

# Remove a mapping
clause --remove

# List all mappings
clause --list

# Skip prompts in scripts
clause work --yes
```

## Persistence

Each profile's data is stored under `~/.clause/profiles/<name>/` and bind-mounted into the container:

| What | Host path | Container path |
|------|-----------|----------------|
| Credentials, history, plugins, cache | `~/.clause/profiles/<name>/.claude/` | `/root/.claude/` |
| Settings, first-run state | `~/.clause/profiles/<name>/.claude.json` | `/root/.claude.json` |
| Workspace mappings | `~/.clause/clause.conf` | — |
| Workspace | `$PWD` (or `-w path`) | `/workspace/` |

All runtime state lives in `~/.clause/` and is created automatically on first run. Nothing in the clause repo needs to be gitignored for runtime data.

## Rebuilding

After changes to `Containerfile`:

```bash
clause --build-container
```
