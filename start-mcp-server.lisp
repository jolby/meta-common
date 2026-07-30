;; start-mcp-server.lisp — Launch an MCP server for a CL project
;;
;; Usage: sbcl --script start-mcp-server.lisp
;;
;; Override the ASDF path via environment variable:
;;   CL_MCP_ASD=/path/to/cl-mcp.asd sbcl --script start-mcp-server.lisp
;;
;; Or set it in your sub-repo Makefile before including cl-project.mk:
;;   MCP_ASD_PATH := ../vendor/cl-mcp/cl-mcp.asd

;; Must be set before cl-mcp starts to disable the worker pool
(setf (uiop:getenv "MCP_NO_WORKER_POOL") "1")

(let ((asd-path (or (uiop:getenv "CL_MCP_ASD")
                    (probe-file "../vendor/cl-mcp/cl-mcp.asd")
                    (error "CL_MCP_ASD not set and ../vendor/cl-mcp/cl-mcp.asd not found.~%~
                            Set the environment variable or place cl-mcp at ../vendor/cl-mcp/"))))
  (asdf:load-asd asd-path)
  (asdf:load-system :cl-mcp :force t))

(cl-mcp:start-http-server :port 3000)
;; => Server running at http://127.0.0.1:3000/mcp
