;;;; tests.lisp — the fixture suite that hides a failure from the counters.
;;;;
;;;; ARITHMETIC-WORKS passes, so "Passed:" is non-zero.
;;;; SIGNALS-AN-ERROR throws out of the test body, which parachute reports as
;;;; "The test failed to evaluate properly" (status ✘, listed under
;;;; ";; Failures:") while the "Failed:" counter stays 0.

(defpackage #:verdict-eval-fail/tests
  (:use #:cl #:parachute))

(in-package #:verdict-eval-fail/tests)

(define-test arithmetic-works
  (is = 4 (+ 2 2)))

(define-test signals-an-error
  (error "deliberate fixture error: this test never evaluates"))
