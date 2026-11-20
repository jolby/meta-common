;;;; load-style-warning.asd — fixture for `make load-trust` in cl-project.mk
;;;;
;;;; A system whose compile produces STYLE-WARNINGs and nothing else: an unused
;;;; variable, which SBCL reports as "; caught STYLE-WARNING: The variable X is
;;;; defined but never used." plus the counted summary "; caught 1 STYLE-WARNING
;;;; condition".
;;;;
;;;; `make load` and `make force-load` must be GREEN for it. That is the half of
;;;; bd-t5m that says a load gate must not be red on healthy code: the style
;;;; warning is REAL — the log must still show it — and it is not a defect.

(defsystem "load-style-warning"
  :version "0.0.1"
  :description "Fixture: style-warnings only, so every load target is green (bd-t5m)."
  :serial t
  :components ((:file "src/defs")))
