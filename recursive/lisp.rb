#!/usr/bin/ruby1.9.1

require 'singleton'

class LispException < RuntimeError
	attr_accessor :code, :env, :original_exception
	def initialize(msg)
		super(msg)
		@code, @env = [], []
	end
end

def assert(expected_value, tested_value)
	raise "Test failed, got #{tested_value.inspect}, expteded #{expected_value.inspect}" if expected_value != tested_value
end

#
# Input stream scanner
#

class StringIO
	def initialize(string)
		@str = string.dup
		@pos = 0
	end
	
	def getc
		char = @str[@pos]
		@pos += 1
		char
	end
	
	def ungetc(char)
		return unless char
		@pos -= 1
		@str[@pos] = char
	end
	
	def gets(sep)
		start_pos = @pos
		end_pos = @str.index sep, @pos
		raise "Unexpected end of string, expected #{sep.inspect} before end of string" unless end_pos
		@pos = end_pos + sep.length
		@str[start_pos .. end_pos]
	end
end

test_io = StringIO.new "abc 123e"
assert "a", test_io.getc
assert "b", test_io.getc
assert "c", test_io.getc
test_io.ungetc "c"
assert "c", test_io.getc
test_io.ungetc "b"
assert "b", test_io.getc
assert " ", test_io.getc
assert "123", test_io.gets("3")
assert "e", test_io.getc
assert nil, test_io.getc


class Scanner
	def initialize(io_stream)
		@io = io_stream
	end
	
	def peek
		char = @io.getc
		@io.ungetc(char)
		char
	end
	
	def consume(*alternatives)
		char = @io.getc
		raise LispException, "Expected one of #{alternatives.inspect} but got #{char.inspect}" unless alternatives.include? char
		char
	end
	
	def until(*alternatives)
		result = ""
		while true
			char = @io.getc
			break if alternatives.include? char
			raise LispException, "Expected one of #{alternatives.inspect} but got #{char.inspect}" unless char
			result += char
		end
		@io.ungetc char
		result
	end
	
	def skip(regexp)
		begin
			char = @io.getc
		end while char =~ regexp
		# This is handled by read() directly...
		#raise LispException, "Unexpected end of file, expected something that does not match #{regexp.inspect}" if char == nil
		@io.ungetc char
		char
	end
end

test_scanner = Scanner.new StringIO.new("abc 12 \t 3")
assert "a", test_scanner.peek
assert "a", test_scanner.consume("a", "b")
assert "b", test_scanner.consume("a", "b")
assert "c 1", test_scanner.until("2")
assert "2", test_scanner.peek
assert "2", test_scanner.consume("2")
assert " ", test_scanner.peek
assert "3", test_scanner.skip(/\s/)
assert "3", test_scanner.peek
assert "3", test_scanner.consume("3")
assert nil, test_scanner.peek
assert nil, test_scanner.consume(nil)


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
	attr_accessor :first, :rest
	
	def initialize(first, rest)
		@first, @rest = first, rest
	end
	
	def ==(other)
		if other.kind_of? LispPair
			@first == other.first and @rest == other.rest
		else
			false
		end
	end
end


#
# Reader function that parses Lisp code and returns the AST of it
#

def read(scanner_or_code)
	scan = (scanner_or_code.kind_of? Scanner) ? scanner_or_code : Scanner.new(StringIO.new(scanner_or_code))
	scan.skip(/\s/)
	while scan.peek == ";"
		scan.until "\n"
		scan.skip(/\s/)
	end
	
	if scan.peek == nil
		LispNil.instance
	elsif scan.peek == "'"
		scan.consume "'"
		ast = read(scan)
		LispPair.new LispSym.new("quote"), LispPair.new(ast, LispNil.instance)
	elsif scan.peek == "("
		read_list(scan)
	else
		read_atom(scan)
	end
end

def read_atom(scan)
	if scan.peek == '"'
		# we got a string
		scan.consume '"'
		str = scan.until '"'
		scan.consume '"'
		raise LispException, "Unterminated string!" unless str
		LispStr.new str
	else
		word = scan.until(" ", "\t", "\n", ")", nil)
		raise LispException, "Got an empty atom!" if word.empty?
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
	scan.consume "("
	read_list_rest(scan)
end

def read_list_rest(scan)
	raise LispException, "Unterminated list!" if scan.peek.nil?
	scan.skip(/\s/)
	if scan.peek == ")"
		scan.consume ")"
		LispNil.instance
	else
		LispPair.new read(scan), read_list_rest(scan)
	end
end

assert LispPair.new(LispInt.new(1), LispNil.instance), read("(1)")
assert LispNil.instance, read("()")
assert LispNil.instance, read("(      )")
assert LispPair.new(LispPair.new(LispInt.new(1), LispNil.instance), LispNil.instance), read("((1))")
assert LispPair.new(LispSym.new("bla"), LispPair.new(LispInt.new(1), LispNil.instance)), read("(bla 1)")
assert LispPair.new(LispSym.new("quote"), LispPair.new(LispSym.new("a"), LispNil.instance)), read("'a")
assert LispNil.instance, read(" ")
assert LispNil.instance, read("\n")
assert LispNil.instance, read("\t")
assert LispNil.instance, read(" \n   \t")


#
# print function
#

def print_ast(ast, output_stack = [])
	if output_stack.include? ast
		"..."
	else
		if ast.kind_of? LispPair
			print_list(ast, output_stack + [ast])
		else
			print_atom(ast)
		end
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

def print_list(ast, output_stack)
	"(" + print_list_rest(ast, output_stack)
end

def print_list_rest(ast, output_stack)
	print_ast(ast.first, output_stack) + if ast.rest.kind_of? LispNil
		")"
	elsif ast.rest.kind_of? LispAtom
		" . #{print_atom(ast.rest)})"
	else
		" #{print_list_rest(ast.rest, output_stack)}"
	end
end

[
	"sym", "123", '"str"', "nil", "true", "false",
	"(1)", "(1 2)", "((a) (b c))",
	"(define eval_list (lambda (ast env) (apply_func (first ast) (rest ast) env)))"
].each do |sample|
	assert sample.strip, print_ast(read(sample))
end


#
# Environments used by eval. We use the build in Ruby hashes and add a reference
# to the parent environment.
#

class Environment < Hash
	attr_reader :parent
	def initialize(parent = nil)
		@parent = parent
	end
	
	def inspect(prefix = "")
		self.collect{|k, v| "#{prefix}#{k}: #{print_ast(v)}"}.join("\n")
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
		function_slot = eval_ast(ast.first, env)
		if function_slot.kind_of? LispSym and Object.private_methods.include? :"eval_#{function_slot.val}"
			Object.send :"eval_#{function_slot.val}", ast.rest, env
		elsif function_slot.kind_of? LispPair and function_slot.first.kind_of? LispSym and function_slot.first.val == "lambda"
			exec_lambda(function_slot.rest, ast.rest, env)
		else
			raise LispException, "Expected a build in or lambda in the function slot but got #{print_ast(function_slot)}"
		end
	end
rescue Exception => e
	unless e.kind_of? LispException
		lisp_excp = LispException.new e.message
		lisp_excp.original_exception = e
		e = lisp_excp
	end
	
	e.code << ast
	e.env << env
	raise e
end

def eval_cons(ast, env)
	raise LispException, "cons requires two arguments" unless ast.kind_of? LispPair
	LispPair.new eval_ast(ast.first, env), eval_ast(ast.rest.first, env)
end

def eval_first(ast, env)
	raise LispException, "first requires a pair as argument" unless ast.kind_of? LispPair
	params = ast.first
	eval_ast(params, env).first
end

def eval_rest(ast, env)
	raise LispException, "rest requires a pair as argument" unless ast.kind_of? LispPair
	params = ast.first
	eval_ast(params, env).rest
end

def eval_set_first(ast, env)
	pair = eval_ast(ast.first, env)
	val = eval_ast(ast.rest.first, env)
	pair.first = val
	pair
end

def eval_set_rest(ast, env)
	pair = eval_ast(ast.first, env)
	val = eval_ast(ast.rest.first, env)
	pair.rest = val
	pair
end

def eval_plus(ast, env)
	a = eval_ast(ast.first, env)
	b = eval_ast(ast.rest.first, env)
	raise LispException, "plus only works with values" unless a.kind_of? LispAtomWithValue and b.kind_of? LispAtomWithValue
	result = a.class.new(a.val + b.val)
	
	c_unevaled = ast.rest.rest
	if c_unevaled.kind_of? LispNil
		result
	else
		eval_plus(LispPair.new(result, c_unevaled), env)
	end
end

def eval_minus(ast, env)
	a = eval_ast(ast.first, env)
	b = eval_ast(ast.rest.first, env)
	raise LispException, "minus only works with values" unless a.kind_of? LispAtomWithValue and b.kind_of? LispAtomWithValue
	result = a.class.new(a.val - b.val)
	
	c_unevaled = ast.rest.rest
	if c_unevaled.kind_of? LispNil
		result
	else
		eval_minus(LispPair.new(result, c_unevaled), env)
	end
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

def eval_quote(ast, env)
	ast.first
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
			raise LispException, "Could not resolve symbol #{ast.val.inspect}"
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
	
	until param_names.kind_of? LispNil
		param = param_names.first
		if args.kind_of? LispNil
			lambda_env[param.val] = LispNil.instance
		else
			lambda_env[param.val] = eval_ast(args.first, env)
			args = args.rest
		end
		param_names = param_names.rest
	end
	
	eval_ast(body, lambda_env)
end

