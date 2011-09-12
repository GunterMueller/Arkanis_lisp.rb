# Lisp interpreter experiments

This project contains experimental Lisp stuff written by Stephan Soller. The code was
written in the context of the course "Design and implementation of programming
languages" of the Stuttgart Media University held by Claus Gittinger.

Contents:

- `lisp.rb`: A continuation based Lisp interpreter written in Ruby 1.9 with support
  for call/cc.
- `lisp.l`: An Lisp evaluator written in Lips on top of the interpreter. Also contains
  a Lisp compiler environment that compiles statements down to Ruby code.
- `recursive/lisp.rb`: A basic recursive Lisp interpreter written in Ruby 1.9.
- `recursive/lisp.l`: Older version of the Lisp evaluator written on top of the recursive
  Lisp interpreter.

Be aware: This is experimental stuff. It's neither complete nor fast enough for any
real practical use.


## Requirements

The interpreters are written in Ruby 1.9. On Ubuntu Linux you can get Ruby
by installing the `ruby1.9.1` package. On Windows the [RubyInstaller][1] is
an easy way to get Ruby running.

[1]: http://rubyinstaller.org/


## Continuation based Lisp interpreter (`lisp.rb`)

- Entire evaluation and read-eval-print loop written in continuation passing style.
- Supports call/cc (also not all state is preserved).
- Runs the peano numbers (`peano.l`).
- Includes some basic file I/O for the compiler environment written in Lisp.
- Can execute code from a file, an interactive Lisp shell or from an command line
  argument.
- Test cases are embedded within the files as asserts (most files in the `lib` directory).
- Reuses the scanner and reader from the older recursive interpreter (see below).

To run the interpreter:

	ruby1.9.1 lisp.rb --help

All command line arguments are shown. Without any arguments the interpreter starts
an interactive Lisp shell.

List of buildins for this interpreter (methods in the `Evaluator::Buildins` module):

- Language
	- `(if cond true-expr false-expr)`: If `cond` evaluates to true `true-expr` is
	  evaluated. Otherwise `false-expr` is evaluated.
	- `(quote expr)`: Returns `expr` unevaluated. Alternatively the `'expr` syntax
	  can be used.
	- `(define sym expr)`: Creates a new variable in the current environment with
	  the name of `sym`. It will contain the evaluated value of `expr`.
	- `(define (lam-name lam-args ...) lam-body ...)`: Creates a new lambda in the current
	  environment bound to the name `lam-name`. The second and all additional arguments
	  are used as the lambda body. If the body consists of more than two statements they
	  are automatically wrapped with `begin`.
	- `(set sym expr)`: Sets the binding named `sym` in the current environment (or one of
	  its parents) to the evaluated value of `expr`.
	- `(lambda (a b ...) body)`: Returns a new lambda. The first argument is the list
	  of arguments (`(a b ...)`). The second is the lambda body. More than two arguments
	  are not supported.
	- `(begin expr expr ...)`: Evaluates each expression and returns the value of the
	  last one. You can specify an arbitrary number of expressions.
	- `(callcc lam)`: Evals the lambda `lam` with one argument: The current continuation.
	  This continuation can be used as a function taking one argument. If it is called the
	  control flow continues after the `callcc` call and the argument is used as the return
	  value of `callcc`. Unfortunately continuations do not preserve the whole program state
	  right now. The input scanner state is not preserved and the reuse of several basic
	  continuations of the real-eval-print loop limit the usefulness of `callcc` to a single
	  statement. Changing this would require some serious rewriting in the interpreter and
	  was therefore postponed until needed.
- Pair
	- `(cons a b)`: Returns a new pair consisting of `a` and `b`.
	- `(first (cons a b))`: Takes one pair as an argument and returns the first
	  element of it (`a`).
	- `rest`: Takes one pair as an argument and returns the second element
	  of it (`b`).
	- `(set_first pair a)`: Sets the first component of `pair` to `a`. Returns the
	  modified pair.
	- `(set_rest pair b)`: Sets the second component of `pair` to `b`. Returns
	  the modified pair.
- Arithmetic
	- `(plus a b ...)`: Adds up all arguments with Rubys `+` operator. More than
	  two operators are handled like nested calls to `plus`: `(plus (plus a b) c)`.
	  Since it applies Rubys `+` operator  it can handle not only numbers but
	  also strings.
	- `(minus a b ...)`: Subtracts all arguments. Same as `plus` but applies
	  Rubys `-` operator.
- Logical operators
	- `(not a)`: Returns false if `a` evaluates to true. Otherwise true is returned.
	- `(and a b ...)`: Returns true if all arguments evaluate to true. Otherwise false
	  is returned.
	- `(or a b ...)`: Returns true if one of the arguments evaluates to true. Otherwise
	  false is returned. Note that all arguments are evaluated, not matter how early
	  the first true occurs.
- Comparison
	- `(eq? a b)`: Returns true if `a` is equal to `b`, false otherwise. Rubys `==`
	  operator is used to test for equality.
	- `(gt? a b)`: Returns true if `a` is greater than `b`, false otherwise. Rubys `>`
	  operator is used for the comparison.
- Output
	- `(puts string)`: Outputs `string` followed by a new line to the console.
	  Occurrences of "\n" and "\t" are replaced by new lines or tabulators.
	- `(print string)`: Same as `puts` but no new line is appended.
	- `(to_s value)`: Converts the value to a string.
- Reflection
	- `(symbol? expr)`: Returns true if `expr` evaluates to a symbol.
	- `(pair? expr)`: Returns true if `expr` evaluates to a pair.
	- `(nil? expr)`: Returns true if `expr` evaluates to nil.
	- `(atom? expr)`: Returns true if `expr` evaluates to an atom.
	- `(lambda? expr)`: Returns true if `expr` evaluates to an lambda.
- Basic file I/O
	- `(file_open filename mode)`: Opens the file `filename` with the specified `mode`
	  (same as with the `fopen` function). A file resource representing the opened file is
	  returned.
	- `(file_close file_res)`: Closes the specified file.
	- `(file_write file_res content)`: Writes `content` to the file represented by the file
	  resource `file_res`.
	- `(file_read file_res)`: Reads all data from the file represented by the resource
	  `file_res`.
- Misc
	- `(error message)`: Aborts evaluation of the current statement an outputs
	  `message` on the console as well as some diagnostic information.
	- `(load file ['log])`: Loads `file` and executes the Lisp code in it. Returns the value
	  of the last statement in the file. All arguments are evaluated and everything after
	  the `file` argument is regarded as flags. Right now only the `log` flag is supported.
	  It makes `load` print each statement that is evaluated as well as its result.


## Lisp evaluator (`lisp.l`)

This is an `eval` procedure written in Lisp itself with the means provided by the interpreters
written in Ruby. The tests are embedded in the form of `assert` statements. It does not implement
its own reader or printer so it's not a complete interpreter in itself. It can be started with the
continuation based interpreter:

	ruby1.9.1 lisp.rb --interactive lisp.l

