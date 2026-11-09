#!/usr/bin/env bash
# test-receipts.sh — end-to-end proof that gate receipts work through the REAL
# make targets (bd-sbf).  Companion to `gate-receipt.sh selftest`, which proves
# the tool in isolation; this one proves the wiring in cl-project.mk.
#
# Each assertion runs a fixture system through the shared target, with SBCL
# behind a counting wrapper, so "the gate did not run" is a fact about a
# process that would have started, not an inference from timing.
#
#   1  a green run executes and exits 0
#   2  an identical second run is a HIT: no SBCL process, exit 0, and the
#      -LATEST.txt is byte-identical to the first run's (the inspection
#      surface, AGENTS.md "inspect, never re-run")
#   3  FORCE=1 re-runs despite the identical digest
#   4  `make test-package PKG=...` is keyed by the variant: same PKG hits, a
#      different designator for the same package MISSES (a hit there would
#      restore the other run's verdict)
#   5  `make test-eval EVAL=...` is keyed by the form
#   6  a red gate is never receipted: it runs again, and again
#   7  `make cache-clean` empties the store and the next run executes
#
#   usage: test-receipts.sh <cl-make-dir> [sbcl-binary] [quicklisp-setup]
#
# Exit status 0 means every assertion held.

set -uo pipefail

CL_MK_DIR=${1:?usage: test-receipts.sh <cl-make-dir> [sbcl] [quicklisp-setup]}
SBCL_BIN=${2:-sbcl}
QL_PATH=${3:-$HOME/quicklisp/setup.lisp}
FIXTURES="${CL_MK_DIR%/}/test-fixtures"
GREEN="$FIXTURES/verdict-pass"
RED="$FIXTURES/verdict-eval-fail"
GREEN_PKG=':verdict-pass/tests'
GREEN_PKG_ALT=':verdict-pass.tests'

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/test-receipts.XXXXXX")
COUNTER=$SCRATCH/sbcl-count.txt
CACHE=$SCRATCH/cache
SB="$SCRATCH/sbcl-counting"

cleanup() { [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf -- "$SCRATCH"; }
trap cleanup EXIT

cat >"$SB" <<'EOS'
#!/usr/bin/env bash
# Counts the SBCL processes a gate STARTS.  A receipt hit must not add one.
# `--version` is excluded: gate-receipt.sh asks the compiler for its version
# when it builds a digest, which is bookkeeping, not a gate run.
case "${1-}" in
  --version) exec @SBCL@ "$@" ;;
esac
echo x >>@COUNTER@
exec @SBCL@ "$@"
EOS
sed -i "s|@SBCL@|$SBCL_BIN|g; s|@COUNTER@|$COUNTER|g" "$SB"
chmod +x "$SB"
: >"$COUNTER"

checks=0
failed=0
check() { # check <description> <0 = held, 1 = violated>
  checks=$((checks + 1))
  if [ "$2" -eq 0 ]; then printf '  ok    %s\n' "$1"
  else printf '  FAIL  %s\n' "$1"; failed=$((failed + 1)); fi
}
is() { [ "$1" -eq 0 ] && echo 0 || echo 1; }
runs() { wc -l <"$COUNTER" | tr -d ' '; }

# run_make <fixture-dir> [make-args...] — sets RC and OUT (terminal output).
OUT=
run_make() {
  local dir=$1; shift
  local term=$SCRATCH/terminal.txt
  ( cd "$dir" && make "$@" SBCL="$SB" QL="$QL_PATH" GATE_CACHE_DIR="$CACHE" ) \
    >"$term" 2>&1
  RC=$?
  OUT=$(cat "$term")
}

log_for() { printf '/tmp/%s-%s-LATEST.txt\n' "$(basename "$1")" "$2"; }

echo "== test-receipts: fixtures under $FIXTURES =="
echo "   receipts: $CACHE"

