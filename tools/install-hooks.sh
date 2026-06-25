#!/usr/bin/env bash
# Installs project git hooks from tools/hooks/ into .git/hooks/.

set -e

HOOKS_SRC="$(dirname "$0")/hooks"
HOOKS_DST="$(git rev-parse --show-toplevel)/.git/hooks"

for hook in "$HOOKS_SRC"/*; do
  name="$(basename "$hook")"
  dst="$HOOKS_DST/$name"
  cp "$hook" "$dst"
  chmod +x "$dst"
  echo "  Installed: $name → .git/hooks/$name"
done

echo "Done. Git hooks are active."
