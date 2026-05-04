# Clause

Meet Claude’s safety-conscious friend, Clause!

Clause mounts your working directory into a tiny container with its own copy of [Claude Code](https://claude.ai/code). Inside that container, Claude can do whatever it wants however it wants, while your host machine and all of its secrets stay safe. Clause supports persistent settings and credentials in named profiles that can use custom container images.

![Clause](images/clause_small.png)

## Why use Clause?

1. You should be running your agents inside a container. Stop raw-dogging the internet. You're going to catch something.

2. Clause is just a single Bash script. No frameworks, packages, runtimes, installs, or opinionated code. Change anything you like.

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
clause -b
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
  -w, --workspace <path>  Workspace directory (default: $PWD)
  -s, --new-session       Start a new session (skip auto-resume)
  -t, --terminal          Launch bash instead of claude
  -d, --dangerous         Pass --dangerously-skip-permissions to claude

prompt options:
  -y, --yes               Auto-answer yes to all prompts
  -n, --no                Auto-answer no to all prompts

mapping management (then exit):
  -a, --add               Add workspace→profile mapping
  -m, --mapping           Show workspace→profile mapping for current workspace
  -r, --remove            Remove workspace→profile mapping
  -l, --list              List all workspace→profile mappings

profile management (then exit):
  --profile-create        Create a new profile scaffold and add mapping
  --profile-delete        Delete a profile and remove its mappings
  --image-create          Copy default Containerfile into profile directory
  --image-delete          Delete profile Containerfile and container image
  --profile-suggest       Suggest Containerfile updates from sudo log

alias management (then exit):
  --alias-create          Add clause alias to .bashrc and/or .zshrc
  --alias-delete          Remove clause alias from .bashrc and/or .zshrc

runtime management (then exit):
  --runtime-set <value>   Set container runtime override (podman or docker)
  --runtime-remove        Remove container runtime override

other:
  -b, --build             Build the container image
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
clause work --image-create

# Edit ~/.clause/profiles/work/Containerfile as needed, then build
clause work -b

# Remove the profile's Containerfile and delete the clause-work image
clause work --image-delete
```

- `--image-create` — copies the default `Containerfile` into `~/.clause/profiles/<profile>/Containerfile`.
- `--image-delete` — removes the profile's `Containerfile` and deletes the `clause-<profile>` container image.
- `-b` / `--build` is profile-aware: if the active profile has a `Containerfile`, it builds `clause-<profile>`; otherwise it builds the base `clause` image.

## Session Resume

When a Claude session ends, the session ID is saved to `.clause-session-id` in your workspace. The next time you run `clause` from that directory it will automatically resume where you left off.

To start a fresh session instead:

```bash
clause -s
```

The `.clause-session-id` file is deleted as soon as it's consumed and is gitignored automatically in the clause repo.

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
| Credentials, history, plugins, cache | `~/.clause/profiles/<name>/.claude/` | `/home/claude/.claude/` |
| Settings, first-run state | `~/.clause/profiles/<name>/.claude.json` | `/home/claude/.claude.json` |
| Git configuration | `~/.clause/profiles/<name>/.gitconfig` | `/home/claude/.gitconfig` |
| sudo activity log | `~/.clause/profiles/<name>/.claude/clause-sudo.log` | `/home/claude/.claude/clause-sudo.log` |
| Workspace mappings | `~/.clause/clause.conf` | — |
| Workspace | `$PWD` (or `-w path`) | `/workspace/` |

All runtime state lives in `~/.clause/` and is created automatically on first run. Nothing in the clause repo needs to be gitignored for runtime data.

## Rebuilding

After changes to `Containerfile`:

```bash
clause -b
```

`--build` is profile-aware: if the specified profile has its own `Containerfile` under `~/.clause/profiles/<profile>/`, it builds the `clause-<profile>` image from that file; otherwise it builds the base `clause` image from the repo `Containerfile`.
