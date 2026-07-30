;;; fresh-build.lisp — Clear Lisp fasl caches, build from scratch, capture all
;;; compiler conditions into structured output with file/line positions.
;;;
;;; Usage:
;;;   sbcl --script scripts/fresh-build.lisp [project-dir]
;;;
;;;   Defaults to $PWD. Works from any repo that has a Makefile with a `load`
;;;   target, or falls back to direct asdf:load-system (auto-detects system name
;;;   from the .asd file).
;;;
;;; Output (saved to <project>/tmp/):
;;;   fresh-build-<timestamp>.lisp  — structured sexp: ((:summary ...) (:conditions ...))
;;;
;;; Two-pass capture:
;;;   Pass 1: asdf:load-system → load-time conditions (redefinitions, etc.)
;;;   Pass 2: Re-compile each source file → compile-time conditions with file/line info
;;;           Uses sb-c::find-error-context (SLY/SLIME technique) for source positions.
;;;
;;; Exit codes: 0 = loaded ok (warnings tolerated), 1 = load failure.

(require :asdf)

;; ── Load user init (--script mode suppresses ~/.sbclrc) ───────────────────
(dolist (init-path (list (merge-pathnames ".sbclrc" (user-homedir-pathname))
                         (merge-pathnames ".shared-lisp-init" (user-homedir-pathname))))
  (when (probe-file init-path)
    (load init-path :if-does-not-exist nil)))

;; ── Bootstrap Quicklisp ──────────────────────────────────────────────────
(let ((ql-setup (merge-pathnames "quicklisp/setup.lisp"
                                 (user-homedir-pathname))))
  (when (probe-file ql-setup)
    (load ql-setup)))