The `--interactive` option starts an interactive shell even after the code in `lisp.l` has been
evaluated. In that shell the `eval` procedure can be used to eval quoted lisp code.

	(eval '(plus 1 2) global_env) → 3

`global_env` is the normal evaluation environment and supports the following buildins:

- Language
	- `(lambda (a b ...) body)`: Creates and returns a new lambda which takes the arguments
	  `a b ...` and evaluates `body`.
	- `(define name value)`: Evaluates `value` and stores the result in a variable named `name`.
	  A new variable is _always_ added to the current environment. If `define` is used twice the
	  second value will "shadow" the first definition.
	- `(set name value)`: Modifies the value of a variable. `set` will modify variables in parent
	  environments if the variable is not defined in the local environment.
- Pair
	- `(cons a b)`: Returns a new pair containing `a` and `b`.
	- `(first pair)`: Returns the first part of `pair`.
	- `(rest pair)`: Returns the second (rest) part of `pair`.
- Arithmetic operations
	- `(plus a b ...)`: Returns the sum of `a` and `b` as well as any other specified arguments.
	- `(minus a b ...)`: Subtracts `b` from `a`. If more than two arguments are specified the
	  calculate is performed from left to right, like `(minus (minus a b) c)`.

Additionally to the global environment `lisp.l` also contains ` compiler_env`, an environment
that supports the same buildins as `global_env`. However if code is evaled in that environment
not the result is returned but a string containing Ruby code that will perform the calculation.

	(eval '(plus 1 2) compiler_env) → "(1 + 2)"

The `compile` and `compile_to` functions are shortcuts for evaluation in that environment. The
`compile_to` function stores the result in the specified file.

	(compile '(plus 1 2))
	(compile_to '(plus 1 2) "out.rb")


## Recursive Lisp interpreter

Basic Lisp interpreter with recursive evaluation. It only supports an interactive
Lisp shell. The test cased are included in the source file (`asserts`) and are run
each time the interpreter start To run it:

	cd recursive
	ruby1.9.1 lisp.rb [lisp-file]

If the optional argument `lisp-file` is specified the Lisp code in that file is evaluated
before the interactive console is run.

List of buildins for this interpreter:

- Language
	- `(if cond true-expr false-expr)`: If `cond` evaluates to true `true-expr` is
	  evaluated. Otherwise `false-expr` is evaluated.
	- `(quote expr)`: Returns `expr` unevaluated. Alternatively the `'expr` syntax
	  can be used.
	- `(define sym expr)`: Creates a new variable in the current environment with
	  the name of `sym`. It will contain the evaluated value of `expr`.
	- `(lambda (a b ...) body)`: Returns a new lambda. The first argument is the list
	  of arguments (`(a b ...)`). The second is the lambda body. More than two arguments
	  are not supported.
	- `(begin expr expr ...)`: Evaluates each expression and returns the value of the
	  last one. You can specify an arbitrary number of expressions.
- Pair
	- `(cons a b)`: Returns a new pair consisting of `a` and `b`.
	- `(first (cons a b))`: Takes one pair as an argument and returns the first
	  element of it (`a`).
	- `rest`: Takes one pair as an argument and returns the second element
	  of it (`b`).
	- `(set_first pair a)`: Sets the first component of `pair` to `a`. Returns the
	  modified pair.
	- `(set_rest pair b)`: Sets the second component of `pair` to `b`. Returns
	  the modified pair.
- Arithmetic
	- `(plus a b ...)`: Adds up all arguments with Rubys `+` operator. More than
	  two operators are handled like nested calls to `plus`: `(plus (plus a b) c)`.
	  Since it applies Rubys `+` operator  it can handle not only numbers but
	  also strings.
	- `(minus a b ...)`: Subtracts all arguments. Same as `plus` but applies
	  Rubys `-` operator.
- Comparison
	- `(eq? a b)`: Returns true if `a` is equal to `b`, false otherwise. Rubys `==`
	  operator is used to test for equality.
	- `(gt? a b)`: Returns true if `a` is greater than `b`, false otherwise. Rubys `>`
	  operator is used for the comparison.
- Output
	- `(puts string)`: Outputs `string` followed by a new line to the console.
	  Occurrences of "\n" and "\t" are replaced by new lines or tabulators.
	- `(print string)`: Same as `puts` but no new line is appended.
	- `(to_s value)`: Converts the value to a string.
	- `(inspect expr)`: Evaluates `expr` and returns the Lisp AST of the result
	  as a string.
- Reflection
	- `(symbol? expr)`: Returns true if `expr` evaluates to a symbol.
	- `(pair? expr)`: Returns true if `expr` evaluates to a pair.
	- `(nil? expr)`: Returns true if `expr` evaluates to nil.
	- `(atom? expr)`: Returns true if `expr` evaluates to an atom.
- Misc
	- `(error message)`: Aborts evaluation of the current statement an outputs
	  `message` on the console as well as some diagnostic information.
	- `(load file)`: Loads `file` and executes the Lisp code in it. Returns the value
	  of the last statement in the file.
