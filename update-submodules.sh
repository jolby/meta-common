#!/usr/bin/env bash
# update-submodules.sh — Pull latest meta-common into all .cl-make/ submodules
#
# Run from any meta-repo root.  Updates:
#   1. <meta-repo>/.cl-make/
#   2. <meta-repo>/repos/*/.cl-make/
#
# Usage:
#   ./.cl-make/update-submodules.sh              # pull only, show status
#   ./.cl-make/update-submodules.sh --commit     # pull + commit each bump
#   ./.cl-make/update-submodules.sh --dry-run    # show what would update
#
# With --commit, each repo with a submodule change gets a commit:
#   "chore: bump .cl-make/ to latest meta-common"

set -euo pipefail

META_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --commit) COMMIT=true ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Collect all .cl-make/ directories: meta-level + sub-repos
declare -a CL_MAKE_DIRS=()
CL_MAKE_DIRS+=("$META_DIR/.cl-make")
if [ -d "$META_DIR/repos" ]; then
  for repo in "$META_DIR"/repos/*/; do
    if [ -d "$repo/.cl-make" ]; then
      CL_MAKE_DIRS+=("$repo.cl-make")
    fi
  done
fi

UPDATED=0
SKIPPED=0
ERRORS=0

echo "=== meta-common update — $(date -Iseconds) ==="
echo "  Meta root: $META_DIR"
echo "  Targets:   ${#CL_MAKE_DIRS[@]} .cl-make/ instances"
echo ""

for cl_make in "${CL_MAKE_DIRS[@]}"; do
  # Determine parent repo name for display
  parent="$(dirname "$cl_make")"
  if [ "$parent" = "$META_DIR" ]; then
    name="$(basename "$META_DIR") (meta)"
  else
    name="repos/$(basename "$parent")"
  fi

  cd "$cl_make"

  # Get current and remote HEAD
  current=$(git rev-parse --short HEAD 2>/dev/null || echo "???")
  git fetch origin main 2>/dev/null || {
    echo -e "  ${RED}✗${NC} $name — fetch failed"
    ERRORS=$((ERRORS + 1))
    continue
  }
  remote=$(git rev-parse --short origin/main 2>/dev/null || echo "$current")

  if [ "$current" = "$remote" ]; then
    echo -e "  ${GREEN}✓${NC} $name — already at $current"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if $DRY_RUN; then
    echo -e "  ${YELLOW}→${NC} $name — $current → $remote (dry-run)"
    UPDATED=$((UPDATED + 1))
    continue
  fi

  # Pull
  if git pull origin main 2>&1 | grep -q '^Already up to date'; then
    echo -e "  ${GREEN}✓${NC} $name — already at $current"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo -e "  ${GREEN}↑${NC} $name — $current → $(git rev-parse --short HEAD)"

  # Commit the submodule bump in the parent repo
  if $COMMIT; then
    cd "$parent"
    if git diff --quiet .cl-make 2>/dev/null && \
       git diff --cached --quiet .cl-make 2>/dev/null; then
      : # no change to commit (submodule tracked differently?)
    else
      git add .cl-make
      git commit -m "chore: bump .cl-make/ to latest meta-common" 2>/dev/null || true
    fi
  fi

  UPDATED=$((UPDATED + 1))
done

echo ""
echo "=== Done: $UPDATED updated, $SKIPPED skipped, $ERRORS errors ==="

if $DRY_RUN; then
  echo "  (dry-run — use --commit to apply)"
elif ! $COMMIT; then
  echo "  (use --commit to auto-commit submodule bumps)"
fi
