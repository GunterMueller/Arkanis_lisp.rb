require 'singleton'
require 'strscan'

class LispException < RuntimeError; end

def assert(expected_value, tested_value)
	raise "Test failed, got #{tested_value.inspect}, expteded #{expected_value.inspect}" if expected_value != tested_value
end

#
# The abstract syntax tree for the Lisp code
#

class LispElement; end
class LispAtom < LispElement; end

class LispNil < LispAtom
	include Singleton
end
class LispTrue < LispAtom
	include Singleton
end
class LispFalse < LispAtom
	include Singleton
end

class LispAtomWithValue < LispAtom
	include Comparable
	attr_reader :val
	
	def initialize(val)
		@val = val
	end
	
	def <=>(other)
		if @val < other.val
			-1
		elsif @val > other.val
			1
		else
			0
		end
	end
end

class LispSym < LispAtomWithValue; end
class LispStr < LispAtomWithValue; end
class LispInt < LispAtomWithValue; end


class LispPair < LispElement
	attr_reader :first, :rest
	
	def initialize(first, rest)
		@first, @rest = first, rest
	end
	
	def ==(other)
		@first == other.first and @rest == other.rest
	end
end


#
# Reader function that parses Lisp code and returns the DOM tree of it
#

def read(code)
	scan = (code.kind_of? StringScanner) ? code : StringScanner.new(code)
	scan.skip /\s+/
	if scan.check /\(/
		read_list(scan)
	else
		read_atom(scan)
	end
end

def read_atom(scan)
	if scan.check /\"/
		# we got a string
		scan.getch
		str = scan.scan_until /\"/
		raise LispException, "Unstopped string!" unless str
		LispStr.new str[0..-2]
	else
		word = scan.scan_until(/\s|(?=\))|$/).rstrip
		if word == "nil"
			LispNil.instance
		elsif word == "true"
			LispTrue.instance
		elsif word == "false"
			LispFalse.instance
		elsif word =~ /\d/
			LispInt.new word.to_i
		else
			LispSym.new word
		end
	end
end

assert LispStr.new(""), read('""')
assert LispStr.new("test"), read('"test"')
assert LispNil.instance, read('nil')
assert LispTrue.instance, read('true')
assert LispFalse.instance, read('false')
assert LispInt.new(123), read('123')
assert LispInt.new(123), read(' 123 ')
assert LispSym.new("name"), read('name')
assert LispSym.new("name"), read(' name ')


def read_list(scan)
	scan.getch  # consume "("
	read_list_rest(scan)
end

def read_list_rest(scan)
	raise LispException, "Unterminated list!" if scan.eos?
	scan.skip /\s+/
	if scan.check /\)/
		scan.getch
		return LispNil.instance
	end
	LispPair.new read(scan), read_list_rest(scan)
end

assert LispPair.new(LispInt.new(1), LispNil.instance), read("(1)")
assert LispNil.instance, read("()")
assert LispNil.instance, read("(      )")
assert LispPair.new(LispPair.new(LispInt.new(1), LispNil.instance), LispNil.instance), read("((1))")
assert LispPair.new(LispSym.new("bla"), LispPair.new(LispInt.new(1), LispNil.instance)), read("(bla 1)")


#
# print function
#

def print_ast(ast)
	if ast.kind_of? LispPair
		print_list(ast)
	else
		print_atom(ast)
	end
end

def print_atom(atom)
	if atom.kind_of? LispNil
		"nil"
	elsif atom.kind_of? LispTrue
		"true"
	elsif atom.kind_of? LispFalse
		"false"
	elsif atom.kind_of? LispStr
		"\"#{atom.val}\""
	elsif atom.kind_of? LispAtomWithValue
		atom.val.to_s
	else
		raise LispException, "unknown atom: #{atom.inspect}"
	end
end

def print_list(ast)
	"(" + print_list_rest(ast)
end

def print_list_rest(ast)
	print_ast(ast.first) + if ast.rest.kind_of? LispNil
		")"
	elsif ast.rest.kind_of? LispAtom
		" . #{print_atom(ast.rest)})"
	else
		" #{print_list_rest(ast.rest)}"
	end
end

["sym", "123", '"str"', "nil", "true", "false", "(1)", "(1 2)", "((a) (b c))"].each do |sample|
	assert sample, print_ast(read(sample))
end


#
# environments used by eval
#

class Environment < Hash
	attr_reader :parent
	def initialize(parent = nil)
		@parent = parent
	end
end


#
# eval function
#

