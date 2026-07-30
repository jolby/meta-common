# meta-common — Shared Build Infrastructure

Common Makefile, Lisp scripts, and shell tooling shared across
cogen-meta, IDEAS, and render-stack-meta projects.

## Usage

Add as a git submodule at `.cl-make/`:

```bash
git submodule add https://github.com/jolby/meta-common.git .cl-make
git submodule update --init
```

Sub-repo Makefiles include:

```makefile
PROJECT_SYSTEM := my-project
include .cl-make/cl-project.mk
```

Meta-repo shell scripts available at `.cl-make/git-stack.sh`, etc.

## Contents

| File | Purpose |
|------|---------|
| `cl-project.mk` | Common Lisp project Makefile (load, test, clean, fresh-build, etc.) |
| `fresh-build.lisp` | SBCL fresh-build script with condition capture |
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
