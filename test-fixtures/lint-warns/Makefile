# Fixture project for `make lint-trust` — a compile WARNING and no lint defect.
#
# Uses the real shared Makefile so the self-check exercises the actual lint
# target rather than a copy of it.

PROJECT_SYSTEM := lint-warns

# The fixture is not registered with Quicklisp, so the target must scan ASDF
# source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk
