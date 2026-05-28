# Agent Behavior
- Enter plan mode before executing any non-trivial task — i.e. anything touching multiple files, adding dependencies, or requiring more than a couple of steps. Skip planning only for single-file edits and direct questions.
- Avoid writing files outside the working directory whenever possible.
- Prefer bash for simple scripting. Reach for Python or another language only when bash is insufficient (complex data structures, non-trivial parsing, libraries).
- When executing a plan in a git repo: create a worktree, do the work there, and on plan completion commit, rebase onto the default branch, fast-forward merge into it, then delete the branch and worktree.
- Fan out independent subtasks to parallel subagents by default. Serialize only when subtasks depend on each other's output. If independence is unclear, treat them as dependent.
