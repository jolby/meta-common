;;;; defs.lisp — an unused variable, and nothing else wrong.
;;;;
;;;; `unused-thing` is deliberately never referenced: SBCL then emits
;;;; "; caught STYLE-WARNING: The variable UNUSED-THING is defined but never
;;;; used." and "; caught 1 STYLE-WARNING condition". There is no IGNORE
;;;; declaration on purpose — that would silence the very warning this fixture
;;;; exists to show, and the fixture would then pass for the wrong reason.
;;;;
;;;; Both lines are tolerated by the load verdict, and both must still be IN the
;;;; log: a fixture whose warning stopped appearing would prove nothing about
;;;; tolerating it.

(in-package #:cl-user)

(defun load-style-warning-probe (unused-thing)
  "Return :OK. UNUSED-THING is unreferenced on purpose (see the file comment)."
  :ok)
