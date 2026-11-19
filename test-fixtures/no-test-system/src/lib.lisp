;;;; lib.lisp — the fixture's only file. Nothing to test, on purpose.

(in-package #:cl-user)

(defun no-test-system-double (x)
  "Double X. There is no suite here, which is the fixture's whole point."
  (* 2 x))
