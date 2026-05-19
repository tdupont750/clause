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
  -a, --args <value>      One-shot claude args (overrides clause-args files)
  -t, --terminal          Launch bash instead of claude
  -w, --workspace <path>  Workspace directory (default: $PWD)

prompt options:
  -y, --yes               Auto-answer yes to all prompts
  -n, --no                Auto-answer no to all prompts

mapping (then exit):
  -m, --map               Add workspace→profile mapping
  -u, --unmap             Remove workspace→profile mapping
  -l, --list              Show current mapping and list all profiles
  -L, --list-all          List all workspace→profile mappings

profile management (then exit):
  -C, --create-profile        Create a new profile (Containerfile + clause-args seeded)
  -D, --delete-profile        Delete a profile and remove its mappings
  -R, --reset-containerfile   Overwrite profile Containerfile with default
  -S, --suggest-updates       Suggest Containerfile updates from sudo log

arguments (then exit):
  -A, --args-view                 Print effective claude args + source
      --args-set <value>          Write workspace .clause-args (this directory)
      --args-set-profile <value>  Write profile clause-args
                                  Default: --effort max --dangerously-skip-permissions

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

Profiles isolate Claude settings, credentials, history, and plugins. Each profile is a directory under `~/.clause/profiles/` with its own `.claude/`, `.claude.json`, `Containerfile`, and `clause-args`. The `default` profile is created automatically on first run.

```bash
# Create a profile (also adds a workspace→profile mapping)
clause work -C

# Use a profile
clause work

# Show current mapping and list all profiles
clause -l

# Delete a profile (also removes its workspace mappings and image)
clause work -D
```

### Per-profile Container Images

Every profile gets its own `Containerfile` (copied from `defaults/Containerfile` when the profile is created) and builds to a profile-specific image `clause-<profile>`.

```bash
# Edit ~/.clause/profiles/work/Containerfile as needed, then build
clause work -b

# Overwrite a profile's Containerfile with the default again
clause work -R
```

- `-b` / `--build` is profile-aware: it builds `clause-<profile>` from the profile's `Containerfile`. If a profile has no `Containerfile` (legacy profiles created before this change), it falls back to building the base `clause` image from the repo's default.
- `-R` / `--reset-containerfile` overwrites the profile's `Containerfile` with the current default.

### Claude args

The args appended to `claude` at launch come from one of three places, in this precedence:

1. **`-a, --args <string>`** — one-shot CLI override for this launch only.
2. **`$WORKSPACE/.clause-args`** — workspace-local override. Present (even empty) wins over the profile file. Manage with `--args-set <string>`.
3. **`$PROFILE_DIR/clause-args`** — profile default at `~/.clause/profiles/<profile>/clause-args`, seeded on profile creation. Manage with `--args-set-profile <string>`.

The seeded default content is:

```
--effort max --dangerously-skip-permissions
```

```bash
# One-shot override for this launch
clause work -a '--effort high'

# Print what would actually be used (and from where)
clause work -A

# Write workspace-local override
clause --args-set '--effort low'

# Write profile-wide default
clause work --args-set-profile '--effort max --dangerously-skip-permissions'
```

Args are ignored under `-t/--terminal` (bash mode passes no args). An empty `.clause-args` file means "no args" — the workspace explicitly opts out.

## Session Resume

If your profile is configured with a `SessionEnd` hook that writes the session ID to `.clause-session-id` in your workspace, the next time you run `clause` from that directory it will automatically resume where you left off. The `.clause-session-id` file is deleted as soon as it's consumed and is gitignored automatically in the clause repo.

To start a fresh session instead, delete `.clause-session-id` before launching.

The default `defaults/settings.json` no longer ships with a session hook — add one to your profile's `settings.json` if you want auto-resume:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "jq -r '.session_id' > /workspace/.clause-session-id" }
        ]
      }
    ]
  }
}
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
clause work -m

# Show the current mapping (plus all profiles)
clause -l

# Remove the current mapping
clause -u

# List all mappings
clause -L

# Skip prompts in scripts
clause work -y
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
| Containerfile (per profile) | `~/.clause/profiles/<name>/Containerfile` | — (build input) |
| Claude args (profile) | `~/.clause/profiles/<name>/clause-args` | — (read by `clause` on launch) |
| Claude args (workspace override) | `<workspace>/.clause-args` | — (read by `clause` on launch) |
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
