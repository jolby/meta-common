;;;; warns.lisp — the deliberate compile WARNING of the lint-trust fixture.
;;;;
;;;; A slot whose initform conflicts with its asserted type is exactly the shape
;;;; limited-box's GENERATED region had before flutter-groveller learned to emit
;;;; a type that admits NIL (bd-twd, bd-04b): SBCL warns "Constant NIL conflicts
;;;; with its asserted type DOUBLE-FLOAT", COMPILE-FILE reports failure, and ASDF
;;;; calls the file a failed compile.  It is written by hand HERE so the fixture
;;;; stays a test of `make lint` and not of the generator.

(in-package #:cl-user)

(defclass lint-warns-box ()
  ((width
    :initarg :width
    :reader lint-warns-box-width
    :type double-float
    :initform nil
    :documentation "NIL is this fixture's deliberate type conflict."))
  (:documentation "The slot above is the point of the fixture."))

(defun lint-warns-make (&key width)
  "Make the fixture box, so the class is not dead code."
  (make-instance 'lint-warns-box :width width))
