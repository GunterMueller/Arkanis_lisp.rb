# encoding: utf-8
require File.dirname(__FILE__) + '/common'
require File.dirname(__FILE__) + '/reader'
require File.dirname(__FILE__) + '/printer'
require 'test/unit/assertions'

include Test::Unit::Assertions

module Evaluator
	
	# Environments used by eval. We use the build in Ruby hashes and add a reference
	# to the parent environment.
	class Environment < Hash
		attr_reader :parent
		def initialize(parent = nil)
			@parent = parent
		end
		
		def inspect(prefix = "")
			self.collect{|k, v| "#{prefix}#{k}: #{v}"}.join("\n")
		end
		
		def to_s
			"env#{self.object_id}"
		end
	end
	
	# Continuation class used to keep track of the control flow. `func` is the method called by the trampoline and
	# is required to respond to `call(args, next_cont)`.  The `args` hash is given to the function call and can be
	# used as local storage between invoking the same continuation again (e.g. recursion). `next` is a reference
	# to the continuation that continues the control flow after the current continuation finished its business.
	# 
	# `heap` is a kind of shared or global storage for multiple continuations. When ever a new continuation is created
	# with the helper methods `create_before` and`copy_with` a reference to the heap is given to the new continuation.
	class Continuation < LispAtom
		attr_accessor :func, :args, :next, :heap
		
		def initialize(next_cont, func, args = {})
			@func, @args, @next = func, args, next_cont
			@heap = {}
		end
		
		# Just syntactic sugar. Updates the arguments and returns self.
		def with(named_args)
			@args.update(named_args)
			return self
		end
		
		# Creates and returns a new continuation with `self` as next continuation. This effectively inserts
		# a new continuation into the control flow. A reference to the heap of `self` is also given to the new
		# continuation and therefore both share the heap.
		def create_before(func, args = {})
			prev_cont = self.class.new self, func, args
			prev_cont.heap = @heap
			return prev_cont
		end
		
		# Creates and returns a new continuation with `next` as next continuation. This effectively inserts
		# a new continuation between the current and the next continuation. A reference to the heap of
		# `self` is also given to the new continuation and therefore both share the heap.
		def create_after(func, args = {})
			next_cont = self.class.new @next, func, args
			next_cont.heap = @heap
			return next_cont
		end
		
		
		# Returns a copy of the continuation but with updated args and optionally updated next continuation
		# reference. This allows an "patch args and retry" approach to programming without affecting the
		# original continuation. This can be important because patching the next continuation can destroy a
		# control flow chain if the continuation is used multiple times (e.g. for a loop).
		# 
		# The heap however is not copied but shared between the original an the copy.
		def copy_with(next_cont = nil, named_args)
			new_cont = self.class.new((next_cont or @next), @func, @args.merge(named_args))
			new_cont.heap = @heap
			return new_cont
		end
		
		# Returns the next continuation with its `args` updated with the specified values. If you return
		# this the trampoline will continue with that continuation and call it with the args set here.
		def next_with(next_cont = nil, args)
			@next.args.update(args)
			@next.next = next_cont if next_cont
			@next
		end
		
		# Returns a nice text representation. Usually of the continuation itself with its arguments as well as the next
		# continuation. The `depth` parameter can be used to set the number of continuations of the continuation
		# chain outputed.
		def to_s(depth = nil)
			if depth.nil? or depth > 0
				func_name = (@func.respond_to? :name) ? @func.name : 'unknown'
				func_args = @args.collect{|name, arg| "#{name}: #{arg}"}.join(', ')
				func_heap = @heap.inspect
				
				if depth.nil?
					"#{func_name}(#{func_args})#{func_heap}"
				else
					"#{func_name}\e[2m(#{func_args})#{func_heap}\e[0m → #{@next ? @next.to_s(depth - 1) : 'nil'}"
				end
			else
				"..."
			end
		end
		
		def dup
			copy = self.class.new(@next, @func, @args.dup)
			copy.heap = @heap.dup
			return copy
		end
	end
	
	# Continuation passing style functions for the AST evaluation
	class << self
		
		# Evaluates an AST in an environment.
		# 
		# Expected arguments:
		# - ast: The abstract syntax tree to evaluate
		# - env: The environment the AST is evaluated in
		# 
		# Gives to the next continuation:
		# - ast: The result syntax tree of the evaluation
		def eval(args, current_cont)
			ast, env = args[:ast], args[:env]
			if ast.kind_of? LispAtom
				if ast.kind_of? LispSym
					# Resolve the binding and let it continue with whatever comes after eval
					return current_cont.create_after method(:eval_binding), name: ast, env: env
				else
					# Give the input AST unmodified to the next continuation. Atoms
					# eval to them selfs.
					return current_cont.next_with(ast: ast)
				end
			else
				# Eval the function slot and continue with function call evaluation
				func_slot, func_args = ast.first, ast.rest
				
				# Build the continuation that takes the evaled function slot and executes it. Directly set the
				# function arguments and environment since `eval` only outputs to the :ast argument.
				func_call_cont = current_cont.create_after method(:eval_function_call), args: func_args, env: env
				# Batch the current continuation so we continue with evaling the function slot. After that the function
				# call continuation comes next.
				return current_cont.copy_with(func_call_cont, ast: func_slot, env: env)
			end
		end
		
		# Resolves a symbol binding in an environment.
		# 
		# Expected arguments:
		# - name: The LispSymbol to look up
		# - env: The environment in which the symbol should be looked up. The search
		#   includes all parent envionments.
		# 
		# Gives to the next continuation:
		# - ast: The Lisp AST bound to the symbol
		def eval_binding(args, current_cont)
			name, env = args[:name], args[:env]
			if env.include? name.val.to_sym
				return current_cont.next_with(ast: env[name.val.to_sym])
			else
				if env.parent
					# TODO: check if copy_with is necessary
					return current_cont.with name: name, env: env.parent
				else
					return current_cont.heap[:error_handler].with message: 
						"Could not resolve symbol #{name.val.inspect}",
						ast: name, backtrace: caller(0)
				end
			end
		end
		
		# Applies a function call. This can be either a build in or a lambda.
		# 
		# Expected arguments:
		# - ast: The AST of the function slot. Either a symbol with the name of a build in
		#   an lambda.
		# - args: The Lisp list of the arguments. That is everything behind the function
		#   slot. The invoked function might eval its arguments but is not required to.
		# - env: The environment the function call is performed in. Usually this is the
		#   environment the arguments are evaluated in. The function body is usually
		#   evaled in the conserved lexical environment.
		# 
		# Indirectly given to the next continuation:
		# - ast: The result AST of the function call.
		# 
		# This function does not invoke the next continuation itself but passes control
		# on to a buildin or to eval_lambda. These then set the `ast` argument on the
		# next continuation.
		def eval_function_call(args, current_cont)
			func_slot, func_args = args[:ast], args[:args]
			env = args[:env]
			
			if func_slot.kind_of? LispSym
				buildin_name = func_slot.val.to_sym
				if Buildins.singleton_methods.include? buildin_name
					return current_cont.create_after Buildins.method(buildin_name), arg_ast: func_args, env: env
				else
					return current_cont.heap[:error_handler].with message:
						"Tried to call unknown buildin with the name \"#{buildin_name}\"",
						ast: LispPair.new(func_slot, func_args), backtrace: caller(0)
				end
			elsif func_slot.kind_of? Continuation
				# If we got a continuation in the function slot eval its first argument and then
				# continue with that continuation.
				return func_slot.create_before method(:eval), ast: func_args.first, env: env
			elsif func_slot.kind_of? LispLambda
				return current_cont.create_after method(:eval_lambda), lambda: func_slot, arg_ast: func_args, env: env
			else
				return current_cont.heap[:error_handler].with message:
					"Got unknown stuff in the function slot: #{Printer.print(func_slot)}",
					ast: LispPair.new(func_slot, func_args), backtrace: caller(0)
			end
		end
		
		# Evaluates the ASTs in the `unevaled_args` argument in the order they were
		# put into that array. This function is primary intended to be used by build ins
		# who want to eval their arguments.
		# 
		# Expected arguments:
		# - unevaled_args: An ruby array with ASTs that you want to be evaluated.
		# 
		# Gives to the next continuation:
		# - evaled_args: An ruby array with the results of the AST evaluation. The results
		#   are in the same order as the ASTs in the `unevaled_args` array.
		def eval_function_args(args, current_cont)
			if args[:ast]
				# If :ast is set we are called by the `eval` call we issue below
				current_cont.args[:evaled_args] ||= []
				current_cont.args[:evaled_args].push args[:ast]
				current_cont.args.delete :ast
				return current_cont
			elsif args[:unevaled_args] and args[:unevaled_args].size > 0
				# We are called by someone who wants the list in :unevaled_args evaled
				return current_cont.create_before method(:eval), ast: current_cont.args[:unevaled_args].shift, env: args[:env]
			else
				# No unevaled args left, continue with whatever someone set out for us. But give them the evaled args
				# they requested.
				return current_cont.next_with evaled_args: args[:evaled_args]
			end
		end
		
		# Applies a lambda with the specified arguments. For lambda definition look
		# at the buildin `lambda`.
		# 
		# Expected arguments:
		# - lambda: The lambda that should be evaluated.
		# - arg_ast: The Lisp AST of the arguments. This is everything after the function slot.
		# - env: The environment the arguments are evaluated in.
		# 
		# Indirectly given to the next continuation:
		# - ast: The result AST of the lambda evaluation.
		# 
		# This function passes control to `eval` in order to eval the lambda body. `eval` then
		# sets the `ast` argument of the next continuation.
		def eval_lambda(args, current_cont)
			lambda, arg_ast, eval_env = args[:lambda], args[:arg_ast], args[:env]
			
			# First eval the arguments in the current eval environment
			unless args[:evaled_args]
				unevaled_args = lisp_list_to_array(arg_ast)
				unless lambda.arg_names.size == unevaled_args.size
					return current_cont.heap[:error_handler].with message:
						"Lambda requires #{lambda.arg_names.size} arguments but #{unevaled_args.size} were given",
						ast: LispPair.new(lambda, arg_ast), backtrace: caller(0)
				end
				
				return current_cont.create_before method(:eval_function_args), unevaled_args: unevaled_args, env: eval_env
			end
			
			# We got all arguments evaled, now build a new environment with them and execute the lambda in there
			evaled_args = args[:evaled_args]
			execution_env = Environment.new lambda.env
			evaled_args.each_with_index do |evaled_arg, index|
				execution_env[lambda.arg_names[index].to_sym] = evaled_arg
			end
			
			return current_cont.create_after method(:eval), ast: lambda.body, env: execution_env
		end
		
		# Small utility function to convert a Lisp list into a ruby array
		def lisp_list_to_array(ast)
			array = []
			while ast.kind_of? LispPair
				array << ast.first
				ast = ast.rest
			end
			return array
		end
		
		# Constructs an environment with all buildins initialized.
		def construct_buildin_env
			env = Environment.new
			Buildins.singleton_methods.each do |name|
				env[name] = LispSym.new name
			end
			return env
		end
	end
	
	
	# Buildins of the lisp interpreter. All buildins are invoked by `eval_function_call`.
	# From it they get the following arguments:
	# 
	# - arg_ast: The Lisp AST with the arguments of the function call. This is the AST
	#   of everything after the function slot.
	# - env: The environment the buildin is called in.
	# 
	# Every buildin is expected to put this into the next continuation arguments:
	# - ast: The result AST of the buildin.
	module Buildins
		class << self
			
			#
			# Language buildins
			#
			
			def quote(args, current_cont)
				return current_cont.next_with(ast: args[:arg_ast].first)
			end
			
			def define(args, current_cont)
				key, value, env = args[:arg_ast].first, args[:arg_ast].rest.first, args[:env]
				
				if key.kind_of? LispSym
					# Usual form of define, we eval the value and put the result into the environment
					unless args[:evaled_args]
						return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [value], env: env
					end
					
					result = args[:evaled_args].first
					env[key.val.to_sym] = result
				elsif key.kind_of? LispPair
					# We got the lambda define shorthand syntax. Here we don't eval anything
					lambda_name = key.first
					lambda_args = Evaluator.lisp_list_to_array(key.rest).collect{|atom| atom.val.to_sym}
					body_args = args[:arg_ast].rest
					if body_args.kind_of? LispPair and not body_args.rest.kind_of? LispNil
						# We got multiple statements as body, wrap them into a "begin" call
						lambda_body = LispPair.new(LispSym.new("begin"), args[:arg_ast].rest)
					else
						# Just one body, take it as it is
						lambda_body = body_args.first
					end
					
					result = LispLambda.new lambda_args, lambda_body, args[:env]
					env[lambda_name.val.to_sym] = result
				else
					return current_cont.heap[:error_handler].with message:
						"define requires a symbol or pair as first parameter",
						ast: args[:arg_ast], backtrace: caller(0)
				end
				
				return current_cont.next_with(ast: result)
			end
			
			def set(args, current_cont)
				unless args[:evaled_args]
					value = args[:arg_ast].rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [value], env: args[:env]
				end
				
				key, value, env = args[:arg_ast].first, args[:evaled_args].first, args[:env]
				if key.kind_of? LispSym
					key_name = key.val.to_sym
					until env.nil?
						break if env.include? key_name
						env = env.parent
					end
					
					unless env.nil?
						env[key_name] = value
					else
						return current_cont.heap[:error_handler].with message:
							"set could not find the binding #{key_name} in the current environment or it's parents",
							ast: args[:arg_ast], backtrace: caller(0)
					end
				else
					return current_cont.heap[:error_handler].with message:
						"set requires a symbol as first parameter",
						ast: args[:arg_ast], backtrace: caller(0)
				end
				
				return current_cont.next_with(ast: value)
			end
			
			def lambda(args, current_cont)
				arg_names = Evaluator.lisp_list_to_array(args[:arg_ast].first).collect{|atom| atom.val}
				result = LispLambda.new arg_names, args[:arg_ast].rest.first, args[:env]
				return current_cont.next_with(ast: result)
			end
			
			def begin(args, current_cont)
				# Eval all arguments
				unless args[:evaled_args]
					statements = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: statements, env: args[:env]
				end
				
				# And then return the result of the last
				return current_cont.next_with ast: args[:evaled_args].last
			end
			
			def load(args, current_cont)
				# Eval all args
				unless args[:evaled_args]
					unevaled_args = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: unevaled_args, env: args[:env]
				end
				
				filename, *options = args[:evaled_args]
				unless args[:file]
					lisp_file = File.open(filename.val)
					current_cont.args[:file] = lisp_file
					current_cont.args[:scanner] = Reader::Scanner.new lisp_file
					current_cont.args[:log] = (options.detect{|opt| opt.kind_of? LispSym and opt.val == 'log'} != nil)
					# Continue right away with the code below. We don't need a continuation to jump there
				end
				
				# Read each statement and give it to eval. Also put it into the heap so the
				# error handler can show it.
				unless args[:file].eof?
					input_ast = Reader.read(args[:scanner])
					
					return current_cont if input_ast.nil?
					
					$stderr.puts "=> " + Printer.print(args[:ast]) if current_cont.args[:log] and args[:ast]
					$stderr.puts Printer.print(input_ast) if current_cont.args[:log]
					
					current_cont.heap[:statement_ast] = input_ast
					return current_cont.create_before Evaluator.method(:eval), ast: input_ast, env: args[:env]
				end
				
				# In the final step close the lisp file and return the last result ast we got
				args[:file].close
				return current_cont.next_with ast: args[:ast]
			end
			
			
			#
			# Pair buildins
			#
			
			def cons(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					a, b = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [a, b], env: args[:env]
				end
				
				# First two arguments evaled
				a, b = *args[:evaled_args]
				result = LispPair.new a, b
				
				return current_cont.next_with(ast: result)
			end
			
			def first(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					param = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [param], env: args[:env]
				end
				
				# First two arguments evaled
				evaled_param = args[:evaled_args].first
				
				unless evaled_param.kind_of? LispPair
					return current_cont.heap[:error_handler].with message:
						"first requires a pair as argument" ,
						ast: args[:arg_ast], backtrace: caller(0)
				end
				
				result = evaled_param.first
				return current_cont.next_with(ast: result)
			end
			
			def set_first(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					pair, val = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [pair, val], env: args[:env]
				end
				
				# First two arguments evaled
				pair, val = *args[:evaled_args]
				pair.first = val
				
				return current_cont.next_with(ast: pair)
			end
			
			def rest(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					param = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [param], env: args[:env]
				end
				
				# First two arguments evaled
				evaled_param = args[:evaled_args].first
				
				unless evaled_param.kind_of? LispPair
					return current_cont.heap[:error_handler].with message:
						"rest requires a pair as argument" ,
						ast: args[:arg_ast], backtrace: caller(0)
				end
				
				result = evaled_param.rest
				return current_cont.next_with(ast: result)
			end
			
			def set_rest(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					pair, val = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [pair, val], env: args[:env]
				end
				
				# First two arguments evaled
				pair, val = *args[:evaled_args]
				pair.rest = val
				
				return current_cont.next_with(ast: pair)
			end
			
			def last(args, current_cont)
				unless args[:evaled_args]
					pair = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [pair], env: args[:env]
				end
				
				pair = args[:evaled_args].first
				pair = pair.rest while pair.rest.kind_of? LispPair
				
				result = pair.rest.kind_of?(LispNil) ? pair.first : pair.rest
				return current_cont.next_with(ast: result)
			end
			
			
			#
			# Arithmetic buildins
			#
			
			def plus(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					a, b = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [a, b], env: args[:env]
				end
				
				# First two arguments evaled
				a, b = *args[:evaled_args]
				unless a.kind_of? LispAtomWithValue and b.kind_of? LispAtomWithValue
					return current_cont.heap[:error_handler].with message:
						"plus only works with values",
						ast: args[:arg_ast], backtrace: caller(0)
				end
				result = a.class.new(a.val + b.val)
				
				c = args[:arg_ast].rest.rest
				if not c or c.kind_of? LispNil
					return current_cont.next_with(ast: result)
				else
					# There is more to add, continue with a next plus
					return current_cont.copy_with(arg_ast: LispPair.new(result, c), evaled_args: nil)
				end
			end
			
			def minus(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					a, b = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [a, b], env: args[:env]
				end
				
				# First two arguments evaled
				a, b = *args[:evaled_args]
				unless a.kind_of? LispAtomWithValue and b.kind_of? LispAtomWithValue
					return current_cont.heap[:error_handler].with message:
						"minus only works with values",
						ast: args[:arg_ast], backtrace: caller(0)
				end
				result = a.class.new(a.val - b.val)
				
				c = args[:arg_ast].rest.rest
				if not c or c.kind_of? LispNil
					return current_cont.next_with(ast: result)
				else
					# There is more to add, continue with a next plus
					return current_cont.copy_with(arg_ast: LispPair.new(result, c), evaled_args: nil)
				end
			end
			
			
			#
			# Logical operators
			#
			
			def not(args, current_cont)
				unless args[:evaled_args]
					unevaled_arg = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [unevaled_arg], env: args[:env]
				end
				
				result = args[:evaled_args].first.kind_of?(LispTrue) ? LispFalse.instance : LispTrue.instance
				return current_cont.next_with ast: result
			end
			
			def and(args, current_cont)
				unless args[:evaled_args]
					unevaled_args = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: unevaled_args, env: args[:env]
				end
				
				result = args[:evaled_args].all?{|arg| arg.kind_of?(LispTrue)} ? LispTrue.instance : LispFalse.instance
				return current_cont.next_with ast: result
			end
			
			def or(args, current_cont)
				unless args[:evaled_args]
					unevaled_args = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: unevaled_args, env: args[:env]
				end
				
				result = args[:evaled_args].any?{|arg| arg.kind_of?(LispTrue)} ? LispTrue.instance : LispFalse.instance
				return current_cont.next_with ast: result
			end
			
			
			#
			# Comparism buildins
			#
			
			def eq?(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					a, b = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [a, b], env: args[:env]
				end
				
				# First two arguments evaled
				a, b = *args[:evaled_args]
				result = (a == b) ? LispTrue.instance : LispFalse.instance
				return current_cont.next_with(ast: result)
			end
			
			def gt?(args, current_cont)
				# If :evaled_args argument is not set eval the first two arguments first
				unless args[:evaled_args]
					arg_ast = args[:arg_ast]
					a, b = arg_ast.first, arg_ast.rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [a, b], env: args[:env]
				end
				
				# First two arguments evaled
				a, b = *args[:evaled_args]
				
				unless a.kind_of? LispAtom and b.kind_of? LispAtom
					return current_cont.heap[:error_handler].with message:
						"gt? requires two atoms",
						ast: args[:arg_ast], backtrace: caller(0)
				end
				
				result = (a > b) ? LispTrue.instance : LispFalse.instance
				return current_cont.next_with(ast: result)
			end
			
			
			#
			# Conditional buildins
			#
			
			def if(args, current_cont)
				# If :evaled_args argument is not set eval the condition argument
				unless args[:evaled_args]
					cond = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [cond], env: args[:env]
				end
				
				cond = args[:evaled_args].first
				branch_ast = unless cond.kind_of? LispFalse or cond.kind_of? LispNil
					args[:arg_ast].rest.first
				else
					args[:arg_ast].rest.rest.first
				end
				
				return current_cont.create_after Evaluator.method(:eval), ast: branch_ast, env: args[:env]
			end
			
			
			#
			# Reflective buildins
			#
			
			{symbol?: LispSym, pair?: LispPair, nil?: LispNil, atom?: LispAtom, lambda?: LispLambda}.each do |name, kind|
				eval <<-EOD
					def #{name}(args, current_cont)
						# Eval the first argument
						unless args[:evaled_args]
							element = args[:arg_ast].first
							return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [element], env: args[:env]
						end
						
						# Perform the test
						result = args[:evaled_args].first.kind_of?(#{kind})  ? LispTrue.instance : LispFalse.instance
						return current_cont.next_with ast: result
					end
				EOD
			end
			
			
			#
			# Output buildins
			#
			
			def print(args, current_cont)
				unless args[:evaled_args]
					unevaled_args = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: unevaled_args, env: args[:env]
				end
				
				args[:evaled_args].each do |arg|
					$stdout.print arg.val.to_s.gsub('\n', "\n").gsub('\t', "\t") if arg.kind_of? LispAtomWithValue
				end
				
				return current_cont.next_with ast: args[:evaled_args].last
			end
			
			def puts(args, current_cont)
				unless args[:evaled_args]
					unevaled_args = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: unevaled_args, env: args[:env]
				end
				
				args[:evaled_args].each do |arg|
					$stdout.puts arg.val.to_s.gsub('\n', "\n").gsub('\t', "\t") if arg.kind_of? LispAtomWithValue
				end
				
				return current_cont.next_with ast: args[:evaled_args].last
			end
			
			def error(args, current_cont)
				unless args[:evaled_args]
					unevaled_args = Evaluator.lisp_list_to_array(args[:arg_ast])
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: unevaled_args, env: args[:env]
				end
				
				return current_cont.heap[:error_handler].with message:
					args[:evaled_args].first,
					ast: args[:arg_ast], backtrace: caller(0)
			end
			
			def to_s(args, current_cont)
				unless args[:evaled_args]
					subject = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [subject], env: args[:env]
				end
				
				subject = args[:evaled_args].first
				result = if subject.kind_of? LispAtomWithValue
					LispStr.new subject.val.to_s
				else
					LispStr.new subject.to_s
				end
				
				return current_cont.next_with ast: result
			end
			
			
			#
			# Basic file I/O
			#
			
			def file_open(args, current_cont)
				unless args[:evaled_args]
					filename, mode = args[:arg_ast].first, args[:arg_ast].rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [filename, mode], env: args[:env]
				end
				
				filename, mode = args[:evaled_args].first.val, args[:evaled_args].last.val
				file_resource = LispResource.new File.new(filename, mode)
				return current_cont.next_with ast: file_resource
			end
			
			def file_close(args, current_cont)
				unless args[:evaled_args]
					file_res = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [file_res], env: args[:env]
				end
				
				file_res = args[:evaled_args].first
				file_res.data.close
				return current_cont.next_with ast: LispNil.instance
			end
			
			def file_write(args, current_cont)
				unless args[:evaled_args]
					file_res, content = args[:arg_ast].first, args[:arg_ast].rest.first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [file_res, content], env: args[:env]
				end
				
				file_res, content = args[:evaled_args].first, args[:evaled_args].last
				bytes_written = file_res.data.write content.val
				result = LispInt.new bytes_written
				return current_cont.next_with ast: result
			end
			
			def file_read(args, current_cont)
				unless args[:evaled_args]
					file_res = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [file_res, content], env: args[:env]
				end
				
				file_res = args[:evaled_args]
				result = LispStr.new file_res.data.read
				return current_cont.next_with ast: result
			end
			
			
			#
			# Continuation stuff
			#
			
			def callcc(args, current_cont)
				unless args[:evaled_args]
					lam = args[:arg_ast].first
					return current_cont.create_before Evaluator.method(:eval_function_args), unevaled_args: [lam], env: args[:env]
				end
				
				lam = args[:evaled_args].first
				unless lam.kind_of? LispLambda
					return current_cont.heap[:error_handler].with message:
						"callcc requireds a lambda as argument",
						ast: args[:arg_ast], backtrace: caller(0)
				end
				
				cont = current_cont.next.dup
				return current_cont.create_after Evaluator.method(:eval_lambda), lambda: lam, arg_ast: LispPair.new(cont, LispNil.instance), env: args[:env]
			end
			
		end
	end
	
	def self.test(show_log = false, show_conts_depths = 0)
		$stderr.puts "Testing eval…" if show_log
		
		test_env = self.construct_buildin_env
		{
			"(cons 1 2)" => "(1 . 2)",
			"(first (cons 1 2))" => "1", "(rest (cons 1 2))" => "2",
			"(set_first (cons 1 2) 3)" => "(3 . 2)", "(set_rest (cons 1 2) 3)" => "(1 . 3)",
			"(last '(1 2 3 4))" => "4",
			"(plus 1 2)" => "3", "(minus 2 1)" => "1",
			"(plus 1 2 3 4)" => "10", "(minus 2 1 1)" => "0",
			'(plus "hallo" " " "welt")' => '"hallo welt"',
			"(eq? 1 1)" => "true", "(eq? 1 2)" => "false",
			"(gt? 2 1)" => "true", "(gt? 1 2)" => "false",
			"(quote a)" => "a",
			'(quote (a 1 "b"))' => '(a 1 "b")',
			"(if true 1 2)" => "1", "(if false 1 2)" => "2", "(if (eq? 5 5) 1 2)" => "1",
			"(define a (plus 1 2))" => "3", "a" => "3",
			"(define b 7)" => "7", "(set b 3)" => "3", "b" => "3",
			"(set b (plus 4 5))" => "9", "(plus b 1)" => "10",
			"(define var (cons 1 2))" => "(1 . 2)",
			"(set_first var 3)" => "(3 . 2)",
			"var" => "(3 . 2)",
			"(define inc (lambda (a) (plus a 1)))" => "(lambda (a) (plus a 1))",
			"(inc 2)" => "3",
			"((lambda (a b) (plus a b)) 1 2)" => "3",
			"(define (dec a) (minus a 1))" => "(lambda (a) (minus a 1))",
			"(dec 2)" => "1",
			"(begin 1 2 3)" => "3",
			"(define (begin-lambda a) (plus a 1) (plus a 2))" => "(lambda (a) (begin (plus a 1) (plus a 2)))",
			"(begin-lambda 1)" => "3",
			"(symbol? (quote abc))" => "true",
			"(symbol? 1)" => "false",
			"(pair? (cons 1 2))" => "true",
			"(nil? nil)" => "true",
			"(atom? 1)" => "true",
			"(atom? (quote sym))" => "true",
			'(atom? "str")' => "true",
			"(atom? (cons 1 2))" => "false",
			"(lambda? (lambda (a b) (plus a b)))" => "true",
			"(lambda? inc)" => "true",
			"(lambda? 3)" => "false",
			"(not true)" => "false",
			"(not false)" => "true",
			"(and true true)" => "true",
			"(and true false)" => "false",
			"(and false true)" => "false",
			"(and false false)" => "false",
			"(or true true)" => "true",
			"(or true false)" => "true",
			"(or false true)" => "true",
			"(or false false)" => "false",
			"(to_s 1)" => '"1"',
			'(to_s "str")' => '"str"',
			"(to_s true)" => '"true"',
			# a small callcc test case
			"(define (f return) (return 2) 3)" => "(lambda (return) (begin (return 2) 3))",
			"(f (lambda (x) x))" => "3",
			"(callcc f)" => "2"
		}.each do |code, result|
			$stderr.puts "- #{code} → #{result}" if show_log
			
			stop_cont = Continuation.new nil, nil
			test_runner_cont = Continuation.new stop_cont, method(:eval), ast: Reader.read(code), env: test_env
			test_runner_cont.heap[:error_handler] = stop_cont
			
			cont = test_runner_cont
			until cont.next.nil?
				puts "  #{cont.to_s(show_conts_depths)}" if show_log and show_conts_depths > 0
				cont = cont.func.call(cont.args, cont)
			end
			
			evaled_code = cont.args[:ast]
			assert_equal result, Printer.print(evaled_code)
		end
	end
	
end