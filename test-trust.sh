#!/usr/bin/env bash
# test-trust.sh — self-check for the test verdict (bd-xvg).
#
# Runs fixture systems through the REAL shared test target (each fixture
# includes ../../cl-project.mk, so nothing here re-implements the verdict)
# and asserts that the target reports the right thing:
#
#   verdict-pass       one passing test                    -> PASS, exit 0
#   verdict-eval-fail  one pass + one test that failed to
#                      evaluate ("Failed: 0", ✘, Failures)  -> FAIL, exit != 0
#   verdict-no-suite   system whose test-op runs nothing    -> FAIL, exit != 0
#   verdict-eval-fail  test-package (direct parachute call) -> FAIL in the log
#   verdict-pass       test-eval with a trivial form        -> PASS, exit 0
#   no-test-system     a project whose <system>/tests does
#                      NOT exist (bd-wf7): the target used
#                      to force-load it, die with
#                      SYSTEM-NOT-FOUND and report FAIL      -> says NO TEST
#                      SYSTEM, points at TEST_ALTERNATIVE,
#                      exits 0, and writes NO verdict line
#   verdict-broken-build a suite that does not COMPILE
#                      (a test file that does not read)      -> FAIL, exit != 0,
#                      no verdict line, no GREEN receipt, and the
#                      no-test-system marker absent from the
#                      backtrace that echoes the guard's own
#                      source (bd-829)
#   OUTPUT_DIR decoy   the failing fixture run with
#                      OUTPUT_DIR=<scratch> while a GREEN log
#                      sits at the shared path: the verdict
#                      must judge the file this run wrote and
#                      say FAIL (bd-235 — it used to read the
#                      decoy and say PASS)
#   synthetic logs     one gate at a time (counted failure,
#                      ✘, Failures block, no summary, bad
#                      command exit, missing log)            -> each FAIL
#                      plus FIVEAM: its "Did N checks" summary is
#                      not evidence that a suite passed, so a
#                      fiveam log FAILs whether it reports
#                      "Fail: 2" or "Fail: 0" (bd-phe)
#
# The eval-fail case also asserts that the counters really do lie ("Passed: 1"
# with "Failed: 0"), so the check cannot silently stop exercising the trap.
#
#   usage: test-trust.sh <cl-make-dir> [sbcl-binary] [quicklisp-setup]
#
# Exit status 0 means every assertion held.

set -uo pipefail

CL_MK_DIR=${1:?usage: test-trust.sh <cl-make-dir> [sbcl] [quicklisp-setup]}
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

# log_for <fixture-dir> <target> — where capture-output writes the log.
log_for() {
  printf '/tmp/%s-%s-LATEST.txt\n' "$(basename "$1")" "$2"
}

# run_make <fixture-dir> <make-args...> — sets RC; terminal output to a file.
# FORCE=1 is deliberate: gate receipts (bd-sbf) would otherwise answer the
# second run from a cached log, and this script's whole job is to make the
# verdict run.  A self-check satisfied by a stale receipt checks nothing.
run_make() {
  local dir=$1
  shift
  local term_log
  term_log="/tmp/$(basename "$dir")-$1-terminal.txt"
  (cd "$dir" && FORCE=1 make "$@" SBCL="$SBCL_BIN" QL="$QL_PATH") >"$term_log" 2>&1
  RC=$?
}

# Common assertions: the verdict line exists and is the log's last line.
verdict_is() { # verdict_is <log> <PASS|FAIL>
  grep -q "^=== VERDICT: $2" "$1"
}

verdict_is_last() {
  [ "$(tail -1 "$1")" = "$(grep -E '^=== VERDICT:' "$1" | tail -1)" ]
}

echo "== test-trust: fixtures under $FIXTURES =="

# ── 1. A genuinely green suite: PASS, exit 0 ──────────────────────────────
echo "[1/9] verdict-pass / make test — must PASS"
LOG=$(log_for "$FIXTURES/verdict-pass" test)
run_make "$FIXTURES/verdict-pass" test
check "verdict-pass: make test exits 0"                      "$(is "$RC")"
check "verdict-pass: log says PASS"                          "$(is "$(verdict_is "$LOG" PASS; echo $?)")"
check "verdict-pass: the verdict line is the log's last line" "$(is "$(verdict_is_last "$LOG"; echo $?)")"

