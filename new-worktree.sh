#!/usr/bin/env bash
set -euo pipefail

# new-worktree.sh - Create a worktree for a subproject with metadata symlinks
#
# Usage: ./scripts/new-worktree.sh <project> <branch-name>
# Example: ./scripts/new-worktree.sh beads_rust feature-labels
#
# Creates: worktrees/<project>--<branch-name>/
# Symlinks AGENTS.md and .beads/ from metadata/<project>/

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
METADATA_PATH="${META_ROOT}/metadata/${PROJECT}"

# Validate repo exists
if [[ ! -d "$REPO_PATH/.git" ]]; then
    echo "Error: Repository not found at $REPO_PATH"
    echo "Available projects:"
    ls -1 "${META_ROOT}/repos/" 2>/dev/null || echo "  (none yet)"
    exit 1
fi

# Validate metadata exists
if [[ ! -d "$METADATA_PATH" ]]; then
    echo "Error: Metadata directory not found at $METADATA_PATH"
    echo "Create it first with: mkdir -p $METADATA_PATH"
    exit 1
fi

# Check if worktree already exists
if [[ -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree already exists at $WORKTREE_PATH"
    exit 1
fi

echo "Creating worktree: $WORKTREE_NAME"
echo "  From: $REPO_PATH"
echo "  To:   $WORKTREE_PATH"
echo "  Branch: $BRANCH"

# Create worktree with new branch
cd "$REPO_PATH"
git worktree add "$WORKTREE_PATH" -b "$BRANCH"

# Calculate relative path from worktree to metadata
# worktrees/<project>--<branch>/ -> ../../metadata/<project>/
RELATIVE_METADATA="../../metadata/${PROJECT}"

# Create symlinks
cd "$WORKTREE_PATH"

if [[ -f "${METADATA_PATH}/AGENTS.md" ]]; then
    ln -s "${RELATIVE_METADATA}/AGENTS.md" AGENTS.md
    echo "  Symlinked: AGENTS.md"
fi

if [[ -d "${METADATA_PATH}/.beads" ]]; then
    ln -s "${RELATIVE_METADATA}/.beads" .beads
    echo "  Symlinked: .beads/"
fi

echo ""
echo "Worktree ready: $WORKTREE_PATH"
echo "To enter: cd $WORKTREE_PATH"
