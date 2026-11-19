# Fixture project for `make test-trust` — a repo with NO test system (bd-wf7).
#
# PROJECT_SYSTEM is a plain library and there is no "<system>/tests": the
# inherited `test` target used to force-load that system, die with
# SYSTEM-NOT-FOUND, and report VERDICT: FAIL without running a single assertion.
#
# test-trust.sh asserts that `make test` now exits 0, says NO TEST SYSTEM, points
# at TEST_ALTERNATIVE and leaves no VERDICT line — and that a repo WITH a suite
# (verdict-pass, case 1) is unaffected.
#
# Uses the real shared Makefile so the self-check exercises the actual test
# target rather than a copy of it.

PROJECT_SYSTEM := no-test-system

# The fixture is not registered with Quicklisp, so the target must scan ASDF
# source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

# The suite this fixture's project actually runs lives in a target of its own,
# which is the shape flutter-groveller has (its gate is `make codegen-test`).
TEST_ALTERNATIVE := codegen-test

include ../../cl-project.mk
