;;;; clean.lisp — a file AFTER the warning-producing one, with nothing to find.
;;;;
;;;; It has to come after warns.lisp in the system order: the whole question is
;;;; whether lint still reaches the files behind a warning.

(in-package #:cl-user)

(defun lint-warns-clean (x)
  "Double X. There is no docstring trap here, and no undefined symbol."
  (* 2 x))
