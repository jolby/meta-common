#!/usr/bin/env bash
# load-trust.sh — self-check for the load verdict (bd-t5m).
#
# Runs the REAL load targets against fixture projects in test-fixtures/ (each
# includes ../../cl-project.mk, so nothing here re-implements the verdict) and
# asserts that the target reports the right thing:
#
#   load-style-warning      an unused variable, so SBCL emits
#                           "; caught STYLE-WARNING: ..." and
#                           "; caught 1 STYLE-WARNING condition"   -> PASS, exit 0
#                           ...and those lines must still be IN the log, or the
#                           fixture has stopped exercising what it tolerates.
#   load-tolerated-warning  the same function defined twice in one file, so SBCL
#                           emits a real "; caught WARNING: Duplicate definition
#                           ..." that the project declares benign with
#                           LOAD_FORCE_EXTRA                  -> PASS, exit 0
#                           ...and the warning must still be in the log AND be
#                           reported as tolerated. This is the "cries wolf" half:
#                           the old predicate grepped for "caught WARNING" and
#                           re-failed exactly the projects that had used the
#                           documented escape hatch.
#   load-undefined          a docstring that ends at an inner quote (undefined
#                           variable) plus an undefined function  -> FAIL, exit != 0
#                           ...and the report must NAME src/broken.lisp and
#                           src/calls.lisp. The command itself EXITS 0 here, so a
#                           red cannot be blamed on the exit status: it is the
#                           detector or nothing (this is also the regression test
#                           for force-load grepping the load target's log — the
#                           wrong file — and therefore never failing).
#
# Then load-verdict.sh's own gates, on synthetic logs, one at a time. Those
# strings are VERBATIM from SBCL 2.6.8 logs captured while this was written; a
# detector that only the fixtures can satisfy is a detector that will rot.
#
# TWO logs matter and they are different files: capture-output puts SBCL's own
# output in /tmp/<system>-<target>-LATEST.txt, while the target's own messages
# (the verdict) go to the terminal, which this script captures.
#
#   usage: load-trust.sh <cl-make-dir> [sbcl-binary] [quicklisp-setup]
#
# Exit status 0 means every assertion held.

set -uo pipefail

CL_MK_DIR=${1:?usage: load-trust.sh <cl-make-dir> [sbcl] [quicklisp-setup]}
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

# run_load <fixture-dir> <target> [extra make assignments...] — sets RC and LOG
# and TERM; terminal output to TERM.
#
# FORCE=1 is deliberate: the load targets are not receipted today, and if they
# gain a receipt a self-check answered from a cached log would check nothing.
run_load() {
  local dir=$1 target=$2
  shift 2
  LOG="/tmp/$(basename "$dir")-$target-LATEST.txt"
  TERM="/tmp/$(basename "$dir")-$target-terminal.txt"
  (cd "$dir" && FORCE=1 make "$target" SBCL="$SBCL_BIN" QL="$QL_PATH" "$@") >"$TERM" 2>&1
  RC=$?
}

verdict_is() { grep -q "^=== VERDICT: $2 (target: $3," "$1"; }

verdict_is_last() {
  [ "$(tail -1 "$1")" = "$(grep -E '^=== VERDICT:' "$1" | tail -1)" ]
}

echo "== load-trust: fixtures under $FIXTURES =="

# ── 0. One implementation, and it is not the old grep ─────────────────────
# The four targets were four copies of one grep, and force-load's copy read the
# load target's log. The invariant that keeps that from coming back is cheap to
# state: the predicate lives in ONE file, and no target inlines it.
echo "[0/4] one verdict implementation for all four load targets"
check "cl-project.mk no longer inlines the blind predicate" \
      "$(is "$(grep -q 'caught (fatal )?(ERROR|WARNING)' "$CL_MK_DIR/cl-project.mk" && echo 1 || echo 0)")"
check "cl-project.mk calls load-verdict.sh from every load target" \
      "$(is "$([ "$(grep -c 'LOAD_VERDICT_SH' "$CL_MK_DIR/cl-project.mk")" -ge 5 ] && echo 0 || echo 1)")"
