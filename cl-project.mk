# cl-project.mk — Shared Common Lisp project Makefile
#
# Include this in each project's Makefile after setting PROJECT_SYSTEM:
#
#   PROJECT_SYSTEM := my-project
#   include .cl-make/cl-project.mk
#
# Full example with all overrides:
#
#   PROJECT_SYSTEM := my-project
#   TEST_SYSTEM := my-project/tests
#   DYNAMIC_SPACE_SIZE := 8096
#   CLEAN_EXTRA_PATTERNS := *.db *.db-journal
#   EXTRA_ASDF_DIRS := ../vendor/some-lib/
#   GOLDEN_PACKAGE := my-project.test
#   include .cl-make/cl-project.mk
#
#   # Project-specific targets go here
#   demo: check-quicklisp
#   	$(SBCL_RUN) --eval '(my-project.demo:run)'
#
# Standard targets provided:
#   help            Print this help
#   load            Quickload the system (for REPL exploration)
#   force-load      Force-reload system (clears stale fasls)
#   load-summary    Show warnings/errors from last load
#   test            Run tests, capture output, preserve exit code
#   test-summary    Show results from last test run
#   clean           Remove fasls from source tree + SBCL cache
#   fresh-build     Clear caches + build from scratch + capture conditions
#   summarize       Human-readable summary of latest fresh-build output
#   build-report    fresh-build + summarize (both passes)
#   demo-<name>     Load system and run dev/<name>.lisp
#   generate-goldens  Regenerate golden test files (requires GOLDEN_PACKAGE)
#
# Standard overrideable variables:
#   PROJECT_SYSTEM        ASDF system name (REQUIRED)
#   TEST_SYSTEM           ASDF test system (default: PROJECT_SYSTEM/tests)
#   TEST_FRAMEWORK        asdf, parachute, or fiveam (default: asdf)
#   EXTRA_ASDF_DIRS       Additional dirs to add to source registry
#   EXTRA_ASDF_TREES      Additional :tree entries for source registry
#   GOLDEN_PACKAGE        Package prefix for update-goldens (enables generate-goldens)
#   DYNAMIC_SPACE_SIZE    SBCL heap in MB (default: 4096)
#   CLEAN_EXTRA_PATTERNS  Extra globs for make clean (default: *.db *.db-journal)
#   BINARY_NAME           Binary output name (enables build/install targets)
#   INSTALL_DIR           Install destination (default: ~/.local/bin)
#   SBCL                  SBCL binary (default: sbcl)
#   SBCL_HOME             Custom SBCL_HOME for custom SBCL builds
#   QL                    Quicklisp setup.lisp path
#   SBCL_FLAGS            Additional SBCL flags

# ── Shell setup ───────────────────────────────────────────────────────────
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# ── Overrideable variables ────────────────────────────────────────────────
PROJECT_SYSTEM ?= $(error PROJECT_SYSTEM must be set before including cl-project.mk)
TEST_SYSTEM ?= $(PROJECT_SYSTEM)/tests
TEST_FRAMEWORK ?= asdf
EXTRA_ASDF_DIRS ?=
EXTRA_ASDF_TREES ?=
GOLDEN_PACKAGE ?=
DYNAMIC_SPACE_SIZE ?= 4096
CLEAN_EXTRA_PATTERNS ?= *.db *.db-journal
BINARY_NAME ?=
INSTALL_DIR ?= $(HOME)/.local/bin
TEST_OUTPUT ?= /tmp/$(subst /,-,$(PROJECT_SYSTEM))-test-LATEST.txt
LOAD_OUTPUT ?= /tmp/$(subst /,-,$(PROJECT_SYSTEM))-load-LATEST.txt

SBCL ?= sbcl
SBCL_HOME ?=
QL ?= $(HOME)/quicklisp/setup.lisp
CACHE_DIR ?= $(HOME)/.cache/common-lisp

# ── Project directory detection ───────────────────────────────────────────
# $(firstword $(MAKEFILE_LIST)) is the top-level Makefile that included us.
_PROJECT_MAKEFILE := $(firstword $(MAKEFILE_LIST))
PROJECT_DIR := $(abspath $(dir $(_PROJECT_MAKEFILE)))
PARENT_DIR := $(abspath $(PROJECT_DIR)/..)

# $(lastword $(MAKEFILE_LIST)) is this file (cl-project.mk).
# Scripts (fresh-build.lisp, summarize-build.lisp) are siblings in the
# same directory.  _CL_MK_DIR provides the path to them.
_CL_MK_SELF := $(lastword $(MAKEFILE_LIST))
_CL_MK_DIR := $(dir $(_CL_MK_SELF))

