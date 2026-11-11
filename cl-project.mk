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
#   BUILD_SYSTEM          ASDF system holding program-op (default: PROJECT_SYSTEM)
#   TEST_FRAMEWORK        VESTIGIAL: nothing reads it.  The test targets call
#                         Parachute directly, which is the only framework
#                         test-verdict.sh can judge a result from (bd-phe); a
#                         fiveam project converts rather than switches this.
#   EXTRA_ASDF_DIRS       Additional dirs to add to source registry
#   EXTRA_ASDF_TREES      Additional :tree entries for source registry
#   GOLDEN_PACKAGE        Package prefix for update-goldens (enables generate-goldens)
#   DYNAMIC_SPACE_SIZE    SBCL heap in MB (default: 4096)
#   CLEAN_EXTRA_PATTERNS  Extra globs for make clean (default: *.db *.db-journal)
#   BINARY_NAME           Binary output name (enables build/install targets)
#   BINARY_PATH           Staging dir for built binary (default: bin)
#   BINARY_BUILD_PATH     Where asdf:make drops the raw binary (default: BINARY_NAME)
#   INSTALL_DIR           Install destination (default: ~/.local/bin)
#   SBCL                  SBCL binary (default: sbcl)
#   SBCL_HOME             Custom SBCL_HOME for custom SBCL builds
#   QL                    Quicklisp setup.lisp path
#   ASDF_SOURCE_REGISTRY  Use source-registry tree scan (yes) or Quicklisp-only (no)
#                         (default: no — fast startup; set yes for CI/fresh-build)

# ── Shell setup ───────────────────────────────────────────────────────────
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# ── Overrideable variables ────────────────────────────────────────────────
PROJECT_SYSTEM ?= $(error PROJECT_SYSTEM must be set before including cl-project.mk)
TEST_SYSTEM ?= $(PROJECT_SYSTEM)/tests
BUILD_SYSTEM ?= $(PROJECT_SYSTEM)
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
# Logs for the two targets that do not follow the TEST_OUTPUT name.  Must
# match what capture-output writes, or the verdict reads a stale file.
TEST_PACKAGE_OUTPUT ?= $(OUTPUT_DIR)test-package-LATEST.txt
TEST_EVAL_OUTPUT ?= $(OUTPUT_DIR)test-eval-LATEST.txt
# Temp file for $(file ...) output — avoids shell quoting issues with --eval
TEST_EVAL_TMP ?= /tmp/$(subst /,-,$(PROJECT_SYSTEM))-test-eval-tmp.lisp

SBCL ?= sbcl
SBCL_HOME ?=
QL ?= $(HOME)/quicklisp/setup.lisp
CACHE_DIR ?= $(HOME)/.cache/common-lisp

# When set to "no", skip the ASDF source registry tree scan entirely —
# much faster startup when Quicklisp already knows all systems (demo,
# dev cycles).  Keep the default "no" for fast 1-2s startup in everyday
# use.  Set to "yes" for CI/fresh-build where sibling repos may not be
# registered with Quicklisp.
ASDF_SOURCE_REGISTRY ?= no

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

