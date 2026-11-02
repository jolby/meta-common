;;;; tests.lisp — the single passing test of the verdict-pass fixture.

(defpackage #:verdict-pass/tests
  (:use #:cl #:parachute))

(in-package #:verdict-pass/tests)

(define-test arithmetic-works
  (is = 4 (+ 2 2)))
