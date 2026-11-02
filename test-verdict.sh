#!/usr/bin/env bash
# test-verdict.sh — compute the ONE authoritative PASS/FAIL verdict for a
# captured test log, write it into the log last, and exit on it (bd-xvg).
#
#   usage: test-verdict.sh [--require-summary] [--target NAME] <log> [rc]
#
#       --require-summary   FAIL when the log shows no test-framework summary
#                           (a suite that never ran must not pass)
#       --target NAME       label used in the verdict line (default: test)
#       <log>               the captured log (OUTPUT_DIR)<target>-LATEST.txt
#       [rc]                exit status of the test command, if not 0
#
# Exit status: 0 = PASS, 1 = FAIL, 2 = bad usage.
#
# WHY THIS EXISTS
# ---------------
# Neither of the two obvious signals can be trusted:
#
#   * SBCL's exit status is not a test result.  `make test` binds
#     cl-user::*exit-on-test-failures* to NIL on purpose (binding it T makes
#     parachute call sb-ext:exit from inside asdf:test-system, which ASDF
#     unwinds into a "compilation unit aborted / caught 1 fatal ERROR" banner
#     even on a passing run).  So SBCL exits 0 with failing tests.
#
#   * Parachute's "Failed:" counter is not a test result either.  Its
#     summarize method filters TEST-RESULT instances out of the counters, and
#     a test that fails to evaluate (an unhandled error in the test body) is
#     one of those.  Such a test is marked "✘" and listed under
#     ";; Failures:" while the summary still reads "Failed: 0".
#
# So the verdict is computed here, from the log, after every check has run,
# and written into the log as its LAST line.  A reader who stops at
# "Failed: 0" or at EOF gets the same answer: PASS or FAIL.
#
# Every reason for a FAIL is written into the verdict block, so the log
# explains itself (the old target printed its error to the terminal only).

set -uo pipefail

TARGET=test
REQUIRE_SUMMARY=no

while [ $# -gt 0 ]; do
  case "$1" in
    --require-summary) REQUIRE_SUMMARY=yes; shift ;;
    --target) TARGET=${2:-}; shift 2 ;;
    --) shift; break ;;
    -*) echo "test-verdict.sh: unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

LOG=${1:-}
if [ -z "$LOG" ]; then
  echo "usage: test-verdict.sh [--require-summary] [--target NAME] <log> [rc]" >&2
  exit 2
fi
RC=${2:-0}
[ -z "$RC" ] && RC=0

# What a framework's summary line looks like.  Override for a project whose
# test framework prints something else (or set TEST_REQUIRE_SUMMARY=no to
# drop the "did the suite run at all" gate).
SUMMARY_PATTERN=${TEST_SUMMARY_PATTERN:-^(;; Summary:|Total:|Running test suite| *Did [0-9]+ checks?)}

reasons=()
add_reason() { reasons+=("$1"); }

if [ "$RC" -ne 0 ]; then
  add_reason "the test command exited $RC"
fi

if [ ! -f "$LOG" ]; then
  add_reason "the log $LOG was never created — the test command did not run"
else
  if grep -qE '^Failed:[[:space:]]*[1-9]' "$LOG"; then
    add_reason "the summary counts failed results ($(grep -E '^Failed:' "$LOG" | tail -1 | tr -s '[:space:]' ' ' | sed 's/^ //'))"
  fi

  if grep -qE '^;; Failures:' "$LOG"; then
    add_reason "the ';; Failures:' block is non-empty (it includes tests that failed to evaluate, which the counters ignore)"
  fi

  if grep -q 'failed to evaluate properly' "$LOG"; then
    add_reason "$(grep -c 'failed to evaluate properly' "$LOG") test(s) failed to evaluate properly"
  fi

  # Belt and braces: the glyph that parachute prints for a failed result.
  # The count is meaningless (child assertions share it); its presence is not.
  if grep -q '✘' "$LOG"; then
    add_reason "the log contains the ✘ failure glyph"
  fi

  if [ "$REQUIRE_SUMMARY" = yes ]; then
    if [ "${TEST_REQUIRE_SUMMARY:-yes}" = yes ] && ! grep -qE "$SUMMARY_PATTERN" "$LOG"; then
      add_reason "no test summary in the log — the suite did not run"
    fi
  fi
fi

if [ ${#reasons[@]} -eq 0 ]; then
  VERDICT=PASS
else
  VERDICT=FAIL
fi

# Write the verdict into the log LAST, and echo it to the terminal.  The
# reasons come first so the verdict line can be the log's final line: a
# reader who stops at EOF gets the conclusion, and `tail -1` is the verdict.
{
  echo ""
  if [ "$VERDICT" = FAIL ]; then
    echo "=== VERDICT reasons ==="
    for reason in "${reasons[@]}"; do
      echo "  - $reason"
    done
  fi
  echo "=== VERDICT: $VERDICT (target: $TARGET, log: $LOG) ==="
} | tee -a "$LOG"

if [ "$VERDICT" = FAIL ]; then
  exit 1
fi
exit 0