# ── Build info (version.sexp pattern) ──────────────────────────────────────
# Generated into BUILD_INFO_FILE before every load/build so Lisp load-time
# forms (see e.g. src/build-info.lisp) can bake the current repo state into
# the image. The file is regenerated on every make run — do NOT commit it.
#
# Disable by setting BUILD_INFO_FORM := (empty) in the project Makefile.
GIT ?= git
BUILD_GIT_SHA      ?= $(shell $(GIT) -C $(PROJECT_DIR) rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_GIT_SHA_FULL ?= $(shell $(GIT) -C $(PROJECT_DIR) rev-parse HEAD 2>/dev/null || echo unknown)
BUILD_GIT_BRANCH   ?= $(shell $(GIT) -C $(PROJECT_DIR) rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
BUILD_GIT_DIRTY    ?= $(shell test -n "$$($(GIT) -C $(PROJECT_DIR) status --porcelain 2>/dev/null)" && echo dirty || echo clean)
# Semantic version: extracted from the .asd (:version slot). Override
# PROJECT_VERSION in the project Makefile if the .asd lives elsewhere or
# uses another convention.
_ASD_VERSION := $(shell grep -m1 -oE ':version +"[^"]*"' $(PROJECT_DIR)/$(PROJECT_SYSTEM).asd 2>/dev/null | sed -E 's/.*"([^"]*)".*/\1/')
PROJECT_VERSION ?= $(or $(_ASD_VERSION),0.0.0)
BUILD_INFO_FILE ?= $(PROJECT_DIR)/build-info.sexp
BUILD_INFO_FORM  ?= (:version "$(PROJECT_VERSION)" :git-sha "$(BUILD_GIT_SHA)" :git-branch "$(BUILD_GIT_BRANCH)" :git-dirty "$(BUILD_GIT_DIRTY)")

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
#   sibling repos.  Set ASDF_SOURCE_REGISTRY=yes for full registry.
ifeq ($(ASDF_SOURCE_REGISTRY),no)
  SBCL_RUN = $(SBCL_QL)
else
  SBCL_RUN = $(SBCL_CMD) $(SBCL_FLAGS) $(QL_BOOT) $(ASDF_BOOT)
endif

# ── Gate receipts (bd-sbf) ────────────────────────────────────────────────
# A gate whose declared inputs are unchanged since its last GREEN run must not
# run again, and must still leave the log a reader inspects.  The receipt tool
# and the invariants it enforces are documented in gate-receipt.sh.
#
# Shape: each cached gate keeps its recipe verbatim under <gate>-uncached and
# gains a one-line wrapper.  On a miss the target therefore behaves EXACTLY as
# it did before receipts existed (same capture-output, same -LATEST.txt, same
# verdict), so receipts cannot move a verdict through a changed recipe.
#
# Inputs are declared per gate as GATE_INPUTS_<gate>.  The default is the WHOLE
# project: a narrower default ("src test data *.asd") was measured to miss a
# root-level test file, which is a false hit — the one failure a receipt must
# never have.  Wide is cheap here (a few hundred files); a project with a large
# generated tree declares it in GATE_EXCLUDES instead of narrowing the inputs.
#
#   make cache-status        what is cached, and where each log lives
#   make cache-clean         drop every receipt (GATE=<name> for one)
#   make FORCE=1 <gate>      re-run even on a matching receipt
#   make gate-selftest       prove the tool still honours its invariants
#   make test-receipts       prove the wiring below end to end
GATE_RECEIPT ?= $(abspath $(_CL_MK_DIR)gate-receipt.sh)
GATE_CACHE_DIR ?= $(PROJECT_DIR)/.gate-cache
# Bump to invalidate every receipt in this project (digest format change).
GATE_RECEIPT_VERSION ?= 1
# The recipe and the shared make layer are always inputs: editing either can
# change what a gate does, so it must change the digest.
GATE_INPUTS_ALWAYS ?= Makefile .cl-make
GATE_INPUTS_DEFAULT ?= .
# Extra basename globs pruned from every walk.  A glob WITH A SLASH is a path
# (dart/build prunes exactly that tree, not every directory called build).
GATE_EXCLUDES ?=
GATE_STAMPS_ALWAYS ?=
# Sibling repos are inputs: ASDF loads them through (:tree PARENT_DIR), so a
# changed sibling checkout must invalidate this project's receipts.
GATE_RECEIPT_SIBLINGS ?= $(PARENT_DIR)
GATE_RECEIPT_SIBLINGS_ARG = $(if $(strip $(GATE_RECEIPT_SIBLINGS)),--siblings '$(GATE_RECEIPT_SIBLINGS)',--no-siblings)
# Command-line variants of a gate: `PKG=:a` and `PKG=:b` write the same log
# path, so they MUST be distinguished by the digest or a hit returns the other
# run's verdict.  Exported so a makefile-defined default is visible too.
# Command-line variants and other overrides that change WHAT a gate examines or
# HOW it decides.  Makefile-DEFINED settings are already covered (the Makefile
# is an input), so this list exists for what can be typed on the command line:
#   PKG/REPORT  which test package, and its report mode
#   EVAL        the test form itself
#   DYNAMIC_SPACE_SIZE  the heap a gate runs in (a smaller heap turns a pass
#                       into an out-of-memory failure)
# A project adds its own selectors with `GATE_STAMP_ENVS += RP_SCENES` and
# `export RP_SCENES`.  The rule: if it can be overridden on the command line and
# it changes the gate, it belongs here.
GATE_STAMP_ENVS ?= PKG REPORT EVAL DYNAMIC_SPACE_SIZE
export PKG REPORT EVAL DYNAMIC_SPACE_SIZE

# The one-line wrapper a cached gate's recipe starts with.  One line on
# purpose: a multi-line define would split the recipe and lose the command.
# Stamp values are QUOTED one by one (GATE_STAMPS_<gate> = flutter=$(shell ...)
# produces a value with spaces, and an unquoted one would sheer into several
# argv words).
gate-receipt-prefix = $(GATE_RECEIPT) run $(1) --root '$(PROJECT_DIR)' --cache '$(GATE_CACHE_DIR)' --cache-version $(GATE_RECEIPT_VERSION) --log '$(2)' $(addprefix --input ,$(GATE_INPUTS_ALWAYS) $(or $(GATE_INPUTS_$(1)),$(GATE_INPUTS_DEFAULT))) $(addprefix --exclude ,$(GATE_EXCLUDES) $(or $(GATE_EXCLUDES_$(1)),)) $(foreach st,$(GATE_STAMPS_ALWAYS) $(or $(GATE_STAMPS_$(1)),),--stamp '$(st)') $(addprefix --stamp-env ,$(GATE_STAMP_ENVS)) --sbcl '$(SBCL)' $(GATE_RECEIPT_SIBLINGS_ARG) --

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

# ── Honest recompilation (bd-fyv) ────────────────────────────────────────
# (ql:quickload :sys :force t) registers the system and silently DISCARDS :force:
# Quicklisp's lambda list ends in &allow-other-keys, so the keyword is accepted and
# dropped, and ASDF then compiles only what it thinks is stale. That is how two real
# defects -- a docstring that broke HARNESS-CLOSE, and (MAP 'fn vector) -- shipped
# through a green `make test`: the run was green against a FASL that no longer matched
# its source.
#
# Registering is Quicklisp's job and compiling is ASDF's, so a target that promises a
# recompile asks for both:
#
#   $(call force-forms,cogen-tui)  →  --eval '(ql:quickload :cogen-tui)'
#                                     --eval '(asdf:load-system :cogen-tui :force t)'
#
# Used by force-load, fast-force-load, test, test-package, test-eval, generate-goldens
# and build. Loading starts at ~1s warm; forcing a project this size costs a few seconds
# of compile, which is the price of the report meaning what it says.
#
# A project whose DEPENDENCY tree emits compile warnings that ASDF treats as a failed
# compile -- CFFI's claw-generated bindings are the known case -- can downgrade that
# decision for the load, because a dependency's warning is not this project's bug:
#
#   LOAD_FORCE_EXTRA := --eval '(setf asdf:*compile-file-failure-behaviour* :warn)'
#
# `make lint` still covers the project's own code: it greps the compile log for
# undefined symbols, which is what bd-a8r's detector is, and the suite still runs.
LOAD_FORCE_EXTRA ?=
force-forms = $(LOAD_FORCE_EXTRA) --eval '(ql:quickload :$(1))' \
              --eval '(asdf:load-system :$(1) :force t)'

# ── Phony targets ─────────────────────────────────────────────────────────
.PHONY: help load force-load fast-load fast-force-load load-summary test test-summary clean \
        check-quicklisp check-sbcl \
        build install demo build-info \
        test-eval test-trust lint test-receipts \
        test-uncached test-eval-uncached cache-status cache-clean gate-selftest \
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
	@echo "  make test-trust     - Self-check that the test verdict can be trusted"	@echo "  make test-package PKG=:pkg  - Run single test package (dots or slashes in the name both work)"
	@echo "  make test-eval EVAL=\"(form)\"  - Run arbitrary test form"
	@echo "  make lint           - Fail on undefined-symbol warnings from src/ (not part of test)"
	@echo "  make cache-status   - What gate receipts are cached (VERBOSE=1 for detail)"
	@echo "  make cache-clean    - Drop every gate receipt (GATE=<name> for one)"
	@echo "  make gate-selftest  - Prove the receipt tool still honours its invariants"	@echo ""
	@echo "Gates are receipted: a second run with unchanged inputs restores the log"
	@echo "instead of running (FORCE=1 to override, make cache-clean to reset)."
	@echo "  make clean          - Remove fasls and SBCL cache"
	@if [ -n "$(BINARY_NAME)" ]; then \
	  echo "  make build          - Build binary → $(BINARY_PATH)/$(BINARY_NAME)"; \
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
	@echo "  ASDF_SOURCE_REGISTRY=yes  Enable source registry scan (for CI/fresh-build)"
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

build-info:
	@printf '%s\n' '$(BUILD_INFO_FORM)' > $(BUILD_INFO_FILE)
	@echo "  build-info: $(BUILD_INFO_FILE)  ($(PROJECT_VERSION) @ $(BUILD_GIT_SHA), $(BUILD_GIT_BRANCH), $(BUILD_GIT_DIRTY))"

force-load: check-quicklisp check-sbcl build-info
	@echo "Force-reloading $(PROJECT_SYSTEM)..."
	$(call capture-output,force-load,$(SBCL_RUN) \
	  $(call force-forms,$(PROJECT_SYSTEM))) ; \
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
	  $(call force-forms,$(PROJECT_SYSTEM))) ; \
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
	  $(call force-forms,$(TEST_SYSTEM)) \
	  --eval "(setf $(GOLDEN_PACKAGE):*update-goldens* t)" \
	  --eval "(setf $(GOLDEN_PACKAGE):*update-pixel-goldens* t)" \
	  --eval '(let ((cl-user::*exit-on-test-failures* t)) (declare (special cl-user::*exit-on-test-failures*)) (asdf:test-system :$(PROJECT_SYSTEM)))' \
	  2>&1 | tee $(TEST_OUTPUT); \
	RC=$$?; \
	grep -E "Passed:|Failed:" $(TEST_OUTPUT) | tail -1; \
	echo "Goldens regenerated — review and commit test/goldens/"; \
	exit $$RC
endif

# ── Test verdict ───────────────────────────────────────────────────────────
# The test targets do not trust Parachute's counters, and they cannot trust
# SBCL's exit status either (bd-xvg).  test-verdict.sh computes ONE verdict
# after the run, writes it into the captured log as its LAST line, and its
# own exit status is the target's.  Nothing above that line claims success.
#
# Read the verdict line, not "Passed:/Failed:" — Parachute does not count a
# test that failed to evaluate (an unhandled error in the test body), so the
# summary can read "Failed: 0" while the log contains ✘ and a ";; Failures:"
# block.  Read the ";; Failures:" block, or the VERDICT line.
#
# TEST_SUMMARY_PATTERN is what "the suite actually ran" looks like in the
# log; a log with no summary line is a FAIL for test/test-package.  Set
# TEST_REQUIRE_SUMMARY=no to drop that gate, or override the pattern for a
# framework that prints something else.
#
# PARACHUTE IS THE ONLY FRAMEWORK THIS ACCEPTS, on purpose (bd-phe).  The
# default used to be `^(;; Summary:|Total:|Running test suite)` plus fiveam's
# "Did N checks" — three marker lines from three different reports, only one of
# which (parachute's `;; Summary:`) this tool can also read FAILURES from.  That
# made every other framework satisfy the "did it run" gate and none of them the
# "did it fail" gate: a fiveam "Fail: 2" was recorded as a PASS and receipted.
# The default is now parachute's own heading, which is the one line that comes
# from the framework this project standardised on (bd-w0a).  A project on
# something else overrides TEST_SUMMARY_PATTERN *and* teaches test-verdict.sh
# its failure shapes — while it does neither, it fails loudly with "no test
# summary in the log", which is the safe direction.
TEST_VERDICT_SH := $(_CL_MK_DIR)test-verdict.sh
TEST_SUMMARY_PATTERN ?= ^(;; Summary:)
TEST_REQUIRE_SUMMARY ?= yes

# ── Test ───────────────────────────────────────────────────────────────────
# Single SBCL invocation captures load warnings, compile errors, AND test
# output.  Stale output file deleted first so grep never sees old results.
# Exit code preserved via pipefail.
# TEST_EVAL is hoisted into a variable so the $(call) parser never sees raw
# parens inside the Lisp form (they confuse make's function-argument scan).
#
# *exit-on-test-failures* is bound NIL on purpose.  Binding it T makes
# parachute call sb-ext:exit from inside (asdf:test-system ...); ASDF's
# operate unwinds the in-flight --eval form and SBCL then prints the
# confusing "compilation unit aborted / caught 1 fatal ERROR condition"
# banner even on a passing run.  The consequence: SBCL exits 0 even with
# failing tests, so its status is only one input to the verdict below — it
# is never the verdict.  The direct-test targets (test-package/test-eval)
# call parachute:test outside ASDF, where the exit is clean, so they DO set
# PARACHUTE_EXIT_EVAL below.
TEST_EVAL = (let ((cl-user::*exit-on-test-failures* nil)) (declare (special cl-user::*exit-on-test-failures*)) (asdf:test-system :$(PROJECT_SYSTEM)))

# Set parachute's *exit-on-test-failures* in the image for the direct-test
# targets.  defparameter proclaims the symbol special so parachute's
# boundp/symbol-value check sees t; a failing run then exits non-zero.
# (test-package/test-eval call parachute:test directly, not via ASDF, so
# there is no abort banner.)
PARACHUTE_EXIT_EVAL = (eval (quote (defparameter cl-user::*exit-on-test-failures* t)))
test: check-quicklisp check-sbcl
	@$(call gate-receipt-prefix,test,$(TEST_OUTPUT)) $(MAKE) --no-print-directory test-uncached

test-uncached: check-quicklisp check-sbcl
	$(call capture-output,test,$(SBCL_RUN) \
	  $(call force-forms,$(PROJECT_SYSTEM)) \
	  $(call force-forms,$(TEST_SYSTEM)) \
	  --eval '$(TEST_EVAL)') ; \
	RC=$$?; \
	TEST_SUMMARY_PATTERN='$(TEST_SUMMARY_PATTERN)' TEST_REQUIRE_SUMMARY=$(TEST_REQUIRE_SUMMARY) \
	  bash $(TEST_VERDICT_SH) --target test --require-summary $(TEST_OUTPUT) $$RC

# ── Gate receipts: the tool's own checks ──────────────────────────────────
# selftest is the deliverable, not a nicety: it proves a red gate is never
# receipted, a hit does not execute the command, the -LATEST.txt comes back
# byte-for-byte, one changed byte forces a miss, FORCE wins, clean works, and
# that the per-run regeneration of build-info.sexp does NOT change the digest
# (the trap that would silently disable every receipt).
gate-selftest:
	@bash $(GATE_RECEIPT) selftest

cache-status:
	@$(GATE_RECEIPT) status --cache '$(GATE_CACHE_DIR)' $(if $(VERBOSE),--verbose,)

cache-clean:
	@$(GATE_RECEIPT) clean --cache '$(GATE_CACHE_DIR)' $(or $(GATE),--all)

test-summary:
	@grep -E "Suite:|Summary:|Passed:|Failed:|Skipped:|Plan:|VERDICT:" $(TEST_OUTPUT) 2>/dev/null | tail -20 \
	  || echo "No test output at $(TEST_OUTPUT). Run 'make test' first."

# ── Verdict self-check ────────────────────────────────────────────────────
# Runs the fixture systems in test-fixtures/ through the real test targets and
# asserts the verdict is right: a green suite passes; a suite whose only
# failure is a test that failed to evaluate fails, with its log saying FAIL; a
# suite that never ran fails too.  This is the regression test for bd-xvg — a
# verdict based on the "Failed:" counter or on SBCL's exit status breaks it.
#
# The fixtures live next to this file, so every project that includes
# cl-project.mk can run the same self-check.
test-trust: check-quicklisp check-sbcl
	@bash $(_CL_MK_DIR)test-trust.sh "$(_CL_MK_DIR)" "$(SBCL)" "$(QL)"

# ── Receipt self-check ────────────────────────────────────────────────────
# Proves the receipt wiring in cl-project.mk end to end: the second identical
# run must not start an SBCL process, must restore the -LATEST.txt
# byte-for-byte, must respect FORCE=1 and cache-clean, must key test-package by
# PKG and test-eval by EVAL, and must never receipt a red gate.  `make test`
# twice on your own project is the other half of the proof — do it once.
test-receipts: check-quicklisp check-sbcl
	@bash $(_CL_MK_DIR)test-receipts.sh "$(_CL_MK_DIR)" "$(SBCL)" "$(QL)"

# ── Targeted testing ──────────────────────────────────────────────────────
# Run a single test package via parachute.
#   make test-package PKG=:my-package
#   make test-package PKG=:my-package REPORT=interactive
#
# PKG is any parachute designator (package keyword/symbol, or a single test
# name/suite symbol). Package names are resolved leniently: if the exact
# name isn't found, dots <-> slashes are swapped and tried again, so both
# PKG=:cogen-core.tests and PKG=:cogen-core/tests resolve the same package
# (ASDF secondary test systems are conventionally named system/tests while
# callers often guess the dotted form). The designator is ALSO hoisted into
# TEST_PACKAGE_EVAL so the $(call) capture-output parser never sees raw
# parens mid-Lisp-form (same reason TEST_EVAL is hoisted for `make test`).
# Char literals are written as (code-char N) — a literal #\/ in the
# expanded value would start a make comment (GNU make re-scans the expanded
# recipe line) and silently truncate the form.
PKG ?=
TEST_PACKAGE_EVAL = (let* ((designator $(PKG)) \
                            (name (etypecase designator \
                                    (symbol (symbol-name designator)) \
                                    (string designator) \
                                    (T (princ-to-string designator)))) \
                            (dot (code-char 46)) (slash (code-char 47)) \
                            (pkg (or (find-package name) \
                                     (find-package (substitute slash dot name)) \
                                     (find-package (substitute dot slash name)))) \
                            (target (if pkg pkg designator))) \
                      (parachute:test target$(if $(REPORT), :report (quote $(REPORT)))))
ifdef PKG
.PHONY: test-package test-package-uncached
test-package: check-quicklisp check-sbcl
	@$(call gate-receipt-prefix,test-package,$(TEST_PACKAGE_OUTPUT)) $(MAKE) --no-print-directory test-package-uncached

test-package-uncached: check-quicklisp check-sbcl
	$(call capture-output,test-package,$(SBCL_RUN) \
	  $(call force-forms,$(PROJECT_SYSTEM)) \
	  $(call force-forms,$(TEST_SYSTEM)) \
	  --eval '$(PARACHUTE_EXIT_EVAL)' \
	  --eval '$(TEST_PACKAGE_EVAL)') ; \
	RC=$$?; \
	TEST_SUMMARY_PATTERN='$(TEST_SUMMARY_PATTERN)' TEST_REQUIRE_SUMMARY=$(TEST_REQUIRE_SUMMARY) \
	  bash $(TEST_VERDICT_SH) --target test-package --require-summary $(TEST_PACKAGE_OUTPUT) $$RC
endif

# Run any test expression.  Works with any framework — but test-eval does NOT
# require a test summary, so it cannot JUDGE a framework whose report
# test-verdict.sh cannot read (fiveam: bd-phe).  Use test/test-package for that.
# Run any test expression.  Bypasses shell quoting via $(file).
# Works with single quotes, double quotes, any Lisp form.
#   make test-eval EVAL="(parachute:test :my-pkg 'some-sym)"
#   make test-eval EVAL="(format t \"hello\")"
# Only enforce when test-eval is the actual target (not at parse time).
ifneq (,$(filter test-eval,$(MAKECMDGOALS)))
  ifeq (,$(EVAL))
    $(error EVAL is required. Usage: make test-eval EVAL="(form)")
  endif
endif
.PHONY: test-eval test-eval-uncached
test-eval: check-quicklisp check-sbcl
	@$(call gate-receipt-prefix,test-eval,$(TEST_EVAL_OUTPUT)) $(MAKE) --no-print-directory test-eval-uncached

test-eval-uncached: check-quicklisp check-sbcl
	$(file >$(TEST_EVAL_TMP),$(EVAL))
	$(call capture-output,test-eval,$(SBCL_RUN) \
	  $(call force-forms,$(PROJECT_SYSTEM)) \
	  $(call force-forms,$(TEST_SYSTEM)) \
	  --eval '$(PARACHUTE_EXIT_EVAL)' \
	  --load $(TEST_EVAL_TMP)) ; \
	RC=$$?; \
	TEST_SUMMARY_PATTERN='$(TEST_SUMMARY_PATTERN)' \
	  bash $(TEST_VERDICT_SH) --target test-eval $(TEST_EVAL_OUTPUT) $$RC

# ── Compiler-warning lint (bd-a8r) ────────────────────────────────────────
# A docstring that quotes a phrase with a plain double quote ENDS at that quote.
# The rest of the sentence becomes body forms: the function still compiles, and it
# signals an unbound-variable error the first time it runs. For something that renders
# every frame that kills the process instantly. Parenthesis checkers, CST parsers and
# structural editors all accept such a file -- the compiler's own "undefined variable"
# warning is the only cheap detector.
#
# So: force-load the system, then fail when a warning about an undefined variable or
# function is attributed to a file under $(LINT_SOURCE_DIR)/. Warnings from other files
# are ignored on purpose -- structurally aware editors (csct) compile isolated
# fragments in /tmp and warn about symbols from files they deliberately do not load.
#
# The recompilation MUST go through ASDF: (ql:quickload :sys :force t) accepts the
# keyword (its lambda list has &allow-other-keys) and ignores it, so it only compiles
# what ASDF thinks is stale. With every fasl fresh that compiles nothing, no warning is
# ever emitted, and the target passes on an empty log -- the exact silent-pass failure
# this check exists to prevent (found 2026-11-03 while promoting it here).
#
# Deliberately NOT a prerequisite of test: it force-loads the whole system, which costs
# seconds on every run. `make lint` is a pre-commit check.
#
# The quickload before the force-recompile also loads every file, so an intra-system
# forward reference (a file using a special the next file defines) is already bound when
# it is recompiled and is not reported. That is deliberate: it is a different bug class
# from a docstring that swallows the body, and reporting those would make lint fail on
# a fresh image and pass on a warm one.
#
# LINT_ALLOWED lists symbol substrings that are known and tolerated; keep it empty
# unless a warning is a real false positive, and say why next to it.
LINT_ALLOWED ?=
LINT_SOURCE_DIR ?= src

.PHONY: lint
lint: check-quicklisp check-sbcl
	$(call capture-output,lint,$(SBCL_RUN) \
	  --eval '(ql:quickload :$(PROJECT_SYSTEM))' \
	  --eval '(asdf:load-system :$(PROJECT_SYSTEM) :force t)') ; \
	RC=$$?; \
	if [ $$RC -ne 0 ]; then \
	  echo ""; \
	  echo "lint: the force-load itself failed (exit $$RC) -- warnings are not the problem:"; \
	  tail -20 $(OUTPUT_DIR)lint-LATEST.txt; \
	  exit $$RC; \
	fi; \
	HITS=$$(awk '/^; file: /{file=$$0} /[Uu]ndefined (variable|function)/{ \
	               if (file ~ /\/$(LINT_SOURCE_DIR)\//) printf "%s\n    %s\n", file, $$0 }' \
	             $(OUTPUT_DIR)lint-LATEST.txt); \
	if [ -n "$(LINT_ALLOWED)" ]; then \
	  HITS=$$(printf '%s\n' "$$HITS" | grep -vF -e "$(LINT_ALLOWED)"); \
	fi; \
	if [ -n "$$HITS" ]; then \
	  echo ""; \
	  echo "lint: undefined-symbol warnings from $(LINT_SOURCE_DIR)/ -- a docstring probably"; \
	  echo "      ends at an inner double quote (bd-a8r), or a definition is missing:"; \
	  echo ""; \
	  printf '%s\n' "$$HITS"; \
	  exit 1; \
	fi; \
	echo "lint: no undefined-symbol warnings from $(LINT_SOURCE_DIR)/ ($(OUTPUT_DIR)lint-LATEST.txt)"

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
	  rm -f $(BINARY_PATH)/$(BINARY_NAME) $(BINARY_BUILD_PATH); \
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
# The binary is built via asdf:make (which wraps sb-ext:save-lisp-and-die),
# moved to bin/<name>, and installed to ~/.local/bin/<name>.
#
# save-lisp-and-die refuses to save when multiple threads are running
# (SAVE-WITH-MULTIPLE-THREADS-ERROR).  Before dumping we terminate all
# background threads.  Override BUILD_PRE_DUMP_FORM for project-specific
# cleanup (close DBs, stop servers, etc.).
#
# For full-featured deployment (foreign libs, resource dirs, boot/quit
# hooks) see the `deploy` ASDF system (shinmera/deploy).

BUILD_PRE_DUMP_FORM ?= \
  (progn (format t "~%Stopping background threads before dump...~%") \
         (dolist (thread (remove sb-thread:*current-thread* (sb-thread:list-all-threads))) \
           (ignore-errors (sb-thread:terminate-thread thread))) \
         (sleep 0.5))

BUILD_PRE_DUMP_TMP ?= /tmp/$(subst /,-,$(PROJECT_SYSTEM))-build-pre-dump.lisp
# Directory the built binary is installed into (staging, pre-install).
# Defaults to ./bin — the binary ends up at $(BINARY_PATH)/$(BINARY_NAME).
BINARY_PATH ?= bin
# Where asdf:make drops the raw binary.  Defaults to repo root; projects
# whose .asd uses :pathname (so :build-pathname is relative to it) override
# this to the source subdirectory (e.g. src/cli/foo).
BINARY_BUILD_PATH ?= $(BINARY_NAME)

build: force-load
	@if [ -z "$(BINARY_NAME)" ]; then \
	  echo "BINARY_NAME not set. Set BINARY_NAME := <name> before include to enable build."; \
	  exit 1; \
	fi
	@echo "Building $(BUILD_SYSTEM) binary..."
	@echo "  $(BINARY_NAME): $(PROJECT_VERSION) @ $(BUILD_GIT_SHA) ($(BUILD_GIT_BRANCH), $(BUILD_GIT_DIRTY))"
	$(file >$(BUILD_PRE_DUMP_TMP),$(BUILD_PRE_DUMP_FORM))
	@$(SBCL_RUN) \
	  $(call force-forms,$(BUILD_SYSTEM)) \
	  --load $(BUILD_PRE_DUMP_TMP) \
	  --eval '(asdf:make :$(BUILD_SYSTEM))'
	@mkdir -p $(BINARY_PATH)
	@if [ -f $(BINARY_BUILD_PATH) ]; then mv -f $(BINARY_BUILD_PATH) $(BINARY_PATH)/$(BINARY_NAME); fi
	@if [ -f $(BINARY_PATH)/$(BINARY_NAME) ]; then \
	  echo "Built: $(BINARY_PATH)/$(BINARY_NAME) ($$(ls -lh $(BINARY_PATH)/$(BINARY_NAME) | awk '{print $$5}'))"; \
	else \
	  echo "Build failed: no binary produced at $(BINARY_BUILD_PATH)"; \
	  exit 1; \
	fi

install: build
	@if [ -f $(BINARY_PATH)/$(BINARY_NAME) ]; then \
	  mkdir -p $(INSTALL_DIR); \
	  cp -f $(BINARY_PATH)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME); \
	  echo "Installed to $(INSTALL_DIR)/$(BINARY_NAME)"; \
	else \
	  echo "No binary found at $(BINARY_PATH)/$(BINARY_NAME). Run 'make build' first."; \
	  exit 1; \
	fi

build-report: fresh-build summarize
