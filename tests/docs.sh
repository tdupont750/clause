#!/usr/bin/env bash
# Documentation drift checks.
#
# Two things the docs promise are kept in sync by hand, which is exactly where
# they have drifted before, so they are checked by machine instead:
#
#   1. README.md's usage block matches `./clause -h` byte for byte.
#   2. Every key the shipped settings.json sets is named in docs/reference.md.
#
# Run from anywhere: `tests/docs.sh`. Exits 0 when both pass, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

# ── 1. README usage block vs ./clause -h ────────────────────────────────────

# The fenced block that follows the "## Usage" heading, fences excluded.
readme_usage() {
  awk '
    /^## Usage$/ { seen = 1; next }
    seen && /^```/ { if (inblock) exit; inblock = 1; next }
    inblock
  ' README.md
}

if diff -u <(readme_usage) <(./clause -h); then
  echo "ok: README usage block matches ./clause -h"
else
  echo "FAIL: README.md's usage block has drifted from ./clause -h (left: README, right: -h)" >&2
  fail=1
fi

# ── 2. settings.json keys vs docs/reference.md ──────────────────────────────

# JSON plumbing and hook event names: structure, not settings, so the docs
# describe what the hooks do rather than naming each event.
skip_key() {
  case "$1" in
    hooks|type|command) return 0 ;;
    SessionStart|UserPromptSubmit|PostToolUse|Notification) return 0 ;;
    Stop|StopFailure|SessionEnd) return 0 ;;
    *) return 1 ;;
  esac
}

# Object keys, at any depth. The pattern deliberately excludes names holding
# '-', '@' or '.' (plugin ids, hook commands), which are values in disguise.
settings_keys() {
  grep -o '"[A-Za-z][A-Za-z0-9]*"[[:space:]]*:' default/.claude/settings.json \
    | tr -d '":' | tr -d '[:blank:]' | sort -u
}

# A loose substring match: this is an alarm for keys added to the template and
# never written up, not a check of how well each one is described.
undocumented=()
while IFS= read -r key; do
  skip_key "$key" && continue
  grep -qF -- "$key" docs/reference.md || undocumented+=("$key")
done < <(settings_keys)

if [[ ${#undocumented[@]} -eq 0 ]]; then
  echo "ok: every settings.json key is named in docs/reference.md"
else
  printf 'FAIL: settings.json keys missing from docs/reference.md: %s\n' \
    "${undocumented[*]}" >&2
  fail=1
fi

exit "$fail"