# ── 2. Only failure is a test that failed to evaluate: FAIL, exit != 0 ────
echo "[2/9] verdict-eval-fail / make test — must FAIL"
LOG=$(log_for "$FIXTURES/verdict-eval-fail" test)
run_make "$FIXTURES/verdict-eval-fail" test
check "verdict-eval-fail: make test exits non-zero"          "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "verdict-eval-fail: log says FAIL"                     "$(is "$(verdict_is "$LOG" FAIL; echo $?)")"
check "verdict-eval-fail: the verdict line is the log's last line" "$(is "$(verdict_is_last "$LOG"; echo $?)")"
check "verdict-eval-fail: the trap is present (a test failed to evaluate)" "$(is "$(grep -q 'failed to evaluate properly' "$LOG"; echo $?)")"
check "verdict-eval-fail: parachute's counters still lie (Failed: 0)"      "$(is "$(grep -qE '^Failed:[[:space:]]*0' "$LOG"; echo $?)")"
check "verdict-eval-fail: the verdict names the real reason" "$(is "$(grep -q 'failed to evaluate properly' "$LOG" && grep -q '^=== VERDICT reasons ===' "$LOG"; echo $?)")"

# ── 3. A suite that never ran: FAIL, exit != 0 ────────────────────────────
echo "[3/9] verdict-no-suite / make test — must FAIL"
LOG=$(log_for "$FIXTURES/verdict-no-suite" test)
run_make "$FIXTURES/verdict-no-suite" test
check "verdict-no-suite: make test exits non-zero"           "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "verdict-no-suite: log says FAIL"                      "$(is "$(verdict_is "$LOG" FAIL; echo $?)")"
check "verdict-no-suite: the verdict names the missing suite" "$(is "$(grep -q 'no test summary' "$LOG"; echo $?)")"
check "verdict-no-suite: nothing in the log claims success"  "$(is "$(grep -qE '=== Exit: 0|VERDICT: PASS' "$LOG" && echo 1 || echo 0)")"

# ── 4. test-package: same trap, direct parachute call ─────────────────────
echo "[4/9] verdict-eval-fail / make test-package — must FAIL in the log"
LOG=$(log_for "$FIXTURES/verdict-eval-fail" test-package)
run_make "$FIXTURES/verdict-eval-fail" test-package PKG=":verdict-eval-fail/tests"
check "test-package: exits non-zero"                         "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "test-package: log says FAIL"                          "$(is "$(verdict_is "$LOG" FAIL; echo $?)")"
check "test-package: the verdict line is the log's last line" "$(is "$(verdict_is_last "$LOG"; echo $?)")"

# ── 5. test-eval: arbitrary form, no summary required ─────────────────────
echo "[5/9] verdict-pass / make test-eval — must PASS without a summary"
LOG=$(log_for "$FIXTURES/verdict-pass" test-eval)
run_make "$FIXTURES/verdict-pass" test-eval 'EVAL=(format t "~&trivial form ran.~%")'
check "test-eval: exits 0"                                   "$(is "$RC")"
check "test-eval: log says PASS"                             "$(is "$(verdict_is "$LOG" PASS; echo $?)")"
check "test-eval: the verdict line is the log's last line"    "$(is "$(verdict_is_last "$LOG"; echo $?)")"
# A `$name` inside the form must reach Lisp unchanged. A command-line variable
# is recursively expanded, so `$(EVAL)` would expand the form a second time and
# read `$path` as make variable `path`: the form arrives corrupted, silently
# (bd-rov). Cypher parameters are the usual casualty.
LOG=$(log_for "$FIXTURES/verdict-pass" test-eval)
run_make "$FIXTURES/verdict-pass" test-eval 'EVAL=(format t "~&dollar=~S.~%" "$path")'
check "test-eval: a dollar name in the form reaches Lisp intact" \
      "$(is "$(grep -qF 'dollar="$path"' "$LOG"; echo $?)")"

