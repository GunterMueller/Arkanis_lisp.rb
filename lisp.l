;
; First some basic and general stuff we use all around the code
;

; Checks if the actual value equals the expected value. If not `error` is called
; with the specified message.
(define assert (lambda (actual expected message)
	(if (eq? expected actual)
		true
		(error (plus (if (nil? message) "assertion failed!" message) " got " (to_s actual)))
	)
))

(assert true true "assert is broken!")

; Returns the second value of a list. Kind of an extention to `first` and
;`rest`.
(define second (lambda (list)
	(first (rest list))
))

(assert (second '(1 2 3)) 2 "second is broken")

(define third (lambda (list)
	(first (rest (rest list)))
))

(assert (third '(1 2 3)) 3 "third is broken")


;
; Environment stuff
;

; Creates a new environment with the specified parent
(define env_new (lambda (parent)
	(cons nil parent)
))

; Defines a new entry in the specified environment
(define env_def (lambda (env key val)
	(begin
		(set_first
			env
			(cons
				(cons key val)
				(first env)
			)
		)
		val
	)
))

; Searches the specified environment for the given key and returns the
; corresponding value. Throws an error if the key could not be found.
(define env_get (lambda (env key)
	(env_search (first env) key (rest env) (lambda (pair)
		(rest pair)
	))
))

; Sets a new value for `key` in the specified environment. If the key does not
; exist an error is thrown.
(define env_set (lambda (env key val)
	(env_search (first env) key (rest env) (lambda (pair)
		(rest (set_rest pair val))
	))
))

; Helper for env_get and env_set. Searches the specified store for `key` and
; continues to search in `parent_env` if the store was completely searched. When
; the key is found the lambda `action` is called with the found key value pair.
; Practically this function encapsulates the key search logic.
(define env_search (lambda (store key parent_env action)
	(if (nil? store)
		; store of this environment is empty
		(if (nil? parent_env)
			; no parent env, search failed
			(error (plus "Could not resolve symbol: " (to_s key)))
			; continue search in the parent env
			(env_search (first parent_env) key (rest parent_env) action)
		)
		; search in the current store
		(if (eq? (first (first store)) key)
			; we found the key, call the action lambda and return whatever it returns
			(action (first store))
			; key not found, continue with next key value pair in store
			(env_search (rest store) key parent_env action)
		)
	)
))

(define test_env (env_new nil))
(assert test_env (cons nil nil) "env_new broken")
(assert (env_def test_env 'a 123) 123 "env_def does not return the set value")
(assert test_env (cons (cons (cons 'a 123) nil) nil) "env_def screwed up the environment with one define")
(env_def test_env 'b 2)
(assert test_env (cons (cons (cons 'b 2) (cons (cons 'a 123) nil)) nil) "env_def screwed up the environment after the second define")
(env_def test_env 'c 3)
(env_def test_env 'd 4)
(env_def test_env 'f 5)
(assert (env_get test_env 'f) 5 "env_get lookup failed")
(assert (env_get test_env 'a) 123 "env_get lookup failed")
(env_set test_env 'a 345)
(assert (env_get test_env 'a) 345 "env_get lookup failed after env_set")
(assert (env_set test_env 'a 456) 456 "env_set does not return the set value")
(assert (env_get test_env 'a) 456 "env_get lookup after env_set failed")


;
; Eval stuff
;

(define global_env (env_new nil))

; the ever mighty eval
(define eval (lambda (ast env)
	(if (symbol? ast)
		(env_get env ast)
		(if (pair? ast)
			(eval_list ast env)
			ast
		)
	)
))

(define eval_list (lambda (ast env)
	(eval_list_apply
		(eval (first ast) env)
		(rest ast)
		env
	)
))

(define eval_list_apply (lambda (func args env)
	; All buildins are lambdas in the environment `env`. So if it's a build in `func` will be the
	; corresponding lambda (looked up by `eval_list`).
	(if (lambda? func)
		(func args env)
	(if ((env_get env 'lisp_lambda?) func)
		((env_get env 'exec_lambda) func args env)
	; else
		(error (plus "Unknown build in: " (to_s func)))
	))
	
	;(if (lisp_lambda? func)
	;	(eval_exec_lambda func args env)
	; else
	;	(error (plus "Unknown build in: " (to_s func)))
	;))
))


;
; Pair opterations
;

(env_def global_env 'cons (lambda (args env)
	(cons
		(eval (first args) env)
		(eval (first (rest args)) env)
	)
))

(env_def global_env 'first (lambda (args env)
	(first (eval (first args) env))
))

(env_def global_env 'rest (lambda (args env)
	(rest (eval (first args) env))
))

(assert (eval '(first (cons 1 2)) global_env) 1 "first is broken")
(assert (eval '(rest (cons 1 2)) global_env) 2 "rest is broken")


;
; Arithmetic operations
;

(env_def global_env 'plus (lambda (args env)
	(if (and (atom? (first args)) (atom? (second args)))
		(if (nil? (rest (rest args)))
			(plus (eval (first args) env) (eval (second args) env))
			((env_get global_env 'plus) (cons
				(plus (eval (first args) env) (eval (second args) env))
				(rest (rest args))
			) env)
		)
		(error "plus can only add atoms")
	)
))

(env_def global_env 'minus (lambda (args env)
	(if (and (atom? (first args)) (atom? (second args)))
		(if (nil? (rest (rest args)))
			(minus (eval (first args) env) (eval (second args) env))
			((env_get global_env 'minus) (cons
				(minus (eval (first args) env) (eval (second args) env))
				(rest (rest args))
			) env)
		)
		(error "minus can only work with atoms")
	)
))

(assert (eval '(plus 1 2) global_env) 3 "plus is broken")
(assert (eval '(plus 1 2 3 4) global_env) 10 "plus is broken")
(assert (eval '(minus 3 2) global_env) 1 "minus is broken")
(assert (eval '(minus 3 2 1) global_env) 0 "minus is broken")
(assert (eval '(minus 10 2 -4 8) global_env) 4 "minus is broken")


;
; Environment operations
;

(env_def global_env 'define (lambda (args env)
	(if (symbol? (first args))
		(env_def env (first args) (eval (second args) env))
		(error (plus "Only symbols can be used as keys in environments. Got: " (to_s (first args))))
	)
))

(env_def global_env 'set (lambda (args env)
	(if (symbol? (first args))
		(env_set env (first args) (eval (second args) env))
		(error (plus "Only symbols can be used as keys in environments. Got: " (to_s (first args))))
	)
))

(define eval_test_env (env_new global_env))
(assert (eval '(define a 1) eval_test_env) 1 "define is broken")
(assert (eval 'a eval_test_env) 1 "environment lookup failed")
(assert (eval '(set a 2) eval_test_env) 2 "set is broken")
(assert (eval 'a eval_test_env) 2 "environment lookup after set failed")
(assert (eval '(define b a) eval_test_env) 2 "define does not eval the value correctly")
(assert (eval 'b eval_test_env) 2 "environment lookup after evaled define failed")

(define sub_test_env (env_new eval_test_env))
(assert (eval 'a sub_test_env) 2 "lookup in sub environment failed")
(assert (eval 'b sub_test_env) 2 "lookup in sub environment failed")
(assert (eval '(define c 3) sub_test_env) 3 "define in sub environment failed")
(assert (eval 'c sub_test_env) 3 "lookup after define in sub environment failed")
(assert (eval '(set c 4) sub_test_env) 4 "set in sub environment failed")
(assert (eval 'c sub_test_env) 4 "lookup after set in sub environment failed")

(assert (eval '(define d (plus 4 1)) sub_test_env) 5 "define with calculation failed")
(assert (eval 'd sub_test_env) 5 "lookup after define with calculation failed")


;
; Lambda stuff
;

; Build a lambda in the form ('lambda env args body)
(env_def global_env 'lambda (lambda (args env)
	(cons 'lambda (cons env args))
))

(assert
	(eval '(lambda (a b) (plus a b)) global_env)
	(cons 'lambda (cons global_env (cons '(a b) (cons '(plus a b) nil))))
	"lambda is broken"
)

; Checks if the first argument is a list in the lambda format
(env_def global_env 'lisp_lambda? (lambda (lam)
	(if (pair? lam)
		(if (eq? (first lam) 'lambda)
			true
			false
		)
		false
	)
))

(assert ( (env_get global_env 'lisp_lambda?) (eval '(lambda (a) (plus a 1)) global_env) ) true "lisp_lambda? broken")
(assert ( (env_get global_env 'lisp_lambda?) 123 ) false "lisp_lambda? broken")

; Some getters for the lambda parts
(define lam_get_env (lambda (lam)
	(second lam)
))

(define lam_get_args (lambda (lam)
	(third lam)
))

(define lam_get_body (lambda (lam)
	(first (rest (rest (rest lam))))
))

(assert (lam_get_env (eval '(lambda (a b) (plus a b)) global_env)) global_env "lam_get_env is broken")
(assert (lam_get_args (eval '(lambda (a b) (plus a b)) global_env)) '(a b) "lam_get_args is broken")
(assert (lam_get_body (eval '(lambda (a b) (plus a b)) global_env)) '(plus a b) "lam_get_body is broken")

; Executes a lambda with the specified arg values
(env_def global_env 'exec_lambda (lambda (lam args env)
	(eval
		(lam_get_body lam)
		(eval_exec_lambda_env_builder (env_new (lam_get_env lam)) env (lam_get_args lam) args)
	)
))

; Helper to build a new environment in which the lambda arg names are bound to
; the specified call argument values.
(define eval_exec_lambda_env_builder (lambda (lam_env call_env keys vals)
	(if (nil? keys)
		lam_env
		; else
		(begin
			(env_def lam_env
				(first keys)
				(if (pair? vals) (eval (first vals) call_env) nil)
			)
			(eval_exec_lambda_env_builder lam_env call_env
				(rest keys)
				(if (nil? vals) nil (rest vals))
			)
		)
	)
))

(assert (eval '((lambda (a) (plus a 1)) 2) global_env) 3 "lambda in function slot broken")
(assert (eval '((lambda () 1)) global_env) 1 "empty lambda broken")

(define lam_test_env (env_new global_env))
(eval '(define one (lambda () 1)) lam_test_env)
(assert (eval '(one) lam_test_env) 1 "lambda execution from environment broken")
(eval '(define inc (lambda (a) (plus a 1))) lam_test_env)
(assert (eval '(inc 1) lam_test_env) 2 "lambda execution from environment broken")


;
; Compiler stuff
;

(define compiler_env (env_new nil))

(define compile (lambda (lisp_ast)
	(eval lisp_ast compiler_env)
))

(define compile_to (lambda (lisp_ast output_filename)
	(begin
		(define output_file (file_open output_filename "w"))
		(file_write output_file (compile lisp_ast))
		(file_close output_file)
	)
))


(env_def compiler_env 'cons (lambda (args env)
	(plus "[" (to_s (eval (first args) env)) ", " (to_s (eval (second args) env)) "]")
))

(env_def compiler_env 'first (lambda (args env)
	(plus (to_s (eval (first args) env)) ".first")
))

(env_def compiler_env 'rest (lambda (args env)
	(plus (to_s (eval (first args) env)) ".last")
))

(assert (compile '(cons 1 2)) "[1, 2]" "compile cons broken")
(assert (compile '(first (cons 1 2))) "[1, 2].first" "compile first broken")
(assert (compile '(rest (cons 1 2))) "[1, 2].last" "compile rest broken")


; Not only generate code but also create a variable in the environemnt. The value
; of this variable is the variable name itself. This way when code for an lambda is
; generated (it is evaled in the compiler env) the variables are resolved to their
; variable names.
(env_def compiler_env 'define (lambda (args env)
	(if (symbol? (first args))
		(begin
			(env_def env (first args) (first args))
			(plus (to_s (first args)) " = " (to_s (eval (second args) env)) "\n")
		)
		(error (plus "Only symbols can be used as keys in environments. Got: " (to_s (first args))))
	)
))

; Just generate code since we already have the variables defined in the environemnt.
; The names is all we need in the compiler.
(env_def compiler_env 'set (lambda (args env)
	(plus (to_s (first args)) " = " (to_s (eval (second args) env)) "\n")
))

(assert (compile '(define a 1)) "a = 1\n" "compiled define broken")
(assert (compile '(define a (cons 2 3))) "a = [2, 3]\n" "compiled define broken")
(assert (compile '(set a 2)) "a = 2\n" "compiled set broken")


(env_def compiler_env 'plus (lambda (args env)
	(plus
		"("
		(to_s (eval (first args) env))
		" + "
		(to_s (eval (second args) env))
		")"
	)
))

(env_def compiler_env 'minus (lambda (args env)
	(plus
		"("
		(to_s (eval (first args) env))
		" - "
		(to_s (eval (second args) env))
		")"
	)
))

(assert (compile '(plus 1 2)) "(1 + 2)" "compiled plus broken")
(assert (compile '(minus 1 2)) "(1 - 2)" "compiled minus broken")
(assert (compile '(plus 1 (minus 3 2))) "(1 + (3 - 2))" "compiled plus does not eval it arguments correctly")


;
; lambda stuff
;

(define join (lambda (elements glue)
	(if (nil? (rest elements))
		(to_s (first elements))
		(plus (to_s (first elements)) glue (join (rest elements) glue))
	)
))

(assert (join '(1 2 3) ",") "1,2,3" "join broken")

(env_def compiler_env 'lambda (lambda (args env)
	(begin
		(define lam_args (first args))
		(define lam_body (second args))
		(define lam_env_builder (lambda (lam_env args)
			(if (pair? args)
				(begin
					(env_def lam_env (first args) (first args))
					(lam_env_builder lam_env (rest args))
				)
			; else
				lam_env
			)
		))
		(define lam_env (lam_env_builder (env_new env) lam_args))
		
		(plus "lambda{|" (join lam_args ", ") "| " (eval lam_body lam_env) "}")
	)
))

(assert (compile '(lambda (a b) (plus a b))) "lambda{|a, b| (a + b)}" "compiled lambda broken")

; No idea how to really do this without a bit of compile time type inference or
; some string operations (check for the "lambda" at the start). Therefore right
; now we just asume everything is a lambda... I know, stupid.
(env_def compiler_env 'lisp_lambda? (lambda (lam)
	true
))

(assert ( (env_get compiler_env 'lisp_lambda?) (eval '(lambda (a) (plus a 1)) compiler_env) ) true "compiled lisp_lambda? broken")
(assert ( (env_get compiler_env 'lisp_lambda?) 123 ) true "compiled lisp_lambda? broken")


(env_def compiler_env 'exec_lambda (lambda (lam args env)
	(plus lam ".call(" (join args ", ") ")")
))

(assert (compile '((lambda (a b) (plus a b)) 1 2)) "lambda{|a, b| (a + b)}.call(1, 2)" "compiled lambda exec broken")