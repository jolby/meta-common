;;;; verdict-broken-build.asd — fixture for `make test-trust` (bd-829).
;;;;
;;;; A tiny ASDF system whose TEST FILE cannot be read: BROKEN is exported by
;;;; nothing, so reading TESTS.LISP signals and the suite never runs.

(defsystem "verdict-broken-build"
  :version "0.0.1"
  :description "Fixture: a test file that does not read (bd-829)."
  :depends-on ("parachute")
  :components ((:file "package") (:file "src"))
  :in-order-to ((test-op (test-op "verdict-broken-build/tests"))))

(defsystem "verdict-broken-build/tests"
  :description "Test system for the verdict-broken-build fixture."
  :depends-on ("verdict-broken-build" "parachute")
  :components ((:file "tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call :parachute :test :verdict-broken-build/tests)))
