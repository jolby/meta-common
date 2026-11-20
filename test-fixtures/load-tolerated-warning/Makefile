# Fixture project for `make load-trust` — see the .asd and load-trust.sh.
#
# Uses the real shared Makefile so the self-check exercises the actual load
# targets (and their one verdict), not a copy of it.

PROJECT_SYSTEM := load-tolerated-warning

# The fixture is not registered with Quicklisp, so the load must scan ASDF
# source registries to find this directory's .asd. This makes every load target
# here use SBCL_RUN, which is what the real projects' load targets do.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk

# The compile WARNING (a duplicate definition) sets COMPILE-FILE's failure-p, so
# ASDF aborts the load unless the project says the warning is tolerable. This is
# the documented escape hatch, and the load verdict must honour it: the point of
# the fixture is that a project which says "this warning is fine" gets a GREEN
# load instead of the old predicate's re-fail on "caught WARNING".
LOAD_FORCE_EXTRA := --eval '(setf asdf:*compile-file-failure-behaviour* :warn)'