# ── 7. A project with NO test system: says so, exits 0, writes no verdict ──
# The trap (bd-wf7): `test` force-loads $(TEST_SYSTEM), the load signals
# SYSTEM-NOT-FOUND, nothing runs, and the verdict says FAIL with "no test
# summary in the log". A red gate no change to the code can turn green.
echo "[6/9] no-test-system / make test — must say so and exit 0"
LOG=$(log_for "$FIXTURES/no-test-system" test)
run_make "$FIXTURES/no-test-system" test
check "no-test-system: make test exits 0"                    "$(is "$RC")"
check "no-test-system: the log says NO TEST SYSTEM"           "$(is "$(grep -qF 'test: NO TEST SYSTEM' "$LOG"; echo $?)")"
check "no-test-system: it names the system that is missing"   "$(is "$(grep -qF 'no-test-system/tests does not exist' "$LOG"; echo $?)")"
check "no-test-system: it points at TEST_ALTERNATIVE"         "$(is "$(grep -qF 'make codegen-test' "$LOG"; echo $?)")"
check "no-test-system: it says no assertions ran"             "$(is "$(grep -qF 'no assertions were run' "$LOG"; echo $?)")"
# The distinction that matters. A VERDICT line here would mean the shared target
# judged a run that never happened; the message must be the whole report.
check "no-test-system: the log carries NO verdict line"       "$(is "$(grep -q '^=== VERDICT:' "$LOG" && echo 1 || echo 0)")"
# Captured, not piped: `make test-summary | grep -q` makes grep exit on the
# first match, the writer takes SIGPIPE, and the check reads 141 instead of the
# target's status. Reading the text into a variable keeps the target's exit out
# of it entirely.
SUMMARY=$( (cd "$FIXTURES/no-test-system" && make test-summary SBCL="$SBCL_BIN" QL="$QL_PATH") 2>/dev/null)
case "$SUMMARY" in
  *"has no test system"*) SUMMARY_SAYS_NO_SUITE=0 ;;
  *)                      SUMMARY_SAYS_NO_SUITE=1 ;;
esac
check "no-test-system: test-summary says the same, not 'run make test first'" \
      "$SUMMARY_SAYS_NO_SUITE"

# ── 7. A suite that does not COMPILE: red, unjudged, and never receipted ──
# bd-829.  Measured TWICE in one day in stratodendron-gog: a test file failed to
# read, SBCL aborted before test-verdict.sh ran, the captured log ended in a
# backtrace, `make test` exited 0, and a GREEN gate receipt was written — so the
# next identical run answered "cached … PASS" for a build that compiled nothing.
#
# Two independent faults made that possible, and this case pins both:
#   * the no-test-system guard wrote its marker as a LITERAL into the --eval
#     source, and SBCL echoes every --eval it was given in the
#     PROCESS-EVAL/LOAD-OPTIONS backtrace frame.  So a compile error put the
#     marker in the log and the recipe took its "nothing to judge, exit 0"
#     branch.  The guard now assembles the marker at run time: the exact phrase
#     must appear NOWHERE in this log, while the echoed source is still there
#     (which is what makes the absence mean something rather than just "the
#     guard did not run").
#   * gate-receipt.sh recorded a green receipt for a log holding no conclusion.
#     It now refuses one (its invariant 6), so a future leak of the same shape
#     cannot poison the next run either.  The second, non-FORCE run below is
#     what measures that.
#
# The log is anchored at column 0 on purpose: a backtrace frame is indented and
# wraps the source text mid-line, so "the log mentions X" is never a test.
echo "[7/9] verdict-broken-build / make test — must be RED and unjudged"
LOG=$(log_for "$FIXTURES/verdict-broken-build" test)
(cd "$FIXTURES/verdict-broken-build" && make cache-clean SBCL="$SBCL_BIN" QL="$QL_PATH") >/dev/null 2>&1
run_make "$FIXTURES/verdict-broken-build" test
check "broken-build: make test exits non-zero"                "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "broken-build: the log says FAIL"                       "$(is "$(verdict_is "$LOG" FAIL; echo $?)")"
check "broken-build: the verdict names the real reason"        "$(is "$(grep -q 'no test summary' "$LOG"; echo $?)")"
check "broken-build: the guard's marker is NOT in the log"     "$(is "$(grep -qF 'test: NO TEST SYSTEM' "$LOG" && echo 1 || echo 0)")"
# ...and the reason that is a real check: the guard WAS handed to SBCL, and the
# backtrace echoed its source.  A marker that moved rather than disappeared
# would fail the check above and pass this one — as it should.
check "broken-build: the echoed guard source is there (assembled)" \
      "$(is "$(grep -qF 'NO TEST ~A' "$LOG"; echo $?)")"
check "broken-build: no GREEN receipt was written"            "$(is "$([ ! -d "$FIXTURES/verdict-broken-build/.gate-cache/test" ] && echo 0 || echo 1)")"
# The consequence, not the cause: run it again WITHOUT FORCE=1.  A poisoned
# receipt is invisible in one run and answers every later one.
(cd "$FIXTURES/verdict-broken-build" && make test SBCL="$SBCL_BIN" QL="$QL_PATH") \
  >"/tmp/verdict-broken-build-test-second.txt" 2>&1
RC_SECOND=$?
check "broken-build: the NEXT run is red too (no poisoned receipt)" \
      "$(is "$([ "$RC_SECOND" -ne 0 ] && echo 0 || echo 1)")"
# Deliberately not `grep -q ... || echo 0`: a missing log would then read as a
# pass.  The run must have produced output AND none of it may be a receipt hit.
SECOND_OUT=/tmp/verdict-broken-build-test-second.txt
if [ -s "$SECOND_OUT" ] && ! grep -qF 'cached (' "$SECOND_OUT"; then NO_HIT=0; else NO_HIT=1; fi
check "broken-build: ...and it executed instead of answering 'cached'" \
      "$(is "$NO_HIT")"

# ── 8. OUTPUT_DIR moves the WRITE and the JUDGE together (bd-235) ─────────
# The incident, measured 2026-11-22 in render-parity: `OUTPUT_DIR=/tmp/x- make
# test` captured its log under /tmp/x- and handed test-verdict.sh the SHARED
# /tmp/<system>-test-LATEST.txt.  That file held the PREVIOUS run's green log,
# so five tests that failed to evaluate reported `=== VERDICT: PASS`.  A false
# green, printed by the one check that exists to prevent false greens.
#
# The decoy is the whole check: seed the shared path with a green log, then run
# a fixture whose suite really is red with OUTPUT_DIR pointing at a scratch
# directory.  Under the old wiring the verdict read the decoy; now it must read
# the file it wrote, and the verdict line itself names that file.
echo "[8/9] bd-235: OUTPUT_DIR moves the log AND the verdict"
DECOY=$(log_for "$FIXTURES/verdict-eval-fail" test)
printf '=== decoy: a GREEN log from an earlier run ===\n;; Summary:\nPassed:     1\nFailed:     0\nSkipped:    0\n=== VERDICT: PASS (target: test, log: %s) ===\n' "$DECOY" >"$DECOY"
OUTDIR=$(mktemp -d /tmp/test-trust-outdir.XXXXXX)
OUT_LOG="$OUTDIR/test-LATEST.txt"
run_make "$FIXTURES/verdict-eval-fail" test OUTPUT_DIR="$OUTDIR/"
check "bd-235: OUTPUT_DIR is where the log landed" \
      "$(is "$([ -s "$OUT_LOG" ] && echo 0 || echo 1)")"
check "bd-235: the verdict names the file this run wrote" \
      "$(is "$(tail -1 "$OUT_LOG" | grep -qF "log: $OUT_LOG)" && echo 0 || echo 1)")"
check "bd-235: ...and it says FAIL, not the decoy's PASS" \
      "$(is "$(verdict_is "$OUT_LOG" FAIL; echo $?)")"
