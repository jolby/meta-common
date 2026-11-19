;;;; no-test-system.asd — fixture for `make test-trust` (bd-wf7).
;;;;
;;;; A library with NO test-op and NO "<system>/tests" companion. That is the
;;;; whole point: the shared `test` target must notice, say so, and exit 0,
;;;; instead of force-loading a system that does not exist and calling the
;;;; resulting SYSTEM-NOT-FOUND a failing test run.
;;;;
;;;; Deliberately does NOT depend on parachute: this fixture must not need a
;;;; test framework to prove there is no suite.

(defsystem "no-test-system"
  :version "0.0.1"
  :description "Fixture: a project with no test system at all."
  :serial t
  :components ((:file "src/lib")))
