# Fixture project for `make test-trust` — a "suite" that never runs because
# the system has no test-op.  The pre-bd-xvg test target called this a pass.

PROJECT_SYSTEM := verdict-no-suite

# The fixture is not registered with Quicklisp, so the test target must scan
# ASDF source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk
