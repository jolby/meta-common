;;; summarize-build.lisp — Print a human-readable summary of a fresh-build
;;; structured output file.
;;;
;;; Usage:
;;;   sbcl --script scripts/summarize-build.lisp <fresh-build-<ts>.lisp>
;;;
;;; Prints: overall counts, per-file heatmap, samples per severity.

(require :asdf)

(defun main (args)
  (unless args
    (format *error-output* "Usage: sbcl --script summarize-build.lisp <file>~%")
    (sb-ext:exit :code 2))
  (let* ((path (first args))
         (d    (with-open-file (f path) (read f)))
         (summary (cadr (assoc :summary d)))
         (by-file (cadr (assoc :by-file d)))
         (conditions (cadr (assoc :conditions d))))
    (format t "File: ~A~%~%" path)
    ;; ── Overall counts ──
    (format t "=== SUMMARY ===~%")
    (format t "Total conditions: ~D~%" (getf summary :total-conditions))
    (format t "  Errors:         ~D~%" (getf summary :errors))
    (format t "  Warnings:       ~D~%" (getf summary :warnings))
    (format t "  Style-warnings: ~D~%" (getf summary :style-warnings))
    (format t "  Notes:          ~D~%" (getf summary :notes))

    ;; ── How many have file info ──
    (let ((with-file (count-if (lambda (c)
                                 (let ((f (getf c :file)))
                                   (and f (not (string= f "LISP"))
                                        (not (string= f "unknown")))))
                               conditions)))
      (format t "  With file path: ~D (~D percent)~%"
              with-file
              (if (plusp (length conditions))
                  (round (* 100 with-file) (length conditions))
                  0)))

    ;; ── Per-file heatmap ──
    (format t "~%=== PER-FILE HEATMAP ===~%")
    (loop for (file conds) in by-file
          for i from 1
          while (<= i 20)
          do (let ((bar-len (min 60 (length conds))))
               (format t "~4D ~A ~A~%"
                       (length conds)
                       (make-string bar-len :initial-element #\#)
                       file)))

    ;; ── Errors (if any) ──
    (let ((errors (remove-if-not (lambda (c) (eq (getf c :severity) :error))
                                 conditions)))
      (when errors
        (format t "~%=== ERRORS (~D) ===~%" (length errors))
        (dolist (c errors)
          (format t "  ~S~%  ~A~%~%" (getf c :file) (getf c :message)))))

    ;; ── Warnings ──
    (let ((warnings (remove-if-not (lambda (c) (eq (getf c :severity) :warning))
                                   conditions)))
      (when warnings
        (format t "~%=== WARNINGS (~D) ===~%" (length warnings))
        (dolist (c warnings)
          (format t "  [~S] ~A~%" (getf c :file) (getf c :message)))))

    ;; ── Sample per severity ──
    (format t "~%=== SAMPLE PER SEVERITY ===~%")
    (let ((shown (make-hash-table)))
      (dolist (c conditions)
        (let* ((sev (getf c :severity))
               (file (getf c :file))
               (msg (getf c :message))
               (sp (getf c :source-path)))
          (when (and file (not (string= file "LISP"))
                     (not (string= file "unknown"))
                     (not (gethash sev shown)))
            (setf (gethash sev shown) t)
            (format t "~%[~A] ~S~%" sev file)
            (format t "  ~A~%" msg)
            (when sp (format t "  source-path: ~S~%" sp))))))

    ;; ── Exit ──
    (if (plusp (getf summary :errors))
        (sb-ext:exit :code 1)
        (sb-ext:exit :code 0))))

;;; Entry point
(handler-case
    (main (cdr sb-ext:*posix-argv*))
  (error (c)
    (format *error-output* "~%FATAL: ~A~%" c)
    (sb-ext:exit :code 2)))
