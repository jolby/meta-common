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
#   	$(SBCL_QL) --eval '(my-project.demo:run)'
#
#   # Custom test suite with output capture:
#   test-integration: check-quicklisp
#   	$(call capture-output,test-integration,$(SBCL_RUN) --eval '...')
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
#   ASDF_SOURCE_REGISTRY  Use source-registry tree scan (yes) or Quicklisp-only (no)
#                         (default: yes; set to no for faster startup)

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

# Base directory prefix for captured output files.
# Per-target capture goes to $(OUTPUT_DIR)<target>-LATEST.txt
OUTPUT_DIR ?= /tmp/$(subst /,-,$(PROJECT_SYSTEM))-
# Temp file for $(file ...) output — avoids shell quoting issues with --eval
TEST_EVAL_TMP ?= /tmp/$(subst /,-,$(PROJECT_SYSTEM))-test-eval-tmp.lisp

SBCL ?= sbcl
SBCL_HOME ?=
QL ?= $(HOME)/quicklisp/setup.lisp
CACHE_DIR ?= $(HOME)/.cache/common-lisp

# When set to "no", skip the ASDF source registry tree scan entirely —
# much faster startup when Quicklisp already knows all systems (demo,
# dev cycles).  Keep the default "yes" for CI/fresh-build scenarios
# where sibling repos may not be registered with Quicklisp.
ASDF_SOURCE_REGISTRY ?= yes

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

# ── Derived convenience variables ─────────────────────────────────────────
# SBCL_QL: lightweight — Quicklisp only, no ASDF source registry.
#   Use for demos and fast dev cycles (~1-2s startup).
SBCL_QL = $(SBCL_CMD) $(SBCL_FLAGS) --eval '(load "$(QL)")'

# SBCL_RUN: full — Quicklisp + ASDF source registry for auto-discovering
#   sibling repos.  Set ASDF_SOURCE_REGISTRY=no to use SBCL_QL instead.
ifeq ($(ASDF_SOURCE_REGISTRY),no)
  SBCL_RUN = $(SBCL_QL)
else
  SBCL_RUN = $(SBCL_CMD) $(SBCL_FLAGS) $(QL_BOOT) $(ASDF_BOOT)
endif

# ── Output capture macro ──────────────────────────────────────────────────
# Capture stdout+stderr of a command to a timestamped output file.
# Pipefail (.SHELLFLAGS) ensures the exit code of the wrapped command
# is preserved (not tee's).  Caller captures RC=$$? after invocation.
#
# Usage in project Makefiles:
#
#   test-special: check-quicklisp
#   	$(call capture-output,test-special,$(SBCL_RUN) --eval '...')
#   	@grep -E "Passed:|Failed:" $(OUTPUT_DIR)test-special-LATEST.txt | tail -1
#
#   demo-my-demo: check-quicklisp
#   	$(call capture-output,demo-my-demo,$(SBCL_QL) --eval '...')
#   	@echo "Output: $(OUTPUT_DIR)demo-my-demo-LATEST.txt"
#
# Output file: $(OUTPUT_DIR)<target>-LATEST.txt
#
# IMPORTANT: do not add a trailing blank line inside this define —
# the ; \ continuation on the call line appends to the last recipe line.
define capture-output
	@rm -f $(OUTPUT_DIR)$(1)-LATEST.txt
	@echo "=== $(PROJECT_SYSTEM) $(1) — `date -Iseconds` ===" | tee $(OUTPUT_DIR)$(1)-LATEST.txt
	@$(2) 2>&1 | tee -a $(OUTPUT_DIR)$(1)-LATEST.txt
endef

# ── Phony targets ─────────────────────────────────────────────────────────
.PHONY: help load force-load fast-load fast-force-load load-summary test test-summary clean \
        check-quicklisp check-sbcl \
        build install demo \
        test-eval \
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
	@echo "  make fast-load       - Same, but Quicklisp-only (~1-2s startup)"
	@echo "  make force-load     - Force-reload system (clears stale fasls)"
	@echo "  make load-summary   - Show warnings/errors from last load"
	@echo "  make demo-<name>    - Load system and run dev/<name>.lisp"
	@echo "  make test           - Run tests, capture output to $(TEST_OUTPUT)"
	@echo "  make test-summary   - Show test results from last run"
	@echo "  make test-package PKG=:pkg  - Run single test package"
	@echo "  make test-eval EVAL=\"(form)\"  - Run arbitrary test form"
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
	@echo "  ASDF_SOURCE_REGISTRY=no  Skip source registry scan for faster startup"
	@echo "  DYNAMIC_SPACE_SIZE=N   Heap size in MB (default: $(DYNAMIC_SPACE_SIZE))"

