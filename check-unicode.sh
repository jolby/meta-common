#!/usr/bin/env bash
# Check Lisp source files for Unicode characters (non-ASCII).
# Usage: check-unicode.sh [directory...]
# Default: check all .lisp files under repos/cogen-*/src/

# After finding unicode usage, you can replace found unicode/emoji usage with something like:
# Replace unicode em-dash with ascii "--"
# find cogen-core/src/ cogen-cli/src/ cogen-ai/src/ -name "*.lisp" -exec sed -i 's/\xe2\x80\x94/ -- /g' {} \; && echo "Done"

set -euo pipefail

if [ $# -eq 0 ]; then
  set -- repos/cogen-core/src repos/cogen-cli/src repos/cogen-ai/src
fi

find "$@" -name '*.lisp' -exec grep -Pn '[^\x00-\x7F]' {} + 2>/dev/null

echo "---"
echo "Exit 0 = clean. Matches above show file:line:unicode-char."

