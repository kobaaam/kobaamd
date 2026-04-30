#!/bin/bash
# git hooks をリポジトリの scripts/hooks/ から .git/hooks/ にシンボリックリンク
set -e
REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="$REPO_ROOT/scripts/hooks"
HOOKS_DST="$REPO_ROOT/.git/hooks"

for hook in pre-commit pre-push; do
    if [ -f "$HOOKS_SRC/$hook" ]; then
        ln -sf "$HOOKS_SRC/$hook" "$HOOKS_DST/$hook"
        chmod +x "$HOOKS_DST/$hook"
        echo "Installed $hook → .git/hooks/$hook"
    fi
done

echo "Done."
