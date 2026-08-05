# meta-common — Self-rolling Makefile
# ================================
# After pushing to meta-common, roll out to all dependent meta repos.
#
# Config (first wins):
#   1. META_REPOS env var:     META_REPOS="~/work/cogen-meta:~/work/IDEAS" make rollout
#   2. .meta-env file:         one path per line, same format as META_REPOS
#
# Targets:
#   make rollout    — push latest to all registered meta repos
#   make status     — show which repos are behind
#   make META_REPOS=~/work/cogen-meta rollout  — target a single repo

# ── Resolve META_REPOS from env var, .meta-env, or error ─────────────────

# Read .meta-env if it exists (strip comments and blank lines)
_META_ENV_FILE := $(wildcard .meta-env)
ifneq (,$(_META_ENV_FILE))
  _META_ENV_DIRS := $(shell grep -v '^\s*#' $(_META_ENV_FILE) | grep -v '^\s*$$')
endif

# META_REPOS env var takes precedence over .meta-env
ifeq (,$(META_REPOS))
  ifneq (,$(_META_ENV_DIRS))
    META_REPOS := $(_META_ENV_DIRS)
  endif
endif

# ── Guard ─────────────────────────────────────────────────────────────────
ifeq (,$(META_REPOS))
  $(error No meta repos configured. Set META_REPOS env var or create .meta-env. \
    Example: echo "$$HOME/work/cogen-meta" > .meta-env)
endif

.PHONY: rollout
rollout:
	@fail=0; \
	for meta in $(META_REPOS); do \
	  echo "=== $$(basename $$meta) ==="; \
	  (cd "$$meta/.cl-make" && git pull origin main) || { echo "  FAIL: pull"; fail=1; continue; }; \
	  (cd "$$meta" && ./.cl-make/update-submodules.sh --commit) || { echo "  FAIL: update-submodules"; fail=1; }; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== Rollout complete ==="; else echo "=== Rollout completed with errors ==="; fi

.PHONY: status
status:
	@for meta in $(META_REPOS); do \
	  echo "=== $$(basename $$meta) ==="; \
	  head_sha=$$(cd "$$meta/.cl-make" && git rev-parse --short HEAD 2>/dev/null || echo "???"); \
	  remote_sha=$$(cd "$$meta/.cl-make" && git rev-parse --short origin/main 2>/dev/null || echo "???"); \
	  echo "  meta-level: $$head_sha (origin/main: $$remote_sha)"; \
	  count=$$(cd "$$meta" && ./.cl-make/update-submodules.sh --dry-run 2>&1 | grep -c '→' || echo 0); \
	  echo "  repos behind: $$count"; \
	done