# ── Common SBCL flags ─────────────────────────────────────────────────────
SBCL_FLAGS ?= --dynamic-space-size $(DYNAMIC_SPACE_SIZE) --noinform \
  --no-userinit --no-sysinit --disable-debugger --non-interactive

# ── ASDF / Quicklisp boot ─────────────────────────────────────────────────
# Use asdf:initialize-source-registry with :tree on the parent directory
# (mcclim-render-stack pattern) to auto-discover sibling repos.
# Quicklisp handles everything else via :inherit-configuration.
ASDF_BOOT := --eval '(require :asdf)' \
  --eval "(asdf:initialize-source-registry \
    '(:source-registry \
      (:directory \#p\"$(PROJECT_DIR)/\") \
      (:tree \#p\"$(PARENT_DIR)/\") \
      :inherit-configuration))"

QL_BOOT := --eval '(load "$(QL)")'

# Extra ASDF dirs appended after the main registry setup
HASH := \#
ifdef EXTRA_ASDF_DIRS
  ASDF_BOOT += $(foreach d,$(EXTRA_ASDF_DIRS),--eval "(pushnew $(HASH)p\"$(d)\" asdf:*central-registry* :test (function equalp))")
endif

# Extra ASDF source trees (e.g., for dev/ directories in meta repos)
ifdef EXTRA_ASDF_TREES
  ASDF_BOOT += $(foreach t,$(EXTRA_ASDF_TREES),--eval "(pushnew \#p\"$(t)\" asdf:*central-registry* :test (function equalp))")
endif

# SBCL command with optional SBCL_HOME (for custom SBCL builds)
ifdef SBCL_HOME
  SBCL_CMD := env SBCL_HOME=$(SBCL_HOME) $(SBCL)
else
  SBCL_CMD := $(SBCL)
endif

# ── Derived convenience variable ──────────────────────────────────────────
SBCL_RUN = $(SBCL_CMD) $(SBCL_FLAGS) $(QL_BOOT) $(ASDF_BOOT)

# ── Phony targets ─────────────────────────────────────────────────────────
.PHONY: help load force-load load-summary test test-summary clean \
        check-quicklisp check-sbcl \
        build install demo \
        fresh-build summarize build-report

# Conditional phony targets
ifdef GOLDEN_PACKAGE
.PHONY: generate-goldens
endif

# ── Guards ────────────────────────────────────────────────────────────────
check-quicklisp:
	@test -f "$(QL)" || { \
	  echo "Quicklisp not found at $(QL)."; \
	  echo "Override: make QL=/path/to/quicklisp/setup.lisp"; \
	  exit 1; \
	}

check-sbcl:
	@command -v $(SBCL) >/dev/null 2>&1 || { \
	  echo "SBCL ($(SBCL)) not found. Override: make SBCL=/path/to/sbcl"; \
	  exit 1; \
	}

# ── Help ──────────────────────────────────────────────────────────────────
help:
	@echo "$(PROJECT_SYSTEM) — Development Makefile"
	@echo ""
	@echo "Standard targets (from cl-project.mk):"
	@echo "  make load           - Load system (for REPL exploration)"
	@echo "  make force-load     - Force-reload system (clears stale fasls)"
	@echo "  make load-summary   - Show warnings/errors from last load"
	@echo "  make demo-<name>    - Load system and run dev/<name>.lisp"
	@echo "  make test           - Run tests, capture output to $(TEST_OUTPUT)"
	@echo "  make test-summary   - Show test results from last run"
	@echo "  make clean          - Remove fasls and SBCL cache"
	@if [ -n "$(BINARY_NAME)" ]; then \
	  echo "  make build          - Build binary → bin/$(BINARY_NAME)"; \
	  echo "  make install        - Install to $(INSTALL_DIR)/$(BINARY_NAME)"; \
	fi
	@if [ -n "$(GOLDEN_PACKAGE)" ]; then \
	  echo "  make generate-goldens - Regenerate golden test files"; \
	fi
	@echo "  make fresh-build    - Clean build + structured condition capture"
	@echo "  make summarize      - Summarize latest fresh-build output"
	@echo "  make build-report   - fresh-build + summarize (both passes)"
	@echo ""
	@echo "Environment overrides:"
	@echo "  SBCL=<path>            Custom SBCL binary"
	@echo "  SBCL_HOME=<path>       SBCL_HOME for custom SBCL builds"
	@echo "  QL=<path>              Quicklisp setup.lisp"
	@echo "  DYNAMIC_SPACE_SIZE=N   Heap size in MB (default: $(DYNAMIC_SPACE_SIZE))"

