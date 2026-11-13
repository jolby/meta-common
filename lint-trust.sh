#!/usr/bin/env bash
# lint-trust.sh — self-check for `make lint` (bd-twd).
#
# Runs the REAL lint target against fixture projects in test-fixtures/ that
# include ../../cl-project.mk, so nothing here re-implements the check:
#
#   lint-warns       a compile WARNING (a slot whose initform conflicts with its
#                    asserted type — the shape limited-box's GENERATED region
#                    had) and NO undefined symbol             -> GREEN, exit 0
#                    ...and the warning must still be IN the log, or the fixture
#                    has stopped exercising the trap it exists for.
#   lint-warns-trap  the same warning in the FIRST file, then a docstring that
#                    ends at an inner quote, so the rest of that sentence is body
#                    forms and an undefined variable is the only evidence
#                                                             -> RED, exit != 0
#                    ...and the report must NAME src/trap.lisp. A red that only
#                    says "the force-load failed" is the confusion bd-twd was:
#                    before the fix, lint died at the warning-producing file and
#                    never reached the trap behind it.
#   standalone       the same trap with no warning in front of it, so check 2's
#                    red cannot be an artifact of the warning.
#
# TWO logs matter, and they are different files: capture-output puts SBCL's own
# output in /tmp/<system>-lint-LATEST.txt, while the target's own messages
# (which file produced what, and the final verdict) go to the terminal, which
# this script captures in /tmp/<system>-lint-terminal.txt.
#
#   usage: lint-trust.sh <cl-make-dir> [sbcl-binary] [quicklisp-setup]
#
# Exit status 0 means every assertion held.

set -uo pipefail

CL_MK_DIR=${1:?usage: lint-trust.sh <cl-make-dir> [sbcl] [quicklisp-setup]}
SBCL_BIN=${2:-sbcl}
QL_PATH=${3:-$HOME/quicklisp/setup.lisp}
FIXTURES="${CL_MK_DIR%/}/test-fixtures"

checks=0
failed=0

check() { # check <description> <0 = held, 1 = violated>
  checks=$((checks + 1))
  if [ "$2" -eq 0 ]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s\n' "$1"
    failed=$((failed + 1))
  fi
}

is() { [ "$1" -eq 0 ] && echo 0 || echo 1; }

# logs_for <project-system> — sets LOG (SBCL output) and TERM (target messages).
# Keyed on the SYSTEM name, not the directory: the standalone fixture below lives
# in a mktemp directory whose basename is not its system name.
logs_for() {
  LOG="/tmp/$1-lint-LATEST.txt"
  TERM="/tmp/$1-lint-terminal.txt"
}

# run_lint <fixture-dir> — sets RC; terminal output to TERM's file.
# FORCE=1 is deliberate even though lint is not receipted today: if it ever
# gains a receipt, a self-check answered from a cached log would check nothing.
run_lint() {
  local dir=$1
  (cd "$dir" && FORCE=1 make lint SBCL="$SBCL_BIN" QL="$QL_PATH") >"$TERM" 2>&1
  RC=$?
}

echo "== lint-trust: fixtures under $FIXTURES =="

# ── 1. A warning with nothing to find: GREEN, and the warning is visible ──
echo "[1/3] lint-warns / make lint — must PASS despite a compile warning"
logs_for lint-warns
run_lint "$FIXTURES/lint-warns"
check "lint-warns: make lint exits 0"                        "$(is "$RC")"
check "lint-warns: the verdict says no undefined-symbol warnings" \
      "$(is "$(grep -q 'no undefined-symbol warnings from src/' "$TERM"; echo $?)")"
check "lint-warns: the compile warning IS in the log (the trap is armed)" \
      "$(is "$(grep -q 'conflicts with its asserted type' "$LOG"; echo $?)")"
check "lint-warns: lint SAYS it tolerated a warning, and how many files" \
      "$(is "$(grep -q 'compiled with WARNINGS that lint tolerates on purpose' "$TERM"; echo $?)")"

# ── 2. The classic docstring trap behind a warning: RED, naming the file ──
echo "[2/3] lint-warns-trap / make lint — must FAIL, naming src/trap.lisp"
logs_for lint-warns-trap
run_lint "$FIXTURES/lint-warns-trap"
check "lint-warns-trap: make lint exits non-zero"            "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "lint-warns-trap: the verdict reports undefined-symbol warnings" \
      "$(is "$(grep -q 'undefined-symbol warnings from src/' "$TERM"; echo $?)")"
check "lint-warns-trap: the report NAMES src/trap.lisp"       \
      "$(is "$(grep -q 'trap\.lisp' "$TERM"; echo $?)")"
check "lint-warns-trap: the log carries the undefined variable" \
      "$(is "$(grep -qE '[Uu]ndefined variable' "$LOG"; echo $?)")"
# The distinction that matters: RED because a trap was FOUND, not because the
# load died on the warning in front of it. Both are in one system, warns.lisp
# first, and the target's own fatal path announces itself in capitals.
check "lint-warns-trap: not red for 'the force-load itself FAILED'" \
      "$(is "$(grep -q 'the force-load itself FAILED' "$TERM" && echo 1 || echo 0)")"

# ── 3. The same trap with no warning in front of it: still RED ────────────
echo "[3/3] a trap with no warning in front of it — must also FAIL"
STANDALONE=$(mktemp -d /tmp/lint-trust-standalone.XXXXXX)
cp "$FIXTURES/lint-warns/Makefile" "$STANDALONE/Makefile"
# The fixture's Makefile says lint-warns and includes ../../cl-project.mk, which
# is only correct inside the fixtures tree; point the copy at the real file.
sed -i 's/^PROJECT_SYSTEM := lint-warns$/PROJECT_SYSTEM := lint-standalone/' \
  "$STANDALONE/Makefile"
sed -i 's|include \.\./\.\./cl-project\.mk|include '"${CL_MK_DIR%/}"'/cl-project.mk|' \
  "$STANDALONE/Makefile"
mkdir -p "$STANDALONE/src"
cp "$FIXTURES/lint-warns-trap/src/trap.lisp" "$STANDALONE/src/trap.lisp"
cp "$FIXTURES/lint-warns/src/clean.lisp" "$STANDALONE/src/clean.lisp"
cat >"$STANDALONE/lint-standalone.asd" <<'ASD'
(defsystem "lint-standalone"
  :version "0.0.1"
  :description "Fixture: the docstring trap with no warning in front of it (bd-twd)."
  :serial t
  :components ((:file "src/clean")
               (:file "src/trap")))
ASD
logs_for lint-standalone
run_lint "$STANDALONE"
check "lint-standalone: make lint exits non-zero"            "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "lint-standalone: the report NAMES src/trap.lisp"       \
      "$(is "$(grep -q 'trap\.lisp' "$TERM"; echo $?)")"
check "lint-standalone: nothing was tolerated (no warning to tolerate)" \
      "$(is "$(grep -q 'compiled with WARNINGS' "$TERM" && echo 1 || echo 0)")"
rm -rf "$STANDALONE"

echo ""
if [ "$failed" -eq 0 ]; then
  echo "== lint-trust: $checks checks, 0 failed — the docstring detector survives a warning =="
  exit 0
fi
echo "== lint-trust: $checks checks, $failed FAILED — lint cannot be trusted =="
echo "   logs: /tmp/lint-*-lint-LATEST.txt and /tmp/lint-*-lint-terminal.txt"
exit 1
