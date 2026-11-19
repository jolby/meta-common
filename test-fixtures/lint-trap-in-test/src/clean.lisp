;;;; clean.lisp — the primary system's only file, with nothing to find.
;;;;
;;;; The trap is deliberately NOT here: it is in the test system, so this file
;;;; stands for "the part of the tree lint always covered" and makes the RED
;;;; below attributable to the widening rather than to src/.

(in-package #:cl-user)

(defun lint-trap-in-test-clean (x)
  "Double X. There is no docstring trap here, and no undefined symbol."
  (* 2 x))
