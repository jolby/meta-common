# Fixture project for `make test-trust` — a suite that does not COMPILE (bd-829).
#
# The test file uses a symbol its package does not export, so ASDF signals a READ
# error, SBCL aborts, and test-verdict.sh never runs: the captured log ends in a
# backtrace and holds NO verdict line.  Before bd-829 was fixed, that run left
# `make test` exiting 0 and wrote a GREEN gate receipt — the next identical run
# answered "cached … PASS" for a build that compiled nothing.
#
# The backtrace echoes the `--eval` source SBCL was given, which is how the
# marker string of the no-test-system guard used to end up in this log and why
# the recipe took its "nothing was judged, exit 0" branch.  The guard now
# assembles that marker at run time, so `test: NO TEST SYSTEM` appears NOWHERE
# here; test-trust.sh asserts that, and asserts this fixture goes red.

PROJECT_SYSTEM := verdict-broken-build

# The fixture is not registered with Quicklisp, so the test target must scan
# ASDF source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk
