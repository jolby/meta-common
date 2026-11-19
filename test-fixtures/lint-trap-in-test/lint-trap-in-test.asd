;;;; lint-trap-in-test.asd — fixture for `make lint-trust` (bd-lnz).
;;;;
;;;; Two systems on purpose. The trap lives in the TEST system, which is a
;;;; sibling of the primary system rather than a component of it — the same
;;;; shape as a real project's rig or test system. So loading the primary
;;;; system compiles src/ and never opens test/trap2.lisp, and only
;;;; LINT_EXTRA_SYSTEMS brings that file into the lint at all.
;;;;
;;;; The test system carries no test-op and no assertion library: the fixture
;;;; exists to be COMPILED, not run.

(defsystem "lint-trap-in-test"
  :version "0.0.1"
  :description "Fixture: the docstring trap is in a directory outside the default filter."
  :serial t
  :components ((:file "src/clean")))

(defsystem "lint-trap-in-test/test"
  :version "0.0.1"
  :description "Fixture: the test system that owns test/trap2.lisp."
  :depends-on ("lint-trap-in-test")
  :serial t
  :components ((:file "test/trap2")))
