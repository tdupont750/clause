When running git commit, always use single quotes around the commit message:
git commit -m 'your message here'
Never use double quotes for commit messages.

Never combine cd and git in a single compound command (e.g. avoid `cd foo && git commit`).
Run cd and git as separate commands.