def eval_load(ast, env)
	file = ast.first.val
	val = LispNil.instance
	result = nil
	File.open(file) do |f|
		scan = Scanner.new f
		begin
			content = read(scan)
			$stderr.puts ">> #{print_ast(content)}"
			result = eval_ast(content, env)
			$stderr.puts "=> #{print_ast(result)}"
		end until f.eof?
	end
	return result
end

def eval_puts(ast, env)
	atom = eval_ast(ast.first, env)
	puts atom.val.gsub('\n', "\n").gsub('\t', "\t") + "\n"
	return atom
end

def eval_print(ast, env)
	atom = eval_ast(ast.first, env)
	print atom.val.gsub('\n', "\n").gsub('\t', "\t")
	return atom
end

def eval_to_s(ast, env)
	LispStr.new eval_ast(ast.first, env).val.to_s
end

def eval_inspect(ast, env)
	LispStr.new print_ast(eval_ast(ast.first, env))
end

def eval_error(ast, env)
	raise LispException, eval_ast(ast.first, env).val
end

def eval_symbol?(ast, env)
	arg = eval_ast(ast.first, env)
	arg.kind_of?(LispSym) ? LispTrue.instance : LispFalse.instance
end

def eval_pair?(ast, env)
	arg = eval_ast(ast.first, env)
	arg.kind_of?(LispPair) ? LispTrue.instance : LispFalse.instance
end

def eval_nil?(ast, env)
	arg = eval_ast(ast.first, env)
	arg.kind_of?(LispNil) ? LispTrue.instance : LispFalse.instance
end

def eval_atom?(ast, env)
	arg = eval_ast(ast.first, env)
	arg.kind_of?(LispAtom) ? LispTrue.instance : LispFalse.instance
end

def eval_begin(ast, env)
	result = LispNil.instance
	while ast.kind_of? LispPair
		result = eval_ast(ast.first, env)
		ast = ast.rest
	end
	result
end

#
# Build the global environment with entries for all build ins
#
global_env = Environment.new
Object.private_methods.select{|m| m.to_s.start_with? "eval_"}.collect{|m| m.to_s.gsub(/^eval_/, '')}.each do |name|
	global_env[name] = LispSym.new(name)
end


#
# Run some eval tests
#
test_env = global_env.dup
{
	"(cons 1 2)" => "(1 . 2)",
	"(first (cons 1 2))" => "1", "(rest (cons 1 2))" => "2",
	"(plus 1 2)" => "3", "(minus 2 1)" => "1",
	"(plus 1 2 3 4)" => "10", "(minus 2 1 1)" => "0",
	'(plus "hallo" " " "welt")' => '"hallo welt"',
	"(eq? 1 1)" => "true", "(eq? 1 2)" => "false",
	"(gt? 2 1)" => "true", "(gt? 1 2)" => "false",
	"(if true 1 2)" => "1", "(if false 1 2)" => "2", "(if (eq? 5 5) 1 2)" => "1",
	"(define a (plus 1 2))" => "3", "a" => "3",
	"(define inc (lambda (a) (plus a 1)))" => "(lambda (a) (plus a 1))",
	"(inc 2)" => "3",
	"((lambda (a b) (plus a b)) 1 2)" => "3",
	"(quote a)" => "a",
	'(quote (a 1 "b"))' => '(a 1 "b")',
	"(define var (cons 1 2))" => "(1 . 2)",
	"(set_first var 3)" => "(3 . 2)",
	"var" => "(3 . 2)",
	"(symbol? (quote abc))" => "true",
	"(symbol? 1)" => "false",
	"(pair? (cons 1 2))" => "true",
	"(nil? nil)" => "true",
	"(atom? 1)" => "true",
	"(atom? (quote sym))" => "true",
	'(atom? "str")' => "true",
	"(atom? (cons 1 2))" => "false",
	"(begin 1 2 3)" => "3"
}.each do |code, result|
	assert result, print_ast(eval_ast(read(code), test_env))
end
puts "All standard tests passed... RbLisp operational"


#
# input console
#

# Eval a file if a file name is given as argument
if ARGV.first
	begin
		puts "Evaling file #{ARGV.first}..."
		eval_load LispPair.new(LispStr.new(ARGV.first), LispNil.instance), global_env
	rescue LispException => e
		puts "error: #{e}"
		e.code.each_with_index do |ast, i|
			puts print_ast(ast)
			print "\e[2m"
			puts e.env[i].inspect("  ")
			print "\e[0m"
		end
		puts (e.original_exception ? e.original_exception : e).backtrace.join "\n"
	end
end

scan = Scanner.new($stdin)
print "> "
until $stdin.eof?
	begin
		ast = read(scan)
		puts print_ast(eval_ast(ast, global_env))
	rescue LispException => e
		puts "error: #{e}"
		e.code.each_with_index do |ast, i|
			puts print_ast(ast)
			print "\e[2m"
			puts e.env[i].inspect("  ")
			print "\e[0m"
		end
		puts (e.original_exception ? e.original_exception : e).backtrace.join "\n"
	end
	print "> "
end

print "\nHave a nice day :)\n"
