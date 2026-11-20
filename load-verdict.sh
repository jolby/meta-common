#!/usr/bin/env bash
# load-verdict.sh — compute the ONE authoritative PASS/FAIL verdict for a
# captured LOAD log, write it into the log last, and exit on it (bd-t5m).
#
#   usage: load-verdict.sh [--target NAME] [--source DIR]... <log> [rc]
#
#       --target NAME   label used in the verdict line (default: load)
#       --source DIR    a directory that holds THIS PROJECT's own sources.  An
#                       undefined variable or function reported in a file under
#                       one of these directories FAILS the load.  Repeatable.
#                       Default: the current directory.
#       <log>           the captured log, (OUTPUT_DIR)<target>-LATEST.txt
#       [rc]            exit status of the load command, if not 0
#
# Exit status: 0 = PASS, 1 = FAIL, 2 = bad usage.
#
# WHY THIS EXISTS
# ---------------
# The four load targets used to decide "did the load fail?" with one blind grep:
#
#     grep -qE "caught (fatal )?(ERROR|WARNING)" <log>
#
# That predicate is wrong in BOTH directions, and both were measured before
# this file was written (bd-t5m):
#
#   * IT CANNOT FAIL, in force-load.  The recipe grepped $(LOAD_OUTPUT), which
#     is the *load* target's log (/tmp/<system>-load-LATEST.txt).  force-load
#     writes /tmp/<system>-force-load-LATEST.txt, so `grep -q` was reading a
#     file that need not exist; grep exits 2 on that, `if` reads failure, and
#     the gate passed.  MEASURED: a system whose docstring ends at an inner
#     quote (the bd-a8r bug) produced "; caught WARNING: / ; undefined
#     variable: LOADUNDEF3::FLAG" in force-load's own log and `make force-load`
#     still exited 0.
#
#   * IT CRIES WOLF.  `caught WARNING` matches warnings that are benign for a
#     load gate and cannot be fixed by the project: real logs on this machine
#     contain "; caught WARNING: Duplicate definition for G found in one file."
#     and LOOM's "; caught WARNING: LOOM requires the 'if' form to have an
#     'else' clause".  The documented escape hatch for that class is
#     LOAD_FORCE_EXTRA (asdf:*compile-file-failure-behaviour* :warn), and the
#     grep re-failed exactly the projects that had used it.
#
# What actually means "broken" is narrower and is what this script gates on:
#
#   * the load command exited non-zero;
#   * the log was never created, or holds nothing but the capture header;
#   * the compiler reported an ERROR (per-condition or the counted summary);
#   * an undefined variable or function in a file under --source.  This is the
#     bd-a8r class (a docstring that ends at an inner double quote, so the rest
#     of the sentence becomes body forms) and it is a real defect whether SBCL
#     classified it WARNING or STYLE-WARNING.
#
# Everything else is REPORTED, not gated: the tolerated warnings are counted
# and written into the log, so a reader can see them and a future detector can
# be added deliberately.  Style-warnings never gate.
#
# The verdict is computed here after the run and written into the log as its
# LAST line, the way test-verdict.sh does it for test runs (bd-xvg): the
# reader who stops at EOF and the reader who runs `tail -1` get the same answer,
# and the log explains itself.  SBCL's exit status is one input, never the
# verdict — `asdf:load-system ... :force t` can exit 0 having printed an
# undefined variable, and exits non-zero on a dependency's tolerated warning.

set -uo pipefail

TARGET=load
SOURCES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET=${2:-}; shift 2 ;;
    --source) SOURCES+=("${2:-}"); shift 2 ;;
    --) shift; break ;;
    -*) echo "load-verdict.sh: unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

LOG=${1:-}
if [ -z "$LOG" ]; then
  echo "usage: load-verdict.sh [--target NAME] [--source DIR]... <log> [rc]" >&2
  exit 2
fi
RC=${2:-0}

if [ ${#SOURCES[@]} -eq 0 ]; then
  SOURCES=("$(pwd)")
fi

# SBCL prints each condition twice: the detail under "; caught X:" while the
# file compiles, and a counted summary after "; compilation unit finished".
# Both shapes are matched, because either one alone can be the only survivor
# of a log that was truncated or filtered.
ERROR_RE='^; +caught +(([0-9]+|a) +)?(fatal +)?ERROR'
# The counted summary keeps the warning kind in the middle: "; caught 1 fatal
# ERROR condition", which the per-condition regex above would not match if it
# demanded the colon.  It does not — the pattern stops after ERROR — so this
# is the same regex; the comment is the reason it is anchored that way.
UNDEFINED_RE='[Uu]ndefined (variable|function)'
WARNING_DETAIL_RE='^; +caught +WARNING:'
WARNING_COUNT_RE='^; +caught +[0-9]+ +WARNING condition'
HEADER_RE='^=== .* ===$'

reasons=()
add_reason() { reasons+=("$1"); }

if [ "$RC" -ne 0 ]; then
  add_reason "the load command exited $RC"
fi

error_hits=
undefined_report=
tolerated_warning=0
tolerated_style=0

if [ ! -f "$LOG" ]; then
  add_reason "the log $LOG was never created — the load command did not run"
else
  # A log with nothing but capture-output's own header is not evidence that a
  # load happened.  capture-output always writes that header, so this is
  # exactly the "the command ran and produced no output" case.
  if ! grep -qvE "$HEADER_RE" "$LOG" || [ -z "$(grep -vE "$HEADER_RE" "$LOG" | tr -d '[:space:]')" ]; then
    add_reason "the log holds nothing but the capture header — the load produced no output"
  fi

  error_hits=$(grep -E "$ERROR_RE" "$LOG" | head -5 || true)
  if [ -n "$error_hits" ]; then
    n=$(grep -cE "$ERROR_RE" "$LOG" || true)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    add_reason "the compiler reported $n ERROR line(s), the first being: $(printf '%s' "$error_hits" | head -1 | sed 's/^; *//')"
  fi

  # Undefined symbols, SCOPED to this project's own sources.  The shape is the
  # one `make lint` already uses: track the "; file: " header, then report a
  # match only while that file lies under a --source directory.  A dependency's
  # undefined symbol (or a warning from a vendored tree) is not this project's
  # bug and must not gate its load.
  #
  # WHY AN UNDEFINED FUNCTION IS A DEFECT HERE AND NOT A FORWARD REFERENCE: a
  # backward reference (file A calling a function that file B defines later) is
  # legal CL and would be a false positive -- but this log comes from a load
  # whose first form is a plain quickload.  By the time the forced compile runs,
  # every file in the system has been loaded, so a name that is still undefined
  # exists NOWHERE and the call would signal UNDEFINED-FUNCTION the first time it
  # ran.  MEASURED: a two-file fixture whose first file calls the second's
  # function produces no warning at all, while a call to a function defined
  # nowhere produces this one.
  #
  # SBCL writes the symbol on the NEXT line for the deferred summary
  # ("Undefined function:" then "T") and inline for the per-file detail
  # ("undefined function: PKG::FOO").  Both are reported WITH the symbol: a
  # report that names a file and nothing to fix is not actionable.
  dirs_joined=$(printf '%s\n' "${SOURCES[@]}")
  undefined_report=$(awk -v dirs="$dirs_joined" -v re="$UNDEFINED_RE" '
    BEGIN { n = split(dirs, D, "\n") }
    function under(d) {
      sub(/\/+$/, "", d)
      return d != "" && index(path, d "/") == 1
    }
    /^; file: / { path = substr($0, 9) }
    $0 ~ re {
      if (path == "") next
      hit = $0
      # A heading that ends at the colon carries its symbol on the next line.
      if (hit ~ /:[[:space:]]*$/) {
        if ((getline nxt) > 0 && nxt ~ /^; +[^;[:space:]]/) {
          sub(/^; +/, "", nxt)
          hit = hit " " nxt
        }
      }
      for (i = 1; i <= n; i++) {
        if (!under(D[i])) continue
        # Report the path RELATIVE to the source root it matched: that is the
        # name a reader recognises (src/broken.lisp), and it is also what makes
        # the fixture assertions stable across mktemp directories.  The path is
        # printed once per contiguous run of hits in that file.
        rel = substr(path, length(D[i]) + 2)
        if (rel != lastp) { printf "%s\n", rel; lastp = rel }
        printf "    %s\n", hit
        break
      }
    }' "$LOG")
  if [ -n "$undefined_report" ]; then
    files=$(printf '%s\n' "$undefined_report" | grep -vE '^[[:space:]]' | sort -u | tr '\n' ' ' | sed 's/ $//')
    add_reason "an undefined variable or function in this project's own sources: $files"
  fi

  tolerated_warning=$(grep -cE "$WARNING_DETAIL_RE|$WARNING_COUNT_RE" "$LOG" || true)
  tolerated_style=$(grep -cE "^; +caught +STYLE-WARNING:|^; +caught +[0-9]+ +STYLE-WARNING condition" "$LOG" || true)
  case "$tolerated_warning" in ''|*[!0-9]*) tolerated_warning=0 ;; esac
  case "$tolerated_style" in ''|*[!0-9]*) tolerated_style=0 ;; esac
fi

if [ ${#reasons[@]} -eq 0 ]; then
  VERDICT=PASS
else
  VERDICT=FAIL
fi

{
  echo ""
  # What was seen and deliberately not gated on.  Printed even when the verdict
  # is PASS: a tolerated warning that the reader cannot see is a warning that
  # was silently dropped.
  if [ "$tolerated_warning" -gt 0 ] || [ "$tolerated_style" -gt 0 ]; then
    echo "=== warnings tolerated (not a gate) ==="
    if [ "$tolerated_warning" -gt 0 ]; then
      echo "  $tolerated_warning WARNING line(s) — benign for a load gate unless they are"
      echo "  undefined-symbol warnings in this project's own sources"
    fi
    if [ "$tolerated_style" -gt 0 ]; then
      echo "  $tolerated_style STYLE-WARNING line(s)"
    fi
  fi
  if [ -n "$undefined_report" ]; then
    echo "=== undefined symbols in this project's own sources ==="
    printf '%s\n' "$undefined_report"
  fi
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
