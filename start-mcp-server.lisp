;; Must be set before cl-mcp starts to disable the worker pool
(setf (uiop:getenv "MCP_NO_WORKER_POOL") "1")

(asdf:load-asd "/home/jboehland/work/cogen-meta/vendor/cl-mcp/cl-mcp.asd")
(asdf:load-system :cl-mcp :force t)

(cl-mcp:start-http-server :port 3000)
;; => Server running at http://127.0.0.1:3000/mcp
