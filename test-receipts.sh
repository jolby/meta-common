#!/usr/bin/env bash
# test-receipts.sh — end-to-end proof that gate receipts work through the REAL
# make targets (bd-sbf).  Companion to `gate-receipt.sh selftest`, which proves
# the tool in isolation; this one proves the wiring in cl-project.mk.
#
# Each assertion runs a fixture system through the shared target, with SBCL
# behind a counting wrapper, so "the gate did not run" is a fact about a
# process that would have started, not an inference from timing.
#
#   1  a green run executes and exits 0, and an identical second run is a HIT:
#      no SBCL process, exit 0, and the -LATEST.txt is byte-identical to the
#      first run's (the inspection surface, AGENTS.md "inspect, never re-run")
#   2  FORCE=1 re-runs despite the identical digest
#   3  `make test-package PKG=...` is keyed by the variant: same PKG hits, a
#      different designator for the same package MISSES (a hit there would
#      restore the other run's verdict)
#   4  `make test-eval EVAL=...` is keyed by the form
#   5  a red gate is never receipted: it runs again, and again
#   6  `make cache-clean` empties the store and the next run executes
#   7  a changed input (one byte in the suite) forces a miss
#   8  the STAMPING mechanism: GATE_STAMPS_<gate> (a literal name=value) and
#      --stamp-env (a value read from the environment) each change the digest
#      when they change, and an UNSET --stamp-env is a stable empty value
#      rather than "nothing recorded" (bd-8dn)
#
# The numbers below are the section numbers the run prints.
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
echo "[1/8] a green gate, twice — the second must be a hit"
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
echo "[2/8] FORCE=1 must re-run a receipted gate"
: >"$COUNTER"
FORCE=1 run_make "$GREEN" test
check "FORCE=1 exits 0"                                     "$(is "$RC")"
check "FORCE=1 executed SBCL"                               "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"

# ── 4. test-package is keyed by PKG ──────────────────────────────────────
echo "[3/8] test-package: the variant (PKG) is part of the key"
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
echo "[4/8] test-eval: the form (EVAL) is part of the key"
: >"$COUNTER"
run_make "$GREEN" test-eval 'EVAL=(format t "~&one.~%")'
check "test-eval runs"                                      "$(is "$RC")"
check "test-eval executed SBCL"                             "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
run_make "$GREEN" test-eval 'EVAL=(format t "~&one.~%")'
check "the same form is a hit"                              "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
run_make "$GREEN" test-eval 'EVAL=(format t "~&two.~%")'
check "a different form MISSES"                             "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"

# ── 6. a red gate is never receipted ─────────────────────────────────────
echo "[5/8] a red gate must run every time"
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
echo "[6/8] cache-clean must empty the store"
: >"$COUNTER"
run_make "$GREEN" cache-clean
check "cache-clean exits 0"                                 "$(is "$RC")"
check "cache-clean leaves no receipts"                      "$(is "$([ -z "$(find "$CACHE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ] && echo 0 || echo 1)")"
run_make "$GREEN" test
check "the run after a clean executes SBCL again"           "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"

# ── 8. a changed input invalidates ───────────────────────────────────────
echo "[7/8] a changed input must force a miss"
SRC=$GREEN/tests.lisp
cp -f "$SRC" "$SCRATCH/tests.lisp.orig"
run_make "$GREEN" test
check "the unchanged tree is a hit"                         "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
printf '\n;; touched by test-receipts.sh\n' >>"$SRC"
run_make "$GREEN" test
check "one changed byte in the suite MISSES"                "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"
cp -f "$SCRATCH/tests.lisp.orig" "$SRC"
run_make "$GREEN" cache-clean

# ── 8. the stamping mechanism (bd-8dn) ───────────────────────────────────
# The verdict-pass fixture carries two digest inputs of its own (see its
# Makefile): GATE_STAMPS_test += literal=$(LITERAL) and GATE_STAMP_ENVS +=
# FROM_ENV.  Nothing above can see them.  [3/8] and [4/8] touch --stamp-env only
# through values those gates ALREADY vary (PKG, EVAL), so they would pass with
# the mechanism half-broken, and --stamp had no test at all — which is how
# bd-gsj's un-stamped fixture selector shipped.  Each assertion below is one run
# separated from the run before it by exactly ONE stamp.
echo "[8/8] the stamping mechanism: a literal --stamp and an environment --stamp-env"
: >"$COUNTER"
run_make "$GREEN" cache-clean
LITERAL=one run_make "$GREEN" test
check "the first stamped run executes"                      "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
LITERAL=one run_make "$GREEN" test
check "the same --stamp value is a hit"                     "$(is "$([ "$(runs)" -eq 1 ] && echo 0 || echo 1)")"
LITERAL=two run_make "$GREEN" test
check "a different --stamp value MISSES"                    "$(is "$([ "$(runs)" -eq 2 ] && echo 0 || echo 1)")"
FROM_ENV=a run_make "$GREEN" test LITERAL=two
check "a --stamp-env value MISSES"                          "$(is "$([ "$(runs)" -eq 3 ] && echo 0 || echo 1)")"
# The inverse direction is the one that matters for safety: GATE_STAMP_ENVS is
# applied to EVERY gate, so a stamp that recorded nothing while unset would be
# a silent no-op on the gates that do not set it, and "unset" would be
# indistinguishable from "this gate does not have that lever".  Here the unset
# run must HIT the receipt written before the variable was ever set — which is
# only true if the unset value is both RECORDED and stable.
run_make "$GREEN" test LITERAL=two
check "an UNSET --stamp-env hits the run from before it was set" \
      "$(is "$([ "$(runs)" -eq 3 ] && echo 0 || echo 1)")"
run_make "$GREEN" cache-clean

echo ""
if [ "$failed" -eq 0 ]; then
  echo "== test-receipts: $checks checks, 0 failed — receipts are wired correctly =="
  exit 0
fi
echo "== test-receipts: $checks checks, $failed FAILED — receipts cannot be trusted =="
exit 1
