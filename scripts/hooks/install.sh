#!/bin/bash
# Configure git to use scripts/hooks/ as the hook directory.
# This replaces the old approach of symlinking into .git/hooks/.
set -e
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

CURRENT="$(git config --local --get core.hooksPath || true)"
if [ "$CURRENT" = "scripts/hooks" ]; then
    echo "core.hooksPath is already set to scripts/hooks (idempotent)"
else
    git config --local core.hooksPath scripts/hooks
    echo "Set core.hooksPath = scripts/hooks"
fi

# Ensure hook scripts are executable
for hook in pre-commit pre-push; do
    if [ -f "scripts/hooks/$hook" ]; then
        chmod +x "scripts/hooks/$hook"
        echo "Made scripts/hooks/$hook executable"
    fi
done

echo "Done. Git hooks are now sourced from scripts/hooks/"
echo ""
echo "Note: If old symlinks remain in .git/hooks/, they will be ignored once core.hooksPath is set."
echo "You can optionally clean them up: rm .git/hooks/pre-commit .git/hooks/pre-push"
