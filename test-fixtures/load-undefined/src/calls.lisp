;;;; calls.lisp — the same defect in its second condition class: an undefined
;;;; FUNCTION, which SBCL reports as a STYLE-WARNING and the counted summary
;;;; "; caught 1 STYLE-WARNING condition". It is still a real defect — the call
;;;; signals UNDEFINED-FUNCTION the moment it runs — so the load verdict gates
;;;; on it, and "never gate on style-warnings" does not mean "never gate on this".
;;;;
;;;; MEASURED shape of the evidence (SBCL 2.6.8):
;;;;
;;;;   ; file: /path/src/calls.lisp
;;;;   ; caught STYLE-WARNING:
;;;;   ;   undefined function: LOAD-UNDEFINED::MISSING-HELPER
;;;;   ;   Undefined function:
;;;;   ;     LOAD-UNDEFINED::MISSING-HELPER

(in-package #:cl-user)

(defun load-undefined-caller (x)
  "Call a helper that nothing defines — the definition went missing."
  (load-undefined-missing-helper x))
