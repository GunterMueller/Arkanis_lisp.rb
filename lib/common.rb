# encoding: utf-8
require 'singleton'

# A small output wrapper for running test cases
def test_output_wrapper(show_log, test_name)
	$stderr.print "Testing #{test_name}… " if show_log
	yield
	$stderr.puts "passed" if show_log
end

# The base exception for everything the interpreter does
class LispException < RuntimeError
end


#
# Elements of the Lisp abstract syntax tree
#

class LispElement
end

class LispAtom < LispElement
end

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

class LispSym < LispAtomWithValue
end

class LispStr < LispAtomWithValue
end

class LispInt < LispAtomWithValue
end


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

class LispLambda < LispAtom
	attr_accessor :arg_names, :body, :env
	
	def initialize(arg_names, body, env)
		@arg_names, @body, @env = arg_names, body, env
	end
end

# Ment to be a container for an opaque object (e.g. a File object) that need
# to be passed around in lisp.
class LispResource < LispAtom
	attr_accessor :data
	
	def initialize(data)
		@data = data
	end
end