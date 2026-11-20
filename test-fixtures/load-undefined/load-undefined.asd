;;;; load-undefined.asd — fixture for `make load-trust` in cl-project.mk
;;;;
;;;; A system whose only defect is an undefined variable in a docstring that
;;;; ends at an inner double quote (the bd-a8r bug). Nothing else complains: the
;;;; parens balance, the file compiles, and the sole evidence is
;;;;
;;;;   ; caught WARNING:
;;;;   ;   undefined variable: LOAD-UNDEFINED::FLAG
;;;;
;;;; `make load` and `make force-load` must both be RED for it, and the report
;;;; must NAME src/broken.lisp. force-load is the case that mattered: it used to
;;;; grep the load target's log, which it never writes, so its gate could not
;;;; fail and this fixture exited 0 (bd-t5m).
;;;;
;;;; The undefined symbol is a STYLE-WARNING variant of the same bug in
;;;; src/calls.lisp — an undefined FUNCTION — so the detector is proven on both
;;;; condition classes the bead names: "Undefined variable", "Undefined function".

(defsystem "load-undefined"
  :version "0.0.1"
  :description "Fixture: an undefined variable and an undefined function (bd-t5m)."
  :serial t
  :components ((:file "src/broken")
               (:file "src/calls")))
