;;; parse-build-log.lisp — Parse a make load-capture log file into structured
;;; conditions with file/line positions extracted from SBCL compiler output.
;;;
;;; Usage:
;;;   sbcl --script scripts/parse-build-log.lisp <log-file-path>
;;;
;;; Output: structured sexp to stdout — same format as fresh-build.lisp.
;;;
;;; Parses SBCL compiler diagnostic lines:
;;;   ; file: /path/to/file.lisp
;;;   ; in: DEFUN FOO
;;;   ; caught STYLE-WARNING:
;;;   ;   message text...
;;;   ; caught WARNING:
;;;   ;   message text...

(require :asdf)

;; ── Parser ────────────────────────────────────────────────────────────────

(defun parse-compiler-stream (text)
  "Parse SBCL compiler diagnostic output into structured entries.
Returns a list of plists with keys :file :severity :message :form."
  (let ((entries nil)
        (current-file nil)
        (current-form nil)
        (current-severity nil)
        (current-msg nil)
        (lines (uiop:split-string text :separator '(#\Newline))))
    (labels ((flush-current ()
               (when (and current-file current-severity current-msg)
                 (push `(:file ,current-file
                         :severity ,current-severity
                         :form ,current-form
                         :message ,(string-trim
                                    '(#\Space #\Newline)
                                    (apply #'concatenate 'string
                                           (nreverse current-msg))))
                       entries))
               (setf current-file nil current-form nil
                     current-severity nil current-msg nil)))
      (dolist (line lines)
        (cond
          ;; File location: ; file: /path/to/file.lisp
          ((and (> (length line) 7)
                (string= line "; file:" :end1 7))
           (flush-current)
           (setf current-file (string-trim '(#\Space) (subseq line 7))))
          ;; Form location: ; in: DEFUN FOO
          ((and (> (length line) 5)
                (string= line "; in:" :end1 5))
           (setf current-form (string-trim '(#\Space) (subseq line 5))))
          ;; Severity: ; caught STYLE-WARNING:
          ((and (> (length line) 8)
                (string= line "; caught " :end1 9))
           (let ((saved-file current-file)
                 (saved-form current-form))
             (flush-current)
             (setf current-file (or saved-file "unknown")
                   current-form saved-form)
             (let ((rest (subseq line 9)))
               (cond
                 ((search "STYLE-WARNING" rest :test #'char-equal)
                  (setf current-severity :style-warning))
                 ((search "WARNING" rest :test #'char-equal)
                  (setf current-severity :warning))
                 ((search "ERROR" rest :test #'char-equal)
                  (setf current-severity :error))
                 (t
                  (setf current-severity :note))))))
          ;; Message continuation: lines starting with ";   " or "; "
          ((and current-severity (> (length line) 1)
                (string= line ";" :end1 1))
           (push (subseq line 1) current-msg))
          ;; Non-comment, non-empty line between entries: flush
          ((and current-severity current-msg
                (> (length line) 0)
                (not (string= line ";" :end1 1)))
           (flush-current))))
      (flush-current)
      (nreverse entries))))

;; ── Summary ───────────────────────────────────────────────────────────────

(defun compute-summary (conditions)
  (let ((counts (make-hash-table)))
    (dolist (c conditions)
      (incf (gethash (getf c :severity) counts 0)))
    `(:total-conditions ,(length conditions)
      :errors ,(gethash :error counts 0)
      :warnings ,(gethash :warning counts 0)
      :style-warnings ,(gethash :style-warning counts 0)
      :notes ,(gethash :note counts 0))))

(defun conditions-by-file (conditions)
  (let ((by-file (make-hash-table :test 'equal)))
    (dolist (c conditions)
      (let ((key (or (getf c :file) "unknown")))
        (push c (gethash key by-file))))
    (sort (loop for k being the hash-keys of by-file
                for v being the hash-values of by-file
                collect (list k v))
          #'> :key (lambda (e) (length (second e))))))

;; ── Main ──────────────────────────────────────────────────────────────────

(defun main (args)
  (unless args
    (format *error-output* "Usage: sbcl --script parse-build-log.lisp <log-file>~%")
    (sb-ext:exit :code 2))
  (let* ((log-path (first args))
         (text (uiop:read-file-string log-path))
         (conditions (parse-compiler-stream text))
         (summary (compute-summary conditions))
         (by-file (conditions-by-file conditions)))
    ;; Write structured output to stdout
    (let ((*print-case* :downcase))
      (pprint `((:summary ,summary)
                (:by-file ,by-file)
                (:conditions ,conditions))))
    (terpri)
    (if (plusp (getf summary :errors))
        (sb-ext:exit :code 1)
        (sb-ext:exit :code 0))))

;;; Entry point
(handler-case
    (main (cdr sb-ext:*posix-argv*))
  (error (c)
    (format *error-output* "~%FATAL: ~A~%" c)
    (sb-ext:exit :code 2)))
