# Agent Behavior
- Enter plan mode before executing any non-trivial task — i.e. anything touching multiple files, adding dependencies, or requiring more than a couple of steps. Skip planning only for single-file edits and direct questions.
- Do not write files outside the working directory, except temporary files in `/tmp`.
- Prefer bash for simple scripting. Reach for Python or another language only when bash is insufficient (complex data structures, non-trivial parsing, libraries).
- Fan out independent subtasks to parallel subagents by default. Serialize when subtasks depend on each other's output OR when multiple subtasks would write to the same working tree. If independence is unclear, treat them as dependent.
- Never take destructive or irreversible action without explicit confirmation from the user. This includes: writes to external data or schemas, deleting files outside the working tree, revoking access, force-pushing, hard resets, history rewrites on shared branches, and tearing down infrastructure.

## Git workflow for plan execution
When presenting a plan for work in a git repo, include the worktree question in the plan (or state the assumed choice) so it is settled at plan approval. Do not begin making changes before this is resolved.

0. If the working tree has uncommitted changes unrelated to the plan, ask how to handle them (stash, commit, or proceed) before starting.

### If yes (worktree):
1. Create a new worktree with a new branch based on the repo's default branch (e.g., `git worktree add ../<repo>-<feature> -b <branch> <default-branch>`).
2. Do all work in the worktree.
3. Commit in logical units as work progresses; each commit should build and pass tests where feasible. Squash on request only.
4. On plan completion:
   - Ensure all changes are committed.
   - Run the project's tests and linters (if present); do not proceed with failures unless the user approves.
   - Fetch and rebase the branch onto the latest default branch; resolve conflicts before proceeding.
   - Fast-forward merge into the default branch (`git checkout <default> && git merge --ff-only <branch>`).
   - Remove the worktree, then delete the branch (`git worktree remove <path>`, `git branch -d <branch>`).
5. If the rebase or fast-forward merge fails, stop and ask before forcing anything.

### If no (current branch):
1. Work directly on the currently checked-out branch.
2. Do not create branches or worktrees unless explicitly asked.
3. Commit in logical units as work progresses; each commit should build and pass tests where feasible.
4. Run the project's tests and linters (if present) before the final commit; report any failures.
5. Do not push unless asked.

### Commits
- Follow the repo's existing commit message convention if one is evident from `git log`; otherwise use concise imperative-mood messages (e.g., "Add retry logic to fetch client").
