;;;; trap2.lisp — the docstring trap, in the TEST system (bd-lnz).
;;;;
;;;; The docstring below closes at the quote before `hint`, so the rest of the
;;;; sentence is read as body forms: `hint` is an undefined variable and the
;;;; function would signal the first time it ran. Nothing else complains — the
;;;; parens balance, the file compiles, and the only evidence is the compiler's
;;;; warning, which is what `make lint` greps for (bd-a8r).
;;;;
;;;; This file is in test/, not src/, so a lint that only loads
;;;; PROJECT_SYSTEM never sees it at all and a lint that only reports hits
;;;; under src/ sees it and discards it. Both variables are exercised by the
;;;; fact that this file's warning is reported.

(in-package #:cl-user)

(defun lint-trap-in-test-trap ()
  "Return the field's "hint" text."
  (values :never-reached))
