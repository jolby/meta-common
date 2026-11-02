;;;; verdict-no-suite.asd — fixture for `make test-trust` in cl-project.mk
;;;;
;;;; A system whose TEST-OP does nothing: the test system exists and loads,
;;;; but nothing anywhere declares an `:in-order-to ((test-op ...))`, so
;;;; `asdf:test-system` prints no summary and SBCL exits 0.  Nothing is
;;;; marked ✘ and "Failed:" never appears, so the pre-bd-xvg test target
;;;; reported success for a suite that never ran (bd-xvg title).
;;;; `make test-trust` asserts the target reports FAIL.

(defsystem "verdict-no-suite"
  :version "0.0.1"
  :description "Fixture: a system whose test-op runs nothing."
  :depends-on ("parachute"))

(defsystem "verdict-no-suite/tests"
  :description "Test system that defines a package and no tests."
  :depends-on ("verdict-no-suite")
  :components ((:file "empty-tests")))