check "bd-235: make test still exits non-zero" \
      "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
# A fake PASS parked at the shared path would lie to the next `make test-summary`
# run from that fixture, so remove the decoy once it has done its job.
rm -f "$DECOY"
rm -rf "$OUTDIR"

# ── 9. The verdict script's own gates, on synthetic logs ──────────────────
echo "[9/9] test-verdict.sh — one gate at a time, no Lisp involved"
SYNTH=$(mktemp -d /tmp/test-trust-synth.XXXXXX)
GREEN="=== x ===
;; Summary:
Passed:     3
Failed:     0
Skipped:    0"

# synth <name> <log-body> [rc] — writes the body, runs the verdict, sets VRC
synth() {
  local log="$SYNTH/$1.txt"
  printf '%b\n' "$2" >"$log"
  bash "${CL_MK_DIR%/}/test-verdict.sh" --target test --require-summary "$log" "${3:-0}" >/dev/null 2>&1
  VRC=$?
}

synth green "$GREEN"
check "green log with a summary exits 0"                     "$(is "$VRC")"
synth counted "$GREEN\nFailed:     2"
check "a counted failure exits non-zero"                     "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
synth glyph "$GREEN\n  0.000 ✘ PKG::SOME-TEST"
check "a bare ✘ exits non-zero"                              "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
synth failures "$GREEN\n;; Failures:\n  0/0 tests failed in PKG::T"
check "a ;; Failures: block exits non-zero"                  "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
synth no-summary "=== x ===\n; Loading \"foo\""
check "a log with no summary exits non-zero"                 "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
# bd-phe.  MEASURED here before it was fixed: a fiveam log whose summary was
# "Fail: 2" satisfied the summary gate (the pattern accepted "Did N checks") and
# failed none of the parachute detectors, so the verdict was PASS — and
# gate-receipt.sh stored that PASS.  The pattern no longer accepts fiveam, so
# the summary gate is what catches it, and the REASON must say so: a fiveam log
# carries no ✘ and no ";; Failures:", so failing for any other reason would mean
# some unrelated detector fired.
FIVEAM_FAIL="Running test suite SMOKE\n Did 52 checks.\n    Pass: 50 ( 96%)\n    Skip: 0 (  0%)\n    Fail: 2 (  3%)"
synth fiveam-fail "$FIVEAM_FAIL"
check "a fiveam 'Fail: 2' summary exits non-zero"             "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
check "...and fails on the summary, not on an unrelated pattern" \
      "$(is "$(grep -q 'no test summary' "$SYNTH/fiveam-fail.txt" && echo 0 || echo 1)")"
# The clean fiveam case pins the DECISION rather than the symptom: this project
# does not read fiveam's report at all, so even "Fail: 0" is not a pass.  A
# future agent who re-adds "Did N checks" to the pattern turns this check red,
# which is exactly the conversation to have before a fiveam repo can come back.
synth fiveam-clean "Running test suite SMOKE\n Did 52 checks.\n    Pass: 52 (100%)\n    Skip: 0 (  0%)\n    Fail: 0 (  0%)"
check "a CLEAN fiveam summary also exits non-zero (unsupported ≠ passing)" \
      "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
synth green "$GREEN" 7
check "a non-zero command exit fails an otherwise green log" "$(is "$([ "$VRC" -ne 0 ] && echo 0 || echo 1)")"
bash "${CL_MK_DIR%/}/test-verdict.sh" --target test "$SYNTH/does-not-exist.txt" 0 >/dev/null 2>&1
check "a missing log exits non-zero"                         "$(is "$([ "$?" -ne 0 ] && echo 0 || echo 1)")"
rm -f "$SYNTH"/*.txt
rmdir "$SYNTH"

echo ""
if [ "$failed" -eq 0 ]; then
  echo "== test-trust: $checks checks, 0 failed — the test verdict can be trusted =="
  exit 0
fi
echo "== test-trust: $checks checks, $failed FAILED — the test verdict cannot be trusted =="
echo "   logs: /tmp/verdict-*-LATEST.txt"
exit 1
