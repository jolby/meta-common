#!/usr/bin/env bash
set -euo pipefail

# remove-worktree.sh - Remove a worktree (ASKS FOR CONFIRMATION)
#
# Usage: ./scripts/remove-worktree.sh <project> <branch-name>
# Example: ./scripts/remove-worktree.sh beads_rust feature-labels

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <project> <branch-name>"
    echo "Example: $0 beads_rust feature-labels"
    exit 1
fi

PROJECT="$1"
BRANCH="$2"
WORKTREE_NAME="${PROJECT}--${BRANCH}"
WORKTREE_PATH="${META_ROOT}/worktrees/${WORKTREE_NAME}"
REPO_PATH="${META_ROOT}/repos/${PROJECT}"

if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree not found at $WORKTREE_PATH"
    exit 1
fi

echo "Will remove worktree: $WORKTREE_PATH"
echo ""
echo "This will:"
echo "  - Remove the directory: $WORKTREE_PATH"
echo "  - Unregister the worktree from git"
echo ""
echo "It will NOT delete the branch '$BRANCH' from the repository."
echo ""
read -p "Are you sure? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "$REPO_PATH"
    git worktree remove "$WORKTREE_PATH"
    echo "Worktree removed."
else
    echo "Cancelled."
    exit 1
fi
