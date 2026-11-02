;;;; verdict-pass.asd — fixture for `make test-trust` in cl-project.mk
;;;;
;;;; A tiny ASDF system whose suite really passes.  `make test-trust` asserts
;;;; that the shared test target reports PASS for it and exits 0, so a fix
;;;; that makes every run fail is caught too.

(defsystem "verdict-pass"
  :version "0.0.1"
  :description "Fixture: a genuinely green suite (one passing test)."
  :depends-on ("parachute")
  :in-order-to ((test-op (test-op "verdict-pass/tests"))))

(defsystem "verdict-pass/tests"
  :description "Test system for the verdict-pass fixture."
  :depends-on ("verdict-pass" "parachute")
  :components ((:file "tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call :parachute :test :verdict-pass/tests)))
