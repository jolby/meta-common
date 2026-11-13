;;;; trap.lisp — the docstring trap, in a file AFTER the warning-producing one.
;;;;
;;;; The docstring below closes at the quote before `hint`, so the rest of the
;;;; sentence is read as body forms: `hint` is an undefined variable and the
;;;; function would signal the first time it ran. Nothing else complains — the
;;;; parens balance, the file compiles, and the only evidence is the compiler's
;;;; warning, which is what `make lint` greps for (bd-a8r, bd-twd).

(in-package #:cl-user)

(defun lint-warns-trap ()
  "Return the field's "hint" text."
  (values :never-reached))
