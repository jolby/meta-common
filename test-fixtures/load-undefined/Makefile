# Fixture project for `make load-trust` — see the .asd and load-trust.sh.
#
# Uses the real shared Makefile so the self-check exercises the actual load
# targets (and their one verdict), not a copy of it.

PROJECT_SYSTEM := load-undefined

# The fixture is not registered with Quicklisp, so the load must scan ASDF
# source registries to find this directory's .asd. This makes every load target
# here use SBCL_RUN, which is what the real projects' load targets do.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk
