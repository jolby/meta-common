;;;; lint-warns.asd — fixture for `make lint-trust` in cl-project.mk
;;;;
;;;; A tiny system whose force-load produces a compile WARNING (warns.lisp) and
;;;; whose remaining source has nothing for lint to find (clean.lisp). `make
;;;; lint` must be GREEN for it, AND its log must still show the warning: that
;;;; pair is the assertion (bd-twd). Before the fix, the load died at warns.lisp
;;;; and clean.lisp was never compiled — so "no undefined-symbol warnings" would
;;;; have been true and meaningless, and in the real project (stratodendron) it
;;;; was simply a red precondition instead.

(defsystem "lint-warns"
  :version "0.0.1"
  :description "Fixture: a compile warning with no lint defect (bd-twd)."
  :serial t
  :components ((:file "src/warns")
               (:file "src/clean")))
