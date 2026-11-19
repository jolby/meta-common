# Fixture for `make lint-trust` — the docstring trap lives in a SEPARATE ASDF
# system, in a directory the default filter does not look at (bd-lnz).
#
# `make lint` must be RED here and must name test/trap2.lisp. That needs BOTH
# halves of the scope: LINT_EXTRA_SYSTEMS compiles the test system (nothing else
# in the shared Makefile does), and LINT_SOURCE_DIRS lets the report see a hit
# under test/. lint-trust.sh also runs the same fixture with the filter narrowed
# back to src and requires GREEN, which is what proves the widening — rather
# than the extra compile — is what found it.
#
# Uses the real shared Makefile so the self-check exercises the actual lint
# target rather than a copy of it.

PROJECT_SYSTEM := lint-trap-in-test
TEST_SYSTEM := lint-trap-in-test/test

# The fixture is not registered with Quicklisp, so the target must scan ASDF
# source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

LINT_SOURCE_DIRS := src test
LINT_EXTRA_SYSTEMS := lint-trap-in-test/test

include ../../cl-project.mk
