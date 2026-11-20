;;;; broken.lisp — the docstring trap: the string closes at the quote before
;;;; `flag`, so the rest of the sentence is read as body forms and `flag` is an
;;;; undefined variable. The function would signal the first time it ran.
;;;;
;;;; MEASURED shape of the evidence (SBCL 2.6.8), which is what load-verdict.sh
;;;; matches:
;;;;
;;;;   ; file: /path/src/broken.lisp
;;;;   ; caught WARNING:
;;;;   ;   undefined variable: LOAD-UNDEFINED::FLAG
;;;;   ;   Undefined variable:
;;;;   ;     LOAD-UNDEFINED::FLAG

(in-package #:cl-user)

(defun load-undefined-trap (x)
  "Set "flag" then return X. The rest of this sentence is not a docstring."
  (values x))
