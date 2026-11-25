;;;; package.lisp — exports NOTHING, deliberately.
;;;;
;;;; TESTS.LISP refers to VERDICT-BROKEN-BUILD:TRUNCATE-TO-SHORTEST.  Because the
;;;; symbol is not exported, the reader signals when the test file is read, so the
;;;; suite fails to load rather than failing an assertion.  That is bd-829's real
;;;; cause, measured in stratodendron-gog ("The symbol TRUNCATE-TO-SHORTEST is not
;;;; external in the GOG.DATA package").

(defpackage #:verdict-broken-build
  (:use #:cl)
  (:export))
