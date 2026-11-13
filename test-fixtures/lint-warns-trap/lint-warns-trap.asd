;;;; lint-warns-trap.asd — fixture for `make lint-trust` (bd-twd).
;;;;
;;;; Same warning-producing first file as the lint-warns fixture, then a file
;;;; whose DOCSTRING ends at an inner double quote. The rest of that sentence
;;;; becomes body forms, so the function still compiles and only the compiler's
;;;; undefined-variable warning records the damage (bd-a8r). `make lint` must be
;;;; RED and must name trap.lisp — and because warns.lisp comes FIRST, the red
;;;; cannot be the load failing at warns.lisp: it is the detector surviving a
;;;; warning and still finding the trap behind it.

(defsystem "lint-warns-trap"
  :version "0.0.1"
  :description "Fixture: a warning, then a docstring that swallows its body (bd-twd)."
  :serial t
  :components ((:file "src/warns")
               (:file "src/clean")
               (:file "src/trap")))
