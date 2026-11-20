;;;; defs.lisp — the same function defined twice in one file.
;;;;
;;;; SBCL reports this as a real WARNING — "; caught WARNING: Duplicate
;;;; definition for LOAD-TOLERATED-WARNING-DUP found in one file." — and that
;;;; sets COMPILE-FILE's failure-p, which ASDF turns into a failed load unless
;;;; the project downgrades it with LOAD_FORCE_EXTRA (see the .asd and Makefile).
;;;;
;;;; The definitions are compatible so the second wins quietly at load time;
;;;; nothing about this project is broken, and the pair is deliberately the
;;;; shape that a naive "any caught WARNING is a failure" predicate rejects.

(in-package #:cl-user)

(defun load-tolerated-warning-dup (x)
  "First definition: double X."
  (* 2 x))

(defun load-tolerated-warning-dup (x)
  "Second definition: also double X, so the redefinition changes no behaviour."
  (* 2 x))