# ── 1/2. the same green run twice ─────────────────────────────────────────
echo "[1/7] a green gate, twice — the second must be a hit"
LOG=$(log_for "$GREEN" test)
: >"$COUNTER"
run_make "$GREEN" test
check "green run exits 0"                                  "$(is "$RC")"
check "green run executed SBCL"                            "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
cp -f "$LOG" "$SCRATCH/log.first"
run_make "$GREEN" test
check "the second run exits 0"                             "$(is "$RC")"
check "the second run started NO SBCL process"             "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
check "the second run says 'cached' and names the log"      "$(is "$(printf '%s' "$OUT" | grep -q "cached.*$LOG" && echo 0 || echo 1)")"
check "the second run restores the log byte-for-byte"       "$(is "$(cmp -s "$LOG" "$SCRATCH/log.first" && echo 0 || echo 1)")"
check "the restored log still carries the verdict line"     "$(is "$(grep -q '^=== VERDICT: PASS' "$LOG" && echo 0 || echo 1)")"

# ── 3. FORCE=1 ───────────────────────────────────────────────────────────
echo "[2/7] FORCE=1 must re-run a receipted gate"
: >"$COUNTER"
FORCE=1 run_make "$GREEN" test
check "FORCE=1 exits 0"                                     "$(is "$RC")"
check "FORCE=1 executed SBCL"                               "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"

# ── 4. test-package is keyed by PKG ──────────────────────────────────────
echo "[3/7] test-package: the variant (PKG) is part of the key"
: >"$COUNTER"
run_make "$GREEN" test-package "PKG=$GREEN_PKG"
check "test-package runs"                                   "$(is "$RC")"
check "test-package executed SBCL"                          "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
run_make "$GREEN" test-package "PKG=$GREEN_PKG"
check "test-package with the same PKG is a hit"             "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
run_make "$GREEN" test-package "PKG=$GREEN_PKG_ALT"
check "the dotted designator is a different gate (it MISSES)" \
      "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"

# ── 5. test-eval is keyed by EVAL ────────────────────────────────────────
echo "[4/7] test-eval: the form (EVAL) is part of the key"
: >"$COUNTER"
run_make "$GREEN" test-eval 'EVAL=(format t "~&one.~%")'
check "test-eval runs"                                      "$(is "$RC")"
check "test-eval executed SBCL"                             "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
run_make "$GREEN" test-eval 'EVAL=(format t "~&one.~%")'
check "the same form is a hit"                              "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
run_make "$GREEN" test-eval 'EVAL=(format t "~&two.~%")'
check "a different form MISSES"                             "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"

# ── 6. a red gate is never receipted ─────────────────────────────────────
echo "[5/7] a red gate must run every time"
: >"$COUNTER"
BEFORE=$(find "$CACHE" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)
run_make "$RED" test
check "the red gate exits non-zero"                         "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
run_make "$RED" test
check "the red gate exits non-zero again"                   "$(is "$([ "$RC" -ne 0 ] && echo 0 || echo 1)")"
check "the red gate executed SBCL both times"               "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"
AFTER=$(find "$CACHE" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)
check "no receipt was stored for it"                        "$(is "$([ "$BEFORE" = "$AFTER" ] && echo 0 || echo 1)")"

# ── 7. cache-clean ───────────────────────────────────────────────────────
echo "[6/7] cache-clean must empty the store"
: >"$COUNTER"
run_make "$GREEN" cache-clean
check "cache-clean exits 0"                                 "$(is "$RC")"
check "cache-clean leaves no receipts"                      "$(is "$([ -z "$(find "$CACHE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ] && echo 0 || echo 1)")"
run_make "$GREEN" test
check "the run after a clean executes SBCL again"           "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"

# ── 8. a changed input invalidates ───────────────────────────────────────
echo "[7/7] a changed input must force a miss"
SRC=$GREEN/tests.lisp
cp -f "$SRC" "$SCRATCH/tests.lisp.orig"
run_make "$GREEN" test
check "the unchanged tree is a hit"                         "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
printf '\n;; touched by test-receipts.sh\n' >>"$SRC"
run_make "$GREEN" test
check "one changed byte in the suite MISSES"                "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"
cp -f "$SCRATCH/tests.lisp.orig" "$SRC"
run_make "$GREEN" cache-clean

echo ""
if [ "$failed" -eq 0 ]; then
  echo "== test-receipts: $checks checks, 0 failed — receipts are wired correctly =="
  exit 0
fi
echo "== test-receipts: $checks checks, $failed FAILED — receipts cannot be trusted =="
exit 1