def eval_ast(ast, env)
	if ast.kind_of? LispAtom
		if ast.kind_of? LispSym
			eval_binding(ast, env)
		else
			ast
		end
	else
		function_slot = ast.first
		if function_slot.kind_of? LispSym
			if Object.private_methods.include? "eval_#{function_slot.val}"
				Object.send :"eval_#{function_slot.val}", ast.rest, env
			else
				evaled_func = eval_ast(function_slot, env)
				if evaled_func.kind_of? LispPair and evaled_func.first.kind_of? LispSym and evaled_func.first.val == "lambda"
					exec_lambda(evaled_func.rest, ast.rest, env)
				else
					ast
				end
			end
		else
			ast
		end
	end
end

def eval_cons(ast, env)
	raise LispException, "cons requires to arguments" unless ast.kind_of? LispPair
	LispPair.new eval_ast(ast.first, env), eval_ast(ast.rest.first, env)
end

def eval_first(ast, env)
	params = ast.first
	eval_ast(params, env).first
end

def eval_rest(ast, env)
	params = ast.first
	eval_ast(params, env).rest
end

def eval_plus(ast, env)
	params = ast
	a, b = eval_ast(params.first, env), eval_ast(params.rest.first, env)
	raise LispException, "plus requires two values" unless a.kind_of? LispAtomWithValue and b.kind_of? LispAtomWithValue
	return a.class.new(a.val + b.val)
end

def eval_minus(ast, env)
	params = ast
	a, b = eval_ast(params.first, env), eval_ast(params.rest.first, env)
	raise LispException, "minus requires two values" unless a.kind_of? LispAtomWithValue and b.kind_of? LispAtomWithValue
	return a.class.new(a.val - b.val)
end

def eval_eq?(ast, env)
	if eval_ast(ast.first, env) == eval_ast(ast.rest.first, env)
		LispTrue.instance
	else
		LispFalse.instance
	end
end

def eval_gt?(ast, env)
	a, b = eval_ast(ast.first, env), eval_ast(ast.rest.first, env)
	raise LispException, "gt? requires to atoms" unless a.kind_of? LispAtom and b.kind_of? LispAtom
	(a > b) ? LispTrue.instance : LispFalse.instance
end

def eval_if(ast, env)
	cond = eval_ast(ast.first, env);
	unless cond.kind_of? LispFalse or cond.kind_of? LispNil
		eval_ast(ast.rest.first, env)
	else
		eval_ast(ast.rest.rest.first, env)
	end
end

def eval_define(ast, env)
	name = ast.first
	raise LispException, "define requires a symbol as first parameter" unless name.kind_of? LispSym
	value = eval_ast(ast.rest.first, env)
	env[name.val] = value
	return value
end

def eval_binding(ast, env)
	if env.include? ast.val
		env[ast.val]
	else
		if env.parent
			eval_binding(ast, env.parent)
		else
			ast
		end
	end
end

def eval_lambda(ast, env)
	# prepend the "lambda" symbol again since we throw it away in eval_ast().
	# a list with the first symbol of "lambda" is our format to store lambdas.
	LispPair.new(LispSym.new("lambda"), ast)
end

def exec_lambda(lambda, args, env)
	param_names = lambda.first
	body = lambda.rest.first
	lambda_env = Environment.new env
	
	param, arg = param_names, args
	begin
		lambda_env[param.first.val] = eval_ast(arg.first, env)
	end until param.rest.kind_of? LispNil or arg.rest.kind_of? LispNil
	
	eval_ast(body, lambda_env)
end

env = Environment.new
{
	"(cons 1 2)" => "(1 . 2)",
	"(first (cons 1 2))" => "1", "(rest (cons 1 2))" => "2",
	"(plus 1 2)" => "3", "(minus 2 1)" => "1",
	"(eq? 1 1)" => "true", "(eq? 1 2)" => "false",
	"(gt? 2 1)" => "true", "(gt? 1 2)" => "false",
	"(if true 1 2)" => "1", "(if false 1 2)" => "2", "(if (eq? 5 5) 1 2)" => "1",
	"(define a (plus 1 2))" => "3", "a" => "3",
	"(define inc (lambda (a) (plus a 1)))" => "(lambda (a) (plus a 1))",
	"(inc 2)" => "3"
}.each do |code, result|
	assert result, print_ast(eval_ast(read(code), env))
end


#
# input console
#

global_env = Environment.new
print "> "
while line = gets
	begin
		ast = read(line.rstrip)
		puts print_ast(eval_ast(ast, global_env))
	rescue LispException => e
		puts "error: #{e}"
	end
	print "> "
end