# ── Load ──────────────────────────────────────────────────────────────────
# Captures stderr+stdout so errors are always inspectable via
# make load-summary or direct inspection of $(LOAD_OUTPUT).
load: check-quicklisp check-sbcl
	@rm -f $(LOAD_OUTPUT)
	@$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM))' \
	  --eval '(format t "~%$(PROJECT_SYSTEM) loaded.~%")' \
	  2>&1 | tee $(LOAD_OUTPUT); \
	RC=$$?; \
	if grep -qE "caught (fatal )?(ERROR|WARNING)" $(LOAD_OUTPUT); then \
	  echo "ERROR: Load had errors — see $(LOAD_OUTPUT) for details"; \
	  exit 1; \
	fi; \
	exit $$RC

force-load: check-quicklisp check-sbcl
	@echo "Force-reloading $(PROJECT_SYSTEM)..."
	@rm -f $(LOAD_OUTPUT)
	@$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)' \
	  2>&1 | tee $(LOAD_OUTPUT); \
	RC=$$?; \
	if grep -qE "caught (fatal )?(ERROR|WARNING)" $(LOAD_OUTPUT); then \
	  echo "ERROR: Force-load had errors — see $(LOAD_OUTPUT) for details"; \
	  exit 1; \
	fi; \
	exit $$RC

load-summary:
	@if [ -f $(LOAD_OUTPUT) ]; then \
	  grep -nE "^; (caught|WARNING|ERROR|READ error)" $(LOAD_OUTPUT) | tail -15; \
	  echo "---"; \
	  echo "Full output: $(LOAD_OUTPUT)"; \
	else \
	  echo "No load output at $(LOAD_OUTPUT). Run 'make load' first."; \
	fi

