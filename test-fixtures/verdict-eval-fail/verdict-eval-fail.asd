;;;; verdict-eval-fail.asd — fixture for `make test-trust` in cl-project.mk
;;;;
;;;; A tiny ASDF system that reproduces the reporting trap in bd-xvg: the
;;;; suite has one passing test and one test whose body signals an unhandled
;;;; error.  Parachute calls that second case "the test failed to evaluate
;;;; properly"; it is marked ✘ and listed under ";; Failures:", but it is a
;;;; TEST-RESULT and PARACHUTE's summary filters test-results out of the
;;;; counters — so the log still reads "Failed: 0".
;;;;
;;;; `make test-trust` asserts the test target reports FAIL here.

(defsystem "verdict-eval-fail"
  :version "0.0.1"
  :description "Fixture: a suite whose only failure is an unevaluated test."
  :depends-on ("parachute")
  :in-order-to ((test-op (test-op "verdict-eval-fail/tests"))))

(defsystem "verdict-eval-fail/tests"
  :description "Test system for the verdict-eval-fail fixture."
  :depends-on ("verdict-eval-fail" "parachute")
  :components ((:file "tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call :parachute :test :verdict-eval-fail/tests)))
