# Fixture project for `make test-trust` — the suite whose only failure is a
# test that failed to evaluate.
#
# Uses the real shared Makefile so the self-check exercises the actual test
# target, not a copy of it.

PROJECT_SYSTEM := verdict-eval-fail

# The fixture is not registered with Quicklisp, so the test target must scan
# ASDF source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk
