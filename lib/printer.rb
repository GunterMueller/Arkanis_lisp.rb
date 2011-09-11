# encoding: utf-8
require File.dirname(__FILE__) + '/common'
require File.dirname(__FILE__) + '/reader'
require 'test/unit/assertions'

include Test::Unit::Assertions

# We add an to_s method to the Lisp AST elements. This way rubys to_s method will
# show us proper Lisp code instead of unreadable object dumps. The printer is just
# a frontend to these to_s methods.

class LispNil
	def to_s
		"nil"
	end
end

class LispTrue
	def to_s
		"true"
	end
end

class LispFalse
	def to_s
		"false"
	end
end

class LispAtomWithValue
	def to_s
		val.to_s
	end
end

class LispStr
	def to_s
		"\"#{val}\""
	end
end

class LispPair
	def to_s(output_stack = [])
		if output_stack.include? self
			"..."
		else
			"(" + to_s_tail(output_stack << self)
		end
	end
	
	def to_s_tail(output_stack)
		first_str = (first.kind_of? LispPair or first.kind_of? LispLambda) ? first.to_s(output_stack) : first.to_s
		rest_str = if rest.kind_of? LispNil
			")"
		elsif rest.kind_of? LispPair
			" #{rest.to_s_tail(output_stack)}"
		elsif rest.kind_of? LispLambda
			" #{rest.to_s(output_stack)}"
		else rest.kind_of? LispAtom
			" . #{rest})"
		end
		
		first_str + rest_str
	end
end

class LispLambda
	def to_s(output_stack = [])
		"(lambda (#{arg_names.join(' ')}) #{body.kind_of?(LispPair) ? body.to_s(output_stack << self) : body.to_s})"
	end
end

class LispResource
	def to_s
		"resource#{@data.inspect}"
	end
end


# The printer module used by the interpreter.
module Printer
	class << self
		def print(ast)
			ast.to_s
		end
		
		def test(show_log = false)
			test_output_wrapper show_log, "Printer" do
				[
					"sym", "123", '"str"', "nil", "true", "false",
					"(1)", "(1 2)", "((a) (b c))",
					"(define eval_list (lambda (ast env) (apply_func (first ast) (rest ast) env)))"
				].each do |sample|
					assert_equal sample.strip, Printer.print( Reader.read(sample) )
				end
			end
		end
	end
end