#!/bin/sh
# set-bg.sh — set terminal background from a Claude Code hook (podman -it).
#   set-bg.sh '#RRGGBB' | set-bg.sh reset
# Writes to /dev/pts/0 (the single session pty under podman -it).
# Always exits 0: exit 2 on UserPromptSubmit blocks the prompt.

TTY=/dev/pts/0
if [ -w "$TTY" ]; then
  if [ "$1" = "reset" ]; then
    printf '\033]111;\007' > "$TTY" 2>/dev/null
  else
    printf '\033]11;%s\007' "$1" > "$TTY" 2>/dev/null
  fi
fi
exit 0
