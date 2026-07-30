#!/usr/bin/env bash
set -euo pipefail

# list-worktrees.sh - List all worktrees for all subprojects

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Worktrees by Project ==="
echo ""

for project_dir in "${META_ROOT}/repos/"*/; do
    if [[ -d "$project_dir" ]]; then
        project=$(basename "$project_dir")
        echo "[$project]"
        cd "$project_dir"
        git worktree list --porcelain 2>/dev/null | grep -E "^worktree " | sed 's/worktree /  /' || echo "  (no worktrees)"
        echo ""
    fi
done
