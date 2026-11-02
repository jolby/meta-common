;;;; empty-tests.lisp — the fixture's "test system" holds no tests on purpose.
;;;; The point of verdict-no-suite is that TEST-OP runs nothing and prints no
;;;; summary, yet exits 0.

(defpackage #:verdict-no-suite/tests
  (:use #:cl))
