;
; First some basic and general stuff we use all around the code
;

; Checks if the actual value equals the expected value. If not `error` is called
; with the specified message.
(define assert (lambda (actual expected message)
	(if (eq? expected actual)
		true
		(error (if (nil? message) "assertion failed!" message))
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

; Logical and
(define and (lambda (a b)
	(if (eq? a true)
		(if (eq? b true)
			true
			false
		)
		false
	)
))

(assert (and true true) true)
(assert (and true false) false)
(assert (and false true) false)
(assert (and false false) false)

; Logical or
(define or (lambda (a b)
	(if (eq? a true)
		true
		(if (eq? b true)
			true
			false
		)
	)
))

(assert (or true true) true)
(assert (or true false) true)
(assert (or false true) true)
(assert (or false false) false)


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

; Helper for env_get and evn_set. Searches the specified store for `key` and
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
(env_def global_env 'cons '__cons)
(env_def global_env 'first '__first)
(env_def global_env 'rest '__rest)
(env_def global_env 'define '__define)
(env_def global_env 'set '__set)
(env_def global_env 'plus '__plus)
(env_def global_env 'minus '__minus)
(env_def global_env 'lambda '__lambda)

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
	(if (eq? func '__cons)
		(eval_cons args env)
	(if (eq? func '__first)
		(eval_first args env)
	(if (eq? func '__rest)
		(eval_rest args env)
	(if (eq? func '__define)
		(eval_define args env)
	(if (eq? func '__set)
		(eval_set args env)
	(if (eq? func '__plus)
		(eval_plus args env)
	(if (eq? func '__minus)
		(eval_minus args env)
	(if (eq? func '__lambda)
		(eval_lambda args env)
	(if (lambda? func)
		(eval_exec_lambda func args env)
	; else
		(error (plus "Unknown build in: " (to_s func)))
	)))))))))
))

;
; Pair opterations
;

(define eval_cons (lambda (args env)
	(cons
		(eval (first args) env)
		(eval (first (rest args)) env)
	)
))

(define eval_first (lambda (args env)
	(first (eval (first args) env))
))

(define eval_rest (lambda (args env)
	(rest (eval (first args) env))
))

(assert (eval '(first (cons 1 2)) global_env) 1 "first is broken")
(assert (eval '(rest (cons 1 2)) global_env) 2 "rest is broken")


;
; Arithmetic operations
;
(define eval_plus (lambda (args env)
	(if (and (atom? (first args)) (atom? (second args)))
		(plus (eval (first args) env) (eval (second args) env))
		(error "plus can only add atoms but got")
	)
))

(define eval_minus (lambda (args evn)
	(if (and (atom? (first args)) (atom? (second args)))
		(minus (eval (first args) env) (eval (second args) env))
		(error "plus can only add atoms but got")
	)
))

(assert (eval '(plus 1 2) global_env) 3)
(assert (eval '(minus 3 2) global_env) 1)


;
; Environment operations
;

(define eval_define (lambda (args env)
	(if (symbol? (first args))
		(env_def env (first args) (eval (second args) env))
		(error (plus "Only symbols can be used as keys in environments. Got: " (to_s (first args))))
	)
))

(define eval_set (lambda (args env)
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
(define eval_lambda (lambda (args env)
	(cons 'lambda (cons env args))
))

(assert (eval '(lambda (a b) (plus a b)) global_env) (cons 'lambda (cons global_env (cons '(a b) (cons '(plus a b) nil)))) )

; Checks if the first argument is a list in the lambda format
(define lambda? (lambda (args env)
	(if (pair? args)
		(if (eq? (first args) 'lambda)
			true
			false
		)
		false
	)
))

(assert (lambda? (eval '(lambda (a b) (plus a b)) global_env)) true "lambda? is broken")
(assert (lambda? 123) false "lambda? is broken")

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
(define eval_exec_lambda (lambda (lam args env)
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
