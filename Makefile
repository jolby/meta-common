# meta-common — Self-rolling Makefile
# ================================
# After pushing to meta-common, roll out to all dependent meta repos:
#
#   make rollout                     # default: all three meta repos
#   make META_PROJECT_DIRS=~/work/cogen-meta rollout  # single repo
#
# Override META_PROJECT_DIRS (colon-separated) to target specific repos.

META_PROJECT_DIRS ?= $(HOME)/work/cogen-meta $(HOME)/work/IDEAS $(HOME)/work/render-stack-meta

.PHONY: rollout
rollout:
	@fail=0; \
	for meta in $(META_PROJECT_DIRS); do \
	  echo "=== $$(basename $$meta) ==="; \
	  (cd "$$meta/.cl-make" && git pull origin main) || { echo "  FAIL: pull"; fail=1; continue; }; \
	  (cd "$$meta" && ./.cl-make/update-submodules.sh --commit) || { echo "  FAIL: update-submodules"; fail=1; }; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== Rollout complete ==="; else echo "=== Rollout completed with errors ==="; fi

.PHONY: status
status:
	@for meta in $(META_PROJECT_DIRS); do \
	  echo "=== $$(basename $$meta) ==="; \
	  head_sha=$$(cd "$$meta/.cl-make" && git rev-parse --short HEAD 2>/dev/null || echo "???"); \
	  remote_sha=$$(cd "$$meta/.cl-make" && git rev-parse --short origin/main 2>/dev/null || echo "???"); \
	  echo "  meta-level: $$head_sha (origin/main: $$remote_sha)"; \
	  count=$$(cd "$$meta" && ./.cl-make/update-submodules.sh --dry-run 2>&1 | grep -c '→' || true); \
	  echo "  repos behind: $$count"; \
	done
