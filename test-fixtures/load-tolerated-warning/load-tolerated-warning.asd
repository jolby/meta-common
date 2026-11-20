;;;; load-tolerated-warning.asd — fixture for `make load-trust` in cl-project.mk
;;;;
;;;; A system whose compile produces a REAL (not style) WARNING that is benign
;;;; for a load gate: the same function defined twice in one file, which SBCL
;;;; reports as "; caught WARNING: Duplicate definition for X found in one file."
;;;;
;;;; That warning sets COMPILE-FILE's failure-p, so ASDF would abort the load on
;;;; it. The project says so explicitly with LOAD_FORCE_EXTRA — the documented
;;;; escape hatch — and then the load is GREEN:
;;;;
;;;;   LOAD_FORCE_EXTRA := --eval '(setf asdf:*compile-file-failure-behaviour* :warn)'
;;;;
;;;; THIS IS THE "CRIES WOLF" HALF OF bd-t5m. The old predicate grepped for
;;;; "caught WARNING" and re-failed exactly the projects that had used the escape
;;;; hatch, so the hatch did not work. The new verdict tolerates the warning,
;;;; REPORTS it (count and log), and does not gate on it.

(defsystem "load-tolerated-warning"
  :version "0.0.1"
  :description "Fixture: a real WARNING that is benign for a load gate (bd-t5m)."
  :serial t
  :components ((:file "src/defs")))