# ── Load ──────────────────────────────────────────────────────────────────
# Captures stderr+stdout so errors are always inspectable via
# make load-summary or direct inspection of $(LOAD_OUTPUT).
load: check-quicklisp check-sbcl
	$(call capture-output,load,$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM))' \
	  --eval '(format t "~%$(PROJECT_SYSTEM) loaded.~%")') ; \
	RC=$$?; \
	if grep -qE "caught (fatal )?(ERROR|WARNING)" $(LOAD_OUTPUT); then \
	  echo "ERROR: Load had errors — see $(LOAD_OUTPUT) for details"; \
	  exit 1; \
	fi; \
	exit $$RC

force-load: check-quicklisp check-sbcl
	@echo "Force-reloading $(PROJECT_SYSTEM)..."
	$(call capture-output,force-load,$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)') ; \
	RC=$$?; \
	if grep -qE "caught (fatal )?(ERROR|WARNING)" $(LOAD_OUTPUT); then \
	  echo "ERROR: Force-load had errors — see $(LOAD_OUTPUT) for details"; \
	  exit 1; \
	fi; \
	exit $$RC

# ── Fast load (Quicklisp-only, no ASDF source registry scan) ─────────────
# Same as load/force-load but uses SBCL_QL — ~1-2s startup instead of ~15s.
# Useful for dev cycles where sibling repos are already registered with
# Quicklisp (via ~/quicklisp/local-projects/ or ql:register-local-projects).
fast-load: check-quicklisp check-sbcl
	$(call capture-output,fast-load,$(SBCL_QL) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM))' \
	  --eval '(format t "~%$(PROJECT_SYSTEM) loaded.~%")') ; \
	RC=$$?; \
	if grep -qE "caught (fatal )?(ERROR|WARNING)" $(OUTPUT_DIR)fast-load-LATEST.txt; then \
	  echo "ERROR: Load had errors — see $(OUTPUT_DIR)fast-load-LATEST.txt for details"; \
	  exit 1; \
	fi; \
	exit $$RC

fast-force-load: check-quicklisp check-sbcl
	@echo "Fast force-reloading $(PROJECT_SYSTEM)..."
	$(call capture-output,fast-force-load,$(SBCL_QL) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)') ; \
	RC=$$?; \
	if grep -qE "caught (fatal )?(ERROR|WARNING)" $(OUTPUT_DIR)fast-force-load-LATEST.txt; then \
	  echo "ERROR: Force-load had errors — see $(OUTPUT_DIR)fast-force-load-LATEST.txt for details"; \
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
# Demo files use SBCL_QL (Quicklisp-only, no source registry scan) for
# fast startup.  Projects that need sibling repos should use $(SBCL_RUN).
demo-%: check-quicklisp check-sbcl
	@test -f "dev/$*.lisp" || { \
	  echo "Demo not found: dev/$*.lisp"; \
	  echo "Available demos:"; \
	  ls dev/*.lisp 2>/dev/null | sed 's/^/  /' || echo "  (none)"; \
	  exit 1; \
	}
	@$(SBCL_QL) \
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
	$(call capture-output,test,$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)' \
	  --eval '(ql:quickload :$(TEST_SYSTEM) :force t)' \
	  --eval '(asdf:test-system :$(PROJECT_SYSTEM))') ; \
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

# ── Targeted testing ──────────────────────────────────────────────────────
# Run a single test package via parachute.
#   make test-package PKG=:my-package
#   make test-package PKG=:my-package REPORT=interactive
PKG ?=
ifdef PKG
.PHONY: test-package
test-package: check-quicklisp check-sbcl
	$(call capture-output,test-package,$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)' \
	  --eval '(ql:quickload :$(TEST_SYSTEM) :force t)' \
	  --eval '(parachute:test $(PKG)$(if $(REPORT), :report (quote $(REPORT))))')
endif

# Run any test expression.  Works with any framework.
# Run any test expression.  Bypasses shell quoting via $(file).
# Works with single quotes, double quotes, any Lisp form.
#   make test-eval EVAL="(parachute:test :my-pkg 'some-sym)"
#   make test-eval EVAL="(format t \"hello\")"
#   make test-eval EVAL="(5am:run! :smoke)"
# Only enforce when test-eval is the actual target (not at parse time).
ifneq (,$(filter test-eval,$(MAKECMDGOALS)))
  ifeq (,$(EVAL))
    $(error EVAL is required. Usage: make test-eval EVAL="(form)")
  endif
endif
.PHONY: test-eval
test-eval: check-quicklisp check-sbcl
	$(file >$(TEST_EVAL_TMP),$(EVAL))
	$(call capture-output,test-eval,$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM) :force t)' \
	  --eval '(ql:quickload :$(TEST_SYSTEM) :force t)' \
	  --load $(TEST_EVAL_TMP))

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
