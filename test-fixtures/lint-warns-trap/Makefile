# Fixture project for `make lint-trust` — the same compile WARNING, then a
# docstring that swallows its body. `make lint` must be RED here, and RED for
# the RIGHT reason: the log must name trap.lisp, not merely report a failed load.
#
# Uses the real shared Makefile so the self-check exercises the actual lint
# target rather than a copy of it.

PROJECT_SYSTEM := lint-warns-trap

# The fixture is not registered with Quicklisp, so the target must scan ASDF
# source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk
