#!/bin/bash
# git-stack.sh — Git operations across all cogen repos
#
# Usage: ./scripts/git-stack.sh <command> [args]
#
# Commands:
#   status          Show git status for all repos
#   log [n]         Show last n commits (default: 5)
#   push            Push all repos to origin
#   pull            Pull all repos from origin
#   dirty           Show which repos have uncommitted changes
#   sync            Sync all repos (pull then push)
#   summary         Summary of all repos (branch, commits ahead/behind)
#   commits <msg>   Commit all changes in all repos with message
#
# Examples:
#   ./scripts/git-stack.sh status
#   ./scripts/git-stack.sh log 10
#   ./scripts/git-stack.sh push

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repos to manage (relative to META_DIR)
# Automatically discovers git repos under repos/ directory
# plus the meta repo itself (.) 
declare -a REPOS
REPOS=(".")

# Auto-discover repos under repos/ directory
if [ -d "$META_DIR/repos" ]; then
  for dir in "$META_DIR"/repos/*/; do
    if [ -d "$dir/.git" ]; then
      # Get path relative to META_DIR (e.g., "repos/beadwork")
      rel_path="repos/$(basename "$dir")"
      REPOS+=("$rel_path")
    fi
  done
fi

# Helper: Print section header
print_header() {
  echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

# Helper: Execute git command in repo
run_in_repo() {
  local repo="$1"
  local cmd="$2"
  local name=$(basename "$repo")

  if [ "$repo" = "." ]; then
    name="cogen-meta"
  fi

  echo -e "\n${YELLOW}▶ $name${NC}"
  cd "$META_DIR/$repo" || return
  eval "$cmd"
}

# Command: status
cmd_status() {
  print_header "Git Status"
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      run_in_repo "$repo" "git status --short || true"
    fi
  done
}

# Command: log
cmd_log() {
  local n="${1:-5}"
  print_header "Last $n Commits"
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      run_in_repo "$repo" "git log --oneline -$n"
    fi
  done
}

# Command: dirty
cmd_dirty() {
  print_header "Dirty Repositories"
  local dirty_count=0
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      cd "$META_DIR/$repo"
      if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        local name=$(basename "$repo")
        [ "$repo" = "." ] && name="cogen-meta"
        echo -e "${RED}✗ $name has uncommitted changes${NC}"
        dirty_count=$((dirty_count + 1))
      fi
    fi
  done

  if [ $dirty_count -eq 0 ]; then
    echo -e "${GREEN}✓ All repositories are clean${NC}"
  else
    echo -e "\n${YELLOW}$dirty_count repo(s) need attention${NC}"
  fi
}

# Command: push
cmd_push() {
  print_header "Pushing to Origin"
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      run_in_repo "$repo" "git push origin $(git branch --show-current)"
    fi
  done
}

# Command: pull
cmd_pull() {
  print_header "Pulling from Origin"
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      run_in_repo "$repo" "git pull origin $(git branch --show-current)"
    fi
  done
}

# Command: sync (pull then push)
cmd_sync() {
  cmd_pull
  echo ""
  cmd_push
}

# Command: summary
cmd_summary() {
  print_header "Repository Summary"

  # Measure max repo name width for dynamic column sizing
  local max_name=10
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      local name=$(basename "$repo")
      [ "$repo" = "." ] && name="cogen-meta"
      if [ ${#name} -gt $max_name ]; then
        max_name=${#name}
      fi
    fi
  done
  local col_repo=$((max_name + 2))
  local separator_width=$((col_repo + 15 + 10 + 10))

  printf "%-${col_repo}s %-15s %-10s %-10s\n" "Repository" "Branch" "Ahead" "Behind"
  printf "%${separator_width}s\n" "" | tr ' ' '-'

  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      cd "$META_DIR/$repo"
      local name=$(basename "$repo")
      [ "$repo" = "." ] && name="cogen-meta"
      local branch=$(git branch --show-current 2>/dev/null || echo "N/A")

      # Use left-right count: output is "behind\tahead"
      local lr=$(git rev-list --left-right --count @{u}...HEAD 2>/dev/null || echo "0\t0")
      local behind=$(echo "$lr" | cut -f1)
      local ahead=$(echo "$lr" | cut -f2)

      printf "%-${col_repo}s %-15s %-10s %-10s\n" "$name" "$branch" "$ahead" "$behind"
    fi
  done
}

# Command: commits
cmd_commits() {
  local msg="$1"
  if [ -z "$msg" ]; then
    echo "Error: Commit message required"
    echo "Usage: $0 commits 'Your commit message'"
    exit 1
  fi

  print_header "Committing All Changes"
  for repo in "${REPOS[@]}"; do
    if [ -d "$META_DIR/$repo/.git" ]; then
      cd "$META_DIR/$repo"
      if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        run_in_repo "$repo" "git add -A && git commit -m '$msg'"
      fi
    fi
  done
}

# Main command dispatcher
case "${1:-}" in
  status)
    cmd_status
    ;;
  log)
    cmd_log "$2"
    ;;
  push)
    cmd_push
    ;;
  pull)
    cmd_pull
    ;;
  dirty)
    cmd_dirty
    ;;
  sync)
    cmd_sync
    ;;
  summary)
    cmd_summary
    ;;
  commits)
    cmd_commits "$2"
    ;;
  *)
    echo "Git Stack Manager - Manage all cogen repositories"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  status              Show git status for all repos"
    echo "  log [n]             Show last n commits (default: 5)"
    echo "  dirty               Show repos with uncommitted changes"
    echo "  summary             Show branch and sync status for all repos"
    echo "  pull                Pull all repos from origin"
    echo "  push                Push all repos to origin"
    echo "  sync                Pull then push all repos"
    echo "  commits <msg>       Commit all changes with message"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 log 10"
    echo "  $0 sync"
    echo "  $0 commits 'Fix bug in core loop'"
    exit 1
    ;;
esac