;; ── Utility: timestamp string ────────────────────────────────────────────
(defun timestamp ()
  (multiple-value-bind (s m h d mo y)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D~2,'0D~2,'0DT~2,'0D~2,'0D~2,'0D" y mo d h m s)))

;; ── Utility: resolve project directory ───────────────────────────────────
(defun project-dir (args)
  (let* ((raw (if args (first args) (uiop:getcwd)))
         (p   (uiop:ensure-directory-pathname raw)))
    (truename p)))

;; ── Utility: safe SBCL-internal function call ────────────────────────────
(defun sv-funcall (name pkg &rest args)
  "Call function NAME (string) in PACKAGE with ARGS, returning NIL on any error."
  (let ((fn (find-symbol name pkg)))
    (when (and fn (fboundp fn))
      (ignore-errors (apply fn args)))))

(defun sv-macroexpand (name pkg &rest args)
  "Macroexpand form (NAME . ARGS) from PACKAGE, returning the expansion."
  (let ((fn (find-symbol name pkg)))
    (when (and fn (macro-function fn))
      (ignore-errors (macroexpand `(,fn ,@args))))))

;; ── Cache clearing ───────────────────────────────────────────────────────
(defun clear-sbcl-cache (project-path)
  "Delete the SBCL fasl cache directory for PROJECT-PATH."
  (let* ((home       (user-homedir-pathname))
         (cache-root (merge-pathnames ".cache/common-lisp/" home)))
    (dolist (sbcl-dir (uiop:subdirectories cache-root))
      (let ((cached-project (merge-pathnames
                             (enough-namestring project-path home)
                             sbcl-dir)))
        (when (uiop:directory-exists-p cached-project)
          (format t "Clearing SBCL cache: ~A~%"
                  (enough-namestring cached-project sbcl-dir))
          (uiop:delete-directory-tree cached-project :validate t
                                      :if-does-not-exist :ignore))))))

(defun clear-local-fasls (project-path)
  "Delete *.fasl and *.dfsl files in PROJECT-PATH tree."
  (dolist (f (append (uiop:directory-files project-path "**/*.fasl")
                     (uiop:directory-files project-path "**/*.dfsl")))
    (format t "Deleting local fasl: ~A~%" (enough-namestring f project-path))
    (delete-file f)))

;; ── Condition capture ────────────────────────────────────────────────────
(defvar *conditions* nil
  "Alist of captured compiler conditions during the build.")

(defvar *error-count* 0)
(defvar *warning-count* 0)
(defvar *style-warning-count* 0)
(defvar *note-count* 0)

(defvar *suppressed-conditions* nil
  "Conditions we silently suppress (e.g. known-harmless redefinitions).")

(defun suppress-p (condition)
  "Return T if CONDITION should be suppressed from the report."
  (declare (ignore condition))
  nil)

(defun classify-severity (condition)
  "Map a condition to :error, :warning, :style-warning, or :note."
  (typecase condition
    (error         :error)
    (style-warning :style-warning)
    (warning       :warning)
    (t             :note)))

(defun extract-source-info (condition)
  "Extract file/source-path from a compiler CONDITION.
Uses sb-c::find-error-context at signal time (SLY technique).
Returns a plist with keys :file :source-path :enclosing-source, or NIL."
  (declare (ignore condition))
  (let* ((pkg  (find-package "SB-C"))
         (ctx  (sv-funcall "FIND-ERROR-CONTEXT" pkg nil))
         (file (sv-funcall "COMPILER-ERROR-CONTEXT-FILE-NAME" pkg ctx)))
    (when file
      (list :file (princ-to-string file)
            :source-path (sv-funcall "COMPILER-ERROR-CONTEXT-ORIGINAL-SOURCE-PATH" pkg ctx)
            :enclosing-source (sv-funcall "COMPILER-ERROR-CONTEXT-ENCLOSING-SOURCE" pkg ctx)))))

(defun source-path-to-line (file source-path)
  "Convert SOURCE-PATH (an integer list from sb-c::find-error-context) to
(cons line column) by reading the source file and counting forms.
Handles depth-1 paths (top-level form indices) reliably; returns NIL
for deeper paths or on error."
  (when (and file source-path (probe-file file))
    (handler-case
        (with-open-file (f file :direction :input)
          (let* ((text (make-array (file-length f) :element-type 'character))
                 (nread (read-sequence text f)))
            (declare (ignore nread))
            ;; For a top-level source-path like (N), skip N forms
            ;; and return the line:col where the Nth form starts.
            (when (cdr source-path)
              (return-from source-path-to-line nil))
            (let ((target (first source-path)))
              (with-input-from-string (s text)
                (let ((start-pos 0))
                  (loop repeat target
                        do (handler-case
                               (read s nil nil)
                             (error () (return-from source-path-to-line nil))))
                  (setf start-pos (file-position s))
                  (handler-case (read s nil nil)
                    (error () (return-from source-path-to-line nil)))
                  ;; Now start-pos is the char position of the target form.
                  ;; Count newlines before it.
                  (let ((line 1) (col 0))
                    (loop for i from 0 below start-pos
                          do (incf col)
                          when (char= (char text i) #\Newline)
                          do (incf line) (setf col 0))
                    (cons line (1+ col))))))))
      (error () nil))))

(defun record-condition (condition)
  "Capture CONDITION into *CONDITIONS* and update counters."
  (let ((sev (classify-severity condition))
        (src (extract-source-info condition))
        (msg (princ-to-string condition)))
    (case sev
      (:error         (incf *error-count*))
      (:warning       (incf *warning-count*))
      (:style-warning (incf *style-warning-count*))
      (:note          (incf *note-count*)))
    (push (list* :severity sev :message msg src) *conditions*)))

(defun condition-handler (condition)
  "Handler for conditions: record, possibly muffle."
  (unless (suppress-p condition)
    (record-condition condition))
  (let ((muffle (find-restart 'muffle-warning condition)))
    (when muffle (invoke-restart muffle))))

;; ── Build: Pass 1 — initial asdf:load-system ─────────────────────────────
(defun detect-system-name (project-path)
  "Find the .asd file in PROJECT-PATH and return the system name."
  (let ((asd-files (uiop:directory-files project-path "*.asd")))
    (when asd-files
      (let* ((asd (first asd-files))
             (name (pathname-name asd)))
        (string-downcase name)))))

(defun load-system-pass (project-path)
  "Pass 1: load the system via asdf:load-system, capturing load-time conditions."
  (push (truename project-path) asdf:*central-registry*)
  (let ((system-name (detect-system-name project-path)))
    (unless system-name
      (error "No .asd file found in ~A" project-path))
    (format t "~%Pass 1: Loading system ~S from ~A…~%" system-name project-path)
    (handler-bind ((style-warning         #'condition-handler)
                   (warning               #'condition-handler)
                   (sb-ext:compiler-note  #'condition-handler))
      (asdf:load-system (intern (string-upcase system-name) :keyword)))
    (format t "Pass 1 complete: ~S loaded.~%" system-name)))

;; ── Build: Pass 2 — recompile each file for file/line info ───────────────
(defun collect-source-files (project-path)
  "Return a list of all .lisp source files in PROJECT-PATH/src/."
  (let ((src-dir (merge-pathnames "src/" project-path)))
    (when (uiop:directory-exists-p src-dir)
      (sort (mapcar (lambda (p) (truename p))
                    (uiop:directory-files src-dir "**/*.lisp"))
            #'string<
            :key #'namestring))))

(defun recompile-pass (project-path)
  "Pass 2: recompile each source file to capture conditions with source info.
sb-c::with-compilation-unit + handler-bind gives fresh sb-c::find-error-context."
  (let ((files (collect-source-files project-path))
        (count-before (length *conditions*)))
    (when files
      (format t "~%Pass 2: Recompiling ~D source files for source locations…~%"
              (length files)))
    (dolist (file files)
      (let ((output (make-pathname :name "__recompile" :type "fasl"
                                   :defaults (merge-pathnames
                                              (make-pathname :directory '(:relative "tmp"))
                                              project-path))))
        (ensure-directories-exist output)
        (handler-case
            ;; eval is needed because with-compilation-unit is a macro and
            ;; referencing sb-c::with-compilation-unit directly hits package locks
            (eval `(sb-c::with-compilation-unit (:override t)
                     (handler-bind ((style-warning #'condition-handler)
                                    (warning #'condition-handler)
                                    (sb-ext:compiler-note #'condition-handler))
                       (compile-file ,(namestring file)
                                     :output-file ,(namestring output)
                                     :verbose nil :print nil))))
          (error (c)
            (format t "  WARNING: compile failed for ~A: ~A~%"
                    (enough-namestring file project-path) c)))))
    ;; Convert source-paths to line:col for all conditions with file info
    (let ((converted 0))
      (dolist (c *conditions*)
        (let ((sp (getf (cddr c) :source-path))
              (file (getf (cddr c) :file)))
          (when (and sp file (not (string= file "LISP"))
                     (not (string= file "unknown")))
            (let ((lc (source-path-to-line file sp)))
              (when lc
                (setf (getf (cddr c) :line) (car lc)
                      (getf (cddr c) :column) (cdr lc))
                (incf converted))))))
      (when (> converted 0)
        (format t "  Converted ~D source-paths to line:col.~%" converted)))
    (let ((new-count (- (length *conditions*) count-before)))
      (format t "Pass 2 complete: ~D new conditions captured.~%" new-count))))

;; ── Reports ──────────────────────────────────────────────────────────────
(defun conditions-by-file ()
  "Group *CONDITIONS* by :file, sorted by count descending."
  (let ((by-file (make-hash-table :test 'equal)))
    (dolist (c *conditions*)
      (let* ((file (getf (cddr c) :file))
             (key  (or file "unknown")))
        (push c (gethash key by-file))))
    (sort (loop for k being the hash-keys of by-file
                for v being the hash-values of by-file
                collect (list k v))
          #'> :key (lambda (e) (length (second e))))))

(defun compute-summary ()
  `(:total-conditions ,(length *conditions*)
    :errors ,*error-count*
    :warnings ,*warning-count*
    :style-warnings ,*style-warning-count*
    :notes ,*note-count*))

(defun determine-exit-code ()
  (if (plusp *error-count*) 1 0))

(defun write-structured-output (out-path)
  "Write the structured build report to OUT-PATH."
  (with-open-file (stream out-path :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (let ((*print-case* :downcase))
      (pprint `((:summary ,(compute-summary))
                (:by-file ,(conditions-by-file))
                (:conditions ,(reverse *conditions*)))
              stream)))
  (format t "~%Structured report → ~A~%" out-path))

;; ── Main ─────────────────────────────────────────────────────────────────
(defun main (args)
  (let* ((project-path (project-dir args))
         (project-name (car (last (pathname-directory project-path))))
         (ts           (timestamp))
         (tmp-dir      (merge-pathnames "tmp/" project-path)))
    (format t "=== fresh-build: ~A at ~A ===~%~%" project-name ts)
    (ensure-directories-exist tmp-dir)

    ;; Phase 0: Clear caches
    (clear-sbcl-cache project-path)
    (clear-local-fasls project-path)
    (terpri)

    ;; Phase 1: Load system (captures load-time conditions)
    (let (build-error)
      (handler-case
          (load-system-pass project-path)
        (error (c)
          (setf build-error c)
          (format t "~%PASS 1 FAILED: ~A~%" c)))

      ;; Phase 2: Recompile for source locations (only if pass 1 succeeded)
      (unless build-error
        (handler-case
            (recompile-pass project-path)
          (error (c)
            (format t "~%PASS 2 FAILED: ~A~%" c))))
      (terpri)

      ;; Write structured output
      (let ((structured-path (merge-pathnames
                              (format nil "fresh-build-~A.lisp" ts)
                              tmp-dir)))
        (write-structured-output structured-path))

      ;; Summary
      (let ((summary (compute-summary)))
        (format t "~%=== Build Summary ===~%")
        (format t "  Errors:        ~D~%" (getf summary :errors))
        (format t "  Warnings:      ~D~%" (getf summary :warnings))
        (format t "  Style-warnings:~D~%" (getf summary :style-warnings))
        (format t "  Notes:         ~D~%" (getf summary :notes))
        (format t "  Total:         ~D~%" (getf summary :total-conditions))
        (format t "~%  (Pass 2 adds file/line positions for per-file conditions)~%"))

      (if build-error
          (progn (format t "~%=== BUILD FAILED ===~%") 1)
          (determine-exit-code)))))

;;; Entry point
(let ((exit-code
       (handler-case
           (main (cdr sb-ext:*posix-argv*))
         (error (c)
           (format *error-output* "~%FATAL: ~A~%" c)
           2))))
  (sb-ext:exit :code exit-code))
