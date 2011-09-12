; A small sample of continuation usage within one statement. Works with
; the continuation based interpreter.

(define (f return)
	(return 2)
	3
)

(print "WITH LAMBDA: " (f (lambda (x) x)) "\n")
(print "WITH CALLCC: " (callcc f) "\n")