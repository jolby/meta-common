;;;; tests.lisp — unreadable on purpose: BROKEN:TRUNCATE-TO-SHORTEST is unexported.

(defpackage #:verdict-broken-build/tests
  (:use #:cl #:parachute))

(in-package #:verdict-broken-build/tests)

(define-test it-works
  (is equal '(1) (verdict-broken-build:truncate-to-shortest '(1 2))))