# bd-235.  `load` WROTE $(OUTPUT_DIR)load-LATEST.txt and JUDGED LOAD_OUTPUT,
# which was spelled /tmp/<system>-load-LATEST.txt — so with OUTPUT_DIR set the
# verdict read whatever the previous run had left there, and could pass a load
# that emitted warnings.  A make-level check, because the bug was in the wiring:
# no SBCL run can distinguish "the verdict is right" from "the verdict read the
# right file" when both files hold the same text.
# Captured to a file first: `make -pn | grep -q` reads make's 141 (grep matched
# early and closed the pipe) instead of grep's 0, and pipefail makes that the
# pipeline's status.
LOAD_PROBE=$(mktemp /tmp/load-trust-probe.XXXXXX)
(cd "$FIXTURES/load-undefined" && make -pn OUTPUT_DIR=/tmp/load-trust-probe- 2>/dev/null) >"$LOAD_PROBE"
check "bd-235: LOAD_OUTPUT is derived from OUTPUT_DIR (write = read)" \
      "$(is "$(grep -qE '^LOAD_OUTPUT = \$\(OUTPUT_DIR\)load-LATEST\.txt$' "$LOAD_PROBE" && echo 0 || echo 1)")"
rm -f "$LOAD_PROBE"

# ── 1. Style-warnings only: PASS, and the warning is visible ──────────────
echo "[1/4] load-style-warning / make force-load — must PASS despite a style-warning"
run_load "$FIXTURES/load-style-warning" force-load
check "load-style-warning: make force-load exits 0"          "$(is "$RC")"
check "load-style-warning: the verdict says PASS"            "$(is "$(verdict_is "$LOG" PASS force-load; echo $?)")"
check "load-style-warning: the verdict line is the log's last line" "$(is "$(verdict_is_last "$LOG"; echo $?)")"
check "load-style-warning: the style-warning IS in the log (the trap is armed)" \
      "$(is "$(grep -q 'caught STYLE-WARNING' "$LOG"; echo $?)")"
check "load-style-warning: the counted summary is in the log too" \
      "$(is "$(grep -qE 'caught [0-9]+ STYLE-WARNING condition' "$LOG"; echo $?)")"
check "load-style-warning: the log REPORTS the tolerated style-warnings" \
      "$(is "$(grep -q 'warnings tolerated (not a gate)' "$LOG"; echo $?)")"

# ── 2. A real WARNING the project declared benign: PASS, not a wolf ───────
echo "[2/4] load-tolerated-warning / make force-load — must PASS despite 'caught WARNING'"
run_load "$FIXTURES/load-tolerated-warning" force-load
check "load-tolerated-warning: make force-load exits 0"      "$(is "$RC")"
check "load-tolerated-warning: the verdict says PASS"        "$(is "$(verdict_is "$LOG" PASS force-load; echo $?)")"
check "load-tolerated-warning: the verdict line is the log's last line" "$(is "$(verdict_is_last "$LOG"; echo $?)")"
check "load-tolerated-warning: a real 'caught WARNING' IS in the log" \
      "$(is "$(grep -q '^; caught WARNING:' "$LOG"; echo $?)")"
check "load-tolerated-warning: ...and the log counts it as tolerated" \
      "$(is "$(grep -qE '^  [1-9][0-9]* WARNING line' "$LOG"; echo $?)")"

# ── 3. An undefined symbol: FAIL, naming the file, on a 0 exit ────────────
echo "[3/4] load-undefined / make force-load — must FAIL, naming both files"
run_load "$FIXTURES/load-undefined" force-load
check "load-undefined: make force-load exits non-zero"       "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "load-undefined: the verdict says FAIL"                "$(is "$(verdict_is "$LOG" FAIL force-load; echo $?)")"
check "load-undefined: the verdict line is the log's last line" "$(is "$(verdict_is_last "$LOG"; echo $?)")"
check "load-undefined: the report NAMES src/broken.lisp (undefined VARIABLE)" \
      "$(is "$(grep -q 'src/broken\.lisp' "$LOG"; echo $?)")"
check "load-undefined: the report NAMES src/calls.lisp (undefined FUNCTION)" \
      "$(is "$(grep -q 'src/calls\.lisp' "$LOG"; echo $?)")"
# The decisive assertion: SBCL exits 0 for this project (an undefined symbol is
# a deferred WARNING, not a failed compile), so the red is the DETECTOR. If a
# future change made the command exit non-zero, this check goes red and the
# reason has to be re-argued rather than quietly passing for the wrong reason.
check "load-undefined: the command itself exited 0 (so the red is the detector)" \
      "$(is "$(grep -q 'the load command exited' "$LOG" && echo 1 || echo 0)")"
# force-load's own log, not the load target's: that mix-up is why this gate could
# never fail, and it is not detectable from the verdict's text alone.
check "load-undefined: the verdict read the FORCE-LOAD log (not the load log)" \
      "$(is "$(grep -q -- '-force-load-LATEST\.txt)' "$LOG"; echo $?)")"

