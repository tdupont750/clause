# Clause

Meet Claude’s safety-conscious friend, **Clause**!

Clause mounts your working directory into a tiny container with its own copy of [Claude Code](https://claude.ai/code). Inside that container, Claude can do whatever it wants however it wants, while your host machine and all of its secrets stay safe. Clause supports persistent settings and credentials in named profiles that can use custom container images.

![Clause](images/clause_small.png)

## Why use Clause?

1. You should be running your agents inside a container. Stop raw-dogging the internet. You're going to catch something.

2. Clause makes it easy to develop inside of lightweight ephemeral containers with durable configuration; this provides convenient workspace isolation, effective security, and simple dependency management.

3. Best of all, Clause is just a Bash script. No frameworks, packages, runtimes, installs, or opinionated code. Change anything you like.

## Requirements

- [Podman](https://podman.io/) or [Docker](https://www.docker.com/) 

## Getting Started

Initialize once.

```bash
# 1. Make the script executable
chmod +x clause

# 2. Add the shell alias so you can run `clause` from any directory
./clause alias create

# 3. Reload your shell, or open a new terminal
source ~/.bashrc

# 4. Build the default container image
clause image build
```

Run anywhere.

```bash
# Navigate to your project 
cd ~/your-project

# Start Claude in this workspace
clause
```

## Usage

```
usage: clause [session options]               launch Claude (default)
       clause <command> ...                   manage clause, then exit

With no command, clause launches the profile bound to this workspace (default:
'default'). Point a workspace at a profile with `clause bind <profile>`.

session options (shape the launch; combine with any command):
  -t, --terminal          Launch bash instead of claude
  -w, --workspace <path>  Workspace directory (default: $PWD)
  -a, --args <value>      One-shot claude args (overrides args files)
  -e, --effort <level>    One-shot effort override: low|medium|high|xhigh|max
  -m, --model <name>      One-shot model override: opus|sonnet|haiku|<id>
  -y, --yes               Auto-answer yes to prompts (destructive
                          confirmations still require typing 'yes')
  -n, --no                Auto-answer no to all prompts

commands (then exit):
  config set [-l] <key> <value>  Set a config key: args|effort|model|mount
  config reset [-l] <key>        Reset a config key to its default
  config list                    Show workspace + profile config
  config help                    Explain every config key
  bind <profile>                 Bind this workspace to a profile (-p)
  bind --unset                   Remove this workspace's binding
  profile create <name>          Create a profile (seeded from default)
  profile reset <name>           Restore a profile's shipped config
  profile delete <name>          Delete a profile, its image and volume
  profile list                   List profiles
  image build                    Build the bound profile's image (-b)
  image suggest                  Print suggested Containerfile edits
  podman enable                  Enable nested podman for the profile
  podman disable                 Disable nested podman
  podman reset                   Reset the nested storage volume
  status                         Effective config for this directory

global (machine-wide setup):
  runtime <podman|docker>        Pin the container runtime
  runtime --unset                Clear the runtime override
  alias create                   Install the clause shell alias
  alias delete                   Remove the shell alias

  -h, --help                     Print this help
```

## Concepts

### Profiles

A profile is a folder under `~/.clause/profiles/<name>/` holding everything that should
outlive a session: Claude credentials, history and plugins, a `.gitconfig`, plus the
profile's own `Containerfile`, `args`, `effort`, and `model`. Each profile builds its own
image, `clause-<profile>`, so one profile can carry extra tooling without touching another. The
`default` profile is created on first run; add more with `clause profile create <name>`.

### Workspaces

A workspace is whatever directory you run `clause` in. It is bind-mounted into the
container at an encoded path (`/home/tom/projects/myapp` becomes
`/workspace/-home-tom-projects-myapp`) which is also the container cwd, so two projects
sharing a profile keep separate Claude history. Which profile a workspace uses is
recorded in `<workspace>/.clause/profile`, written by `clause bind <profile>`. There is
no central registry: the binding lives in the folder and travels with it.

### Ephemeral sessions

Every launch is a throwaway `--rm` container. Nothing inside it survives, and all state
is in bind mounts, so the blast radius is the workspace plus the profile folder.

### Layered config

Four knobs shape a launch: `args` is what gets appended to `claude`, `effort` and `model`
are the `--effort` level and `--model` name injected into those args, and `mount` pins the
container-side workspace path. Each resolves the same way, most specific first: a one-shot
flag, then `<workspace>/.clause/`, then the profile, then the shipped template (`mount` is
workspace-only, since it describes a folder rather than a profile). A workspace starts with
no config files and passes straight through; write one and it wins, even if you write it
empty, which is how you switch a knob off for a single directory. Profile files are always
seeded from the template, so a profile is never missing one.

`clause config set|reset [--local] <key>` writes them. `clause status` collapses all of
it into the single value a launch would use, and names the source of each.

### Nested podman

Agents often want to build an image or bring up a service container. Handing them the
host container engine would undo the point of the sandbox, so `clause` can instead run
podman *inside* the session.

Inner containers are rootless inside the session's own user namespace, with no access to
the host engine, so escaping one only lands you back in the jailed session user. Inner
images persist in a per-profile volume; everything else is still ephemeral. It is opt-in
per profile because it adds roughly 200 MB to the image and relaxes a few container
security options (more so under a Docker host, where Podman is recommended instead).

## Documentation

[Reference](docs/reference.md): every command, flag, config key, precedence rule, nested-podman detail, and the full state-to-path table.