# ── Demo runner ───────────────────────────────────────────────────────────
# Usage: make demo-<name>  →  loads system then runs dev/<name>.lisp
# Example: make demo-sdl3  →  runs dev/sdl3.lisp
#
# Demo files receive the full SBCL_RUN boot (ASDF source registry +
# Quicklisp already set up), so they just need (ql:quickload ...)
# followed by their demo code.
demo-%: check-quicklisp check-sbcl
	@test -f "dev/$*.lisp" || { \
	  echo "Demo not found: dev/$*.lisp"; \
	  echo "Available demos:"; \
	  ls dev/*.lisp 2>/dev/null | sed 's/^/  /' || echo "  (none)"; \
	  exit 1; \
	}
	@$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM))' \
	  --load "dev/$*.lisp"

# ── Golden generation ─────────────────────────────────────────────────────
# Available only when GOLDEN_PACKAGE is set.
# Bootstraps or updates all golden files by running the test suite with
# *update-goldens* and *update-pixel-goldens* set to T.
ifdef GOLDEN_PACKAGE
generate-goldens: check-quicklisp check-sbcl
	@echo "Generating goldens for $(PROJECT_SYSTEM)..."
	@$(SBCL_RUN) \
	  --eval '(ql:quickload :$(TEST_SYSTEM) :force t)' \
	  --eval "(setf $(GOLDEN_PACKAGE):*update-goldens* t)" \
	  --eval "(setf $(GOLDEN_PACKAGE):*update-pixel-goldens* t)" \
	  --eval '(asdf:test-system :$(PROJECT_SYSTEM))' \
	  2>&1 | tee $(TEST_OUTPUT); \
	RC=$$?; \
	grep -E "Passed:|Failed:" $(TEST_OUTPUT) | tail -1; \
	echo "Goldens regenerated — review and commit test/goldens/"; \
	exit $$RC
endif

# ── Test ───────────────────────────────────────────────────────────────────
# Single SBCL invocation captures load warnings, compile errors, AND test
# output.  Stale output file deleted first so grep never sees old results.
# Exit code preserved via pipefail.
test: check-quicklisp check-sbcl
	@rm -f $(TEST_OUTPUT)
	@echo "=== $(PROJECT_SYSTEM) Tests — $$(date -Iseconds) ===" | tee $(TEST_OUTPUT)
	@$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)' \
	  --eval '(ql:quickload :$(TEST_SYSTEM) :force t)' \
	  --eval '(asdf:test-system :$(PROJECT_SYSTEM))' \
	  2>&1 | tee -a $(TEST_OUTPUT); \
	RC=$$?; \
	echo "" | tee -a $(TEST_OUTPUT); \
	echo "=== Exit: $$RC ===" | tee -a $(TEST_OUTPUT); \
	grep -E "Passed:|Failed:" $(TEST_OUTPUT) | tail -1; \
	if grep -q "failed to evaluate properly" $(TEST_OUTPUT); then \
	  echo "ERROR: Tests failed to evaluate — see $(TEST_OUTPUT) for details"; \
	  exit 1; \
	fi; \
	exit $$RC

test-summary:
	@grep -E "Suite:|Summary:|Passed:|Failed:|Skipped:|Plan:" $(TEST_OUTPUT) 2>/dev/null | tail -20 \
	  || echo "No test output at $(TEST_OUTPUT). Run 'make test' first."

# ── Clean ──────────────────────────────────────────────────────────────────
# SBCL caches fasls under ~/.cache/common-lisp/<version>/<full-absolute-path>
# so we match with the full PROJECT_DIR, not a path relative to HOME.
clean:
	@echo "Removing compiled fasls from source tree..."
	@find $(PROJECT_DIR) \( -name "*.fasl" -o -name "*.dfsl" \
	  -o -name "*.fas" -o -name "*.lib" -o -name "*.x86f" \
	  -o -name "*.amd64f" -o -name "*.lx64fsl" \) -exec rm -f {} \;
	@for pattern in $(CLEAN_EXTRA_PATTERNS); do \
	  find $(PROJECT_DIR) -name "$$pattern" -exec rm -f {} \;; \
	done
	@if [ -n "$(BINARY_NAME)" ]; then \
	  rm -f bin/$(BINARY_NAME) $(BINARY_NAME); \
	fi
	@echo "Removing SBCL fasl cache..."
	@rm -rf $(CACHE_DIR)/sbcl-*$(PROJECT_DIR)
	@echo "Done."

# ── Fresh build with structured condition capture ──────────────────────────
# Requires fresh-build.lisp and summarize-build.lisp in the same directory
# as this file (i.e., inside .cl-make/).

fresh-build: check-sbcl
	@test -f "$(_CL_MK_DIR)fresh-build.lisp" || { \
	  echo "fresh-build.lisp not found at $(_CL_MK_DIR)"; \
	  echo "Ensure .cl-make/ submodule is initialized: git submodule update --init"; \
	  exit 1; \
	}
	@$(SBCL) --script "$(_CL_MK_DIR)fresh-build.lisp" $(PROJECT_DIR)

summarize: check-sbcl
	@LATEST=$$(ls -t $(PROJECT_DIR)/tmp/fresh-build-*.lisp 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
	  echo "No fresh-build output found in $(PROJECT_DIR)/tmp/"; \
	  echo "Run 'make fresh-build' first."; \
	  exit 1; \
	fi; \
	$(SBCL) --script "$(_CL_MK_DIR)summarize-build.lisp" "$$LATEST"

# ── Binary build & install (available when BINARY_NAME is set) ────────────
# Projects that build a binary set BINARY_NAME before the include:
#   BINARY_NAME := csct
# The binary is built via asdf:make, moved to bin/<name>, and installed
# to ~/.local/bin/<name>.

build: force-load
	@if [ -z "$(BINARY_NAME)" ]; then \
	  echo "BINARY_NAME not set. Set BINARY_NAME := <name> before include to enable build."; \
	  exit 1; \
	fi
	@echo "Building $(PROJECT_SYSTEM) binary..."
	@$(SBCL_RUN) \
	  --eval '(asdf:make :$(PROJECT_SYSTEM))'
	@mkdir -p bin
	@if [ -f $(BINARY_NAME) ]; then mv -f $(BINARY_NAME) bin/$(BINARY_NAME); fi
	@if [ -f bin/$(BINARY_NAME) ]; then \
	  echo "Built: bin/$(BINARY_NAME) ($$(ls -lh bin/$(BINARY_NAME) | awk '{print $$5}'))"; \
	else \
	  echo "Build failed: no binary produced at bin/$(BINARY_NAME)"; \
	  exit 1; \
	fi

install: build
	@if [ -f bin/$(BINARY_NAME) ]; then \
	  mkdir -p $(INSTALL_DIR); \
	  cp -f bin/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME); \
	  echo "Installed to $(INSTALL_DIR)/$(BINARY_NAME)"; \
	else \
	  echo "No binary found. Run 'make build' first."; \
	  exit 1; \
	fi

build-report: fresh-build summarize