# ── 4. The verdict script's own gates, on synthetic logs ──────────────────
echo "[4/4] load-verdict.sh — one gate at a time, no Lisp involved"
SYNTH=$(mktemp -d /tmp/load-trust-synth.XXXXXX)
PROJ="$SYNTH/proj"
mkdir -p "$PROJ/src"

# synth <name> <log-body> [rc] — writes the body, runs the verdict scoped to
# $PROJ, sets VRC.
synth() {
  local log="$SYNTH/$1.txt"
  printf '%b\n' "$2" >"$log"
  bash "${CL_MK_DIR%/}/load-verdict.sh" --target load --source "$PROJ" "$log" "${3:-0}" >/dev/null 2>&1
  VRC=$?
}

GOOD="; Loading \"x\"
; compilation finished in 0:00:00.001"

synth green "$GOOD"
check "a clean load log exits 0"                              "$(is "$VRC")"

# The bead's own complaint, as a log. ASDF summarises style-warnings in a counted
# line; the old regex needed "caught WARNING" and missed it, while the line above
# it ("caught STYLE-WARNING:") it also (correctly) ignored.
synth style-only "; Loading \"x\"
; caught STYLE-WARNING:
;   The variable CMD is defined but never used.
; caught 18 STYLE-WARNING conditions"
check "style-warnings only (per-condition AND counted) exit 0" "$(is "$VRC")"

# Verbatim from a real log on this machine (loom's macro warning and a duplicate
# definition). Both are benign for a load gate, and both are what the old
# predicate rejected the project for.
synth benign-warning "; Loading \"x\"
; caught WARNING:
;   LOOM requires the 'if' form to have an 'else' clause
; caught WARNING:
;   Duplicate definition for GET-INSTANCE found in one file.
;   caught 2 WARNING conditions"
check "a benign 'caught WARNING' exits 0 (no crying wolf)"    "$(is "$VRC")"

synth error "; Loading \"x\"
; caught ERROR:
;   The variable FOO is not a function."
check "a per-condition 'caught ERROR' exits non-zero"         "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"

# The counted summary carries a number between "caught" and the kind, which a
# naive regex anchored on 'caught ERROR' would miss.
synth fatal-count "; Loading \"x\"
; compilation unit aborted
;   caught 2 fatal ERROR conditions"
check "a counted 'caught 2 fatal ERROR conditions' exits non-zero" "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
synth error-count "; Loading \"x\"
;   caught 1 ERROR condition"
check "a counted 'caught 1 ERROR condition' exits non-zero"   "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"

synth undefined "; Loading \"x\"
; file: $PROJ/src/broken.lisp
; caught WARNING:
;   undefined variable: SYNTH::FLAG"
check "an undefined variable in the project's sources exits non-zero" "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
check "...and the report NAMES the file, relative to the source root" \
      "$(is "$(grep -q 'src/broken\.lisp' "$SYNTH/undefined.txt"; echo $?)")"

# The same warning, in a file that is NOT this project's source. A dependency's
# undefined symbol is not this project's bug and must not gate its load.
synth dep-undefined "; Loading \"x\"
; file: $HOME/quicklisp/dists/quicklisp/software/loom-1.0.0/loom.lisp
; caught WARNING:
;   undefined variable: LOOM::*REGEX-CASE-SENSITIVE-P*"
check "an undefined variable in a DEPENDENCY exits 0"         "$(is "$VRC")"

synth header-only "=== x load — 2026-11-19T00:00:00-08:00 ==="
check "a log holding only the capture header exits non-zero"  "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"

synth green "$GOOD" 7
check "a non-zero command exit fails an otherwise clean log"  "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"

bash "${CL_MK_DIR%/}/load-verdict.sh" --target load --source "$PROJ" "$SYNTH/does-not-exist.txt" 0 >/dev/null 2>&1
check "a missing log exits non-zero"                          "$(is "$([ "$?" -ne 0 ] && echo 0 || echo 1)")"

rm -f "$SYNTH"/*.txt
rm -rf "$SYNTH"

echo ""
if [ "$failed" -eq 0 ]; then
  echo "== load-trust: $checks checks, 0 failed — the load verdict can be trusted =="
  exit 0
fi
echo "== load-trust: $checks checks, $failed FAILED — the load verdict cannot be trusted =="
echo "   logs: /tmp/load-*-LATEST.txt and /tmp/load-*-terminal.txt"
exit 1
