; This sample does not work correctly because the continuation
; does not contain the complete state.

(define cont nil)

(print "CALLCC RETURN: " (to_s (callcc (lambda (c)
	(begin
		(set cont c)
		true
	)
))) "\n")

(print "CONT: " (to_s cont) "\n")
(cont 1)
(cont 2)