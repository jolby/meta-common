# Fixture project for `make test-trust` — a genuinely green suite.
#
# Uses the real shared Makefile so the self-check exercises the actual test
# target, not a copy of it.

PROJECT_SYSTEM := verdict-pass

# The fixture is not registered with Quicklisp, so the test target must scan
# ASDF source registries to find this directory's .asd.
ASDF_SOURCE_REGISTRY := yes

include ../../cl-project.mk

# bd-8dn: two fixture-local digest inputs, so `make test-receipts` proves the
# SELECTOR STAMPING mechanism where it is implemented.  LITERAL exercises
# GATE_STAMPS_<gate> (a literal name=value, the hook a project uses for
# something like "which flutter version does this gate measure"); FROM_ENV
# exercises --stamp-env (a value read out of the environment, which is how PKG,
# REPORT and EVAL are keyed).
#
# They are DELIBERATELY different variables: on one variable a broken --stamp
# would be masked by a working --stamp-env and the checks would prove neither.
# Both come AFTER the include, because cl-project.mk sets GATE_STAMP_ENVS with
# ?= -- appending before it would define the variable early and silently drop
# the PKG/REPORT/EVAL stamps the rest of test-receipts.sh relies on.
GATE_STAMPS_test += literal=$(LITERAL)
GATE_STAMP_ENVS += FROM_ENV
export FROM_ENV
