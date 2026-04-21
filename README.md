# Clause

Meet Claude’s safety-conscious friend, Clause!

Clause mounts your working directory into a tiny container with its own copy of Claude Code.

Inside that container, Claude can do whatever it wants, however it wants, while your host machine and all of its secrets stay safe.

Good luck, have fun, don't die!

## Overview

A Podman container for running [Claude Code](https://claude.ai/code) CLI in an isolated environment, with persistent settings and credentials stored in named profiles.

## Requirements

- [Podman](https://podman.io/) or [Docker](https://www.docker.com/)

`clause` auto-detects whichever is on your `PATH`, preferring Podman. To override:

```bash
clause --runtime-set docker
```

## Getting Started

**1. Make the script executable:**

```bash
chmod +x clause
```

**2. Add the shell alias** so you can run `clause` from any directory:

```bash
./clause --alias-create
```

Then reload your shell (`source ~/.bashrc` or open a new terminal).

**3. Build the container image:**

```bash
clause -B
```

**4. Start Claude in your project:**

```bash
cd ~/your-project
clause
```

That's it. Claude Code runs inside the container with your project mounted at `/workspace`.

## Usage

```
usage: clause [-h] [profile] [options]

arguments:
  profile                 Profile to use (default: 'default')

session options:
  -w, --workspace         Workspace directory (default: $PWD)
  -S, --new-session       Start a new session (skip auto-resume)
  -t, --terminal          Launch bash instead of claude

prompt options:
  -y, --yes               Auto-answer yes to all prompts
  -n, --no                Auto-answer no to all prompts

mapping management (then exit):
  -a, --add               Add workspace→profile mapping
  -m, --mapping           Show workspace→profile mapping for current workspace
  -R, --remove            Remove workspace→profile mapping
  -l, --list              List all workspace→profile mappings

profile management (then exit):
  --profile-create        Create a new profile scaffold and add mapping
  --profile-delete        Delete a profile and remove its mappings
  --profile-create-image  Copy default Containerfile into profile directory
  --profile-delete-image  Delete profile Containerfile and container image

alias management (then exit):
  --alias-create          Add clause alias to .bashrc and/or .zshrc
  --alias-delete          Remove clause alias from .bashrc and/or .zshrc

runtime management (then exit):
  --runtime-set <value>   Set container runtime override (podman or docker)
  --runtime-remove        Remove container runtime override

other:
  -B, --build             Build the container image
  -h, --help              Print this help
```

Running `clause` launches Claude Code inside the container with your current directory mounted at `/workspace`.

## Profiles

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `~/.clause/profiles/` with its own `.claude/` and `.claude.json`. The `default` profile is created automatically on first run.

```bash
# Create a profile (also adds a workspace→profile mapping)
clause work --profile-create

# Use a profile
clause work

# Delete a profile (also removes its workspace mappings)
clause work --profile-delete
```

### Per-profile Container Images

By default all profiles share the base `clause` image. You can give a profile its own `Containerfile` to customize the image independently.

```bash
# Copy the default Containerfile into the profile directory
clause work --profile-create-image

# Edit ~/.clause/profiles/work/Containerfile as needed, then build
clause work -B

# Remove the profile's Containerfile and delete the clause-work image
clause work --profile-delete-image
```

- `--profile-create-image` — copies the default `Containerfile` into `~/.clause/profiles/<profile>/Containerfile`.
- `--profile-delete-image` — removes the profile's `Containerfile` and deletes the `clause-<profile>` container image.
- `-B` / `--build` is profile-aware: if the active profile has a `Containerfile`, it builds `clause-<profile>`; otherwise it builds the base `clause` image.

## Session Resume

When a Claude session ends, the session ID is saved to `.last-session-id` in your workspace. The next time you run `clause` from that directory it will automatically resume where you left off.

To start a fresh session instead:

```bash
clause -S
```

The `.last-session-id` file is deleted as soon as it's consumed and is gitignored automatically in the clause repo.

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

# Show the current mapping
clause --mapping

# Remove a mapping
clause --remove

# List all mappings
clause --list

# Skip prompts in scripts
clause work --yes
```

## Shell Alias

Add a `clause` alias to your shell so you can run it from any directory without specifying the full path:

```bash
clause --alias-create
```

This checks for `~/.bashrc` and `~/.zshrc` and prompts to append the alias to each file found. If the alias already exists in a file, it is skipped. To remove it:

> **Note:** Only aliases created by `--alias-create` are detected (they contain a `# clause-alias` marker). Manually created `alias clause=...` entries without this marker will not be detected and may result in duplicates.

```bash
clause --alias-delete
```

## Persistence

Each profile's data is stored under `~/.clause/profiles/<name>/` and bind-mounted into the container:

| What | Host path | Container path |
|------|-----------|----------------|
| Credentials, history, plugins, cache | `~/.clause/profiles/<name>/.claude/` | `/root/.claude/` |
| Settings, first-run state | `~/.clause/profiles/<name>/.claude.json` | `/root/.claude.json` |
| Git configuration | `~/.clause/profiles/<name>/.gitconfig` | `/root/.gitconfig` |
| Workspace mappings | `~/.clause/clause.conf` | — |
| Workspace | `$PWD` (or `-w path`) | `/workspace/` |

All runtime state lives in `~/.clause/` and is created automatically on first run. Nothing in the clause repo needs to be gitignored for runtime data.

## Rebuilding

After changes to `Containerfile`:

```bash
clause -B
```

`--build` is profile-aware: if the specified profile has its own `Containerfile` under `~/.clause/profiles/<profile>/`, it builds the `clause-<profile>` image from that file; otherwise it builds the base `clause` image from the repo `Containerfile`.
