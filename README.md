# meta-common — Shared Build Infrastructure

Common Makefile, Lisp scripts, and shell tooling shared across
cogen-meta, IDEAS, and render-stack-meta projects.

→ **Full documentation:** [README.org](README.org)

## Quick Start

```bash
git submodule add git@github.com:jolby/meta-common.git .cl-make
git submodule update --init
```

```makefile
PROJECT_SYSTEM := my-project
include .cl-make/cl-project.mk
```

## Contents

| File | Purpose |
|------|---------|
| `README.org` | Full documentation — targets, variables, scripts, design |
| `cl-project.mk` | Common Lisp project Makefile |
| `fresh-build.lisp` | SBCL fresh-build with condition capture |
| `summarize-build.lisp` | Human-readable build output summarizer |
| `parse-build-log.lisp` | Build log parser |
| `start-mcp-server.lisp` | MCP server launcher |
| `git-stack.sh` | Batch git operations across all repos |
| `list-worktrees.sh` | List worktrees for all subprojects |
| `new-worktree.sh` | Create worktree with metadata symlinks |
| `remove-worktree.sh` | Remove worktree (with confirmation) |
| `check-unicode.sh` | Unicode character checker |

## Updating

```bash
cd .cl-make && git pull origin main
cd .. && git add .cl-make && git commit -m "Update .cl-make to latest"
```
