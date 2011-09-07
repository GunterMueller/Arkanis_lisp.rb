# encoding: utf-8
require File.dirname(__FILE__) + '/common'
require 'test/unit/assertions'

include Test::Unit::Assertions

module Reader
	
	class LispSyntaxException < LispException
	end
	
	# This class allows the scanner to access a string in the same way as files. The StringIO of the
	# standard library didn't work that well.
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
			raise LispSyntaxException, "Unexpected end of string, expected #{sep.inspect} before end of string" unless end_pos
			@pos = end_pos + sep.length
			@str[start_pos .. end_pos]
		end
		
		def eof?
			@pos >= @str.length
		end
	end
	
	def self.test_string_io
		test_io = StringIO.new "abc 123e"
		assert_equal false, test_io.eof?
		assert_equal "a", test_io.getc
		assert_equal "b", test_io.getc
		assert_equal "c", test_io.getc
		test_io.ungetc "c"
		assert_equal "c", test_io.getc
		test_io.ungetc "b"
		assert_equal "b", test_io.getc
		assert_equal " ", test_io.getc
		assert_equal "123", test_io.gets("3")
		assert_equal false, test_io.eof?
		assert_equal "e", test_io.getc
		assert_equal nil, test_io.getc
		assert_equal true, test_io.eof?
	end
	
	
	# A small scanner class for the read functions.
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
			raise LispSyntaxException, "Expected one of #{alternatives.inspect} but got #{char.inspect}" unless alternatives.include? char
			char
		end
		
		def until(*alternatives)
			result = ""
			while true
				char = @io.getc
				break if alternatives.include? char
				raise LispSyntaxException, "Expected one of #{alternatives.inspect} but got #{char.inspect}" unless char
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
			@io.ungetc char if char
			char
		end
		
		def stream
			@io
		end
	end
	
	def self.test_scanner
		test_scanner = Scanner.new StringIO.new("abc 12 \t 3")
		assert_equal "a", test_scanner.peek
		assert_equal "a", test_scanner.consume("a", "b")
		assert_equal "b", test_scanner.consume("a", "b")
		assert_equal "c 1", test_scanner.until("2")
		assert_equal "2", test_scanner.peek
		assert_equal "2", test_scanner.consume("2")
		assert_equal " ", test_scanner.peek
		assert_equal "3", test_scanner.skip(/\s/)
		assert_equal "3", test_scanner.peek
		assert_equal "3", test_scanner.consume("3")
		assert_equal nil, test_scanner.peek
		assert_equal nil, test_scanner.consume(nil)
	end
	
	# From now on we only define methods of the Reader module
	class << self
		
		# Reader function that parses Lisp code and returns the abstract syntax tree of it. Read accepts
		# an instance of a Scanner class (see above) or a plain string. The AST is composed of LispElement
		# subclasses defined in common.rb. If an EOF is encountered `nil` is returned.
		def read(scanner_or_code)
			scan = (scanner_or_code.kind_of? Scanner) ? scanner_or_code : Scanner.new(StringIO.new(scanner_or_code))
			scan.skip(/\s/)
			while scan.peek == ";"
				scan.until "\n"
				scan.skip(/\s/)
			end
			
			if scan.peek == nil
				nil
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
				raise LispSyntaxException, "Unterminated string!" unless str
				LispStr.new str
			else
				word = scan.until(" ", "\t", "\n", "\r", ")", nil)
				if word.empty?
					nil  # probably end of file
				elsif word == "nil" or word == "null"
					LispNil.instance
				elsif word == "true"
					LispTrue.instance
				elsif word == "false"
					LispFalse.instance
				elsif word =~ /^\d+$/
					LispInt.new word.to_i
				else
					LispSym.new word
				end
			end
		end
		
		def test_read_atom
			assert_equal LispStr.new(""), read('""')
			assert_equal LispStr.new("test"), read('"test"')
			assert_equal LispNil.instance, read('nil')
			assert_equal LispTrue.instance, read('true')
			assert_equal LispFalse.instance, read('false')
			assert_equal LispInt.new(123), read('123')
			assert_equal LispInt.new(123), read(' 123 ')
			assert_equal LispSym.new("name"), read('name')
			assert_equal LispSym.new("name"), read(' name ')
			assert_equal LispSym.new("_x"), read('_x')
			assert_equal LispSym.new("_0"), read('_0')
		end
		
		def read_list(scan)
			scan.consume "("
			read_list_rest(scan)
		end
		
		def read_list_rest(scan)
			raise LispSyntaxException, "Unterminated list!" if scan.peek.nil?
			scan.skip(/\s/)
			if scan.peek == ")"
				scan.consume ")"
				LispNil.instance
			else
				LispPair.new read(scan), read_list_rest(scan)
			end
		end
		
		def test_read_list
			assert_equal LispPair.new(LispInt.new(1), LispNil.instance), read("(1)")
			assert_equal LispNil.instance, read("()")
			assert_equal LispNil.instance, read("(      )")
			assert_equal LispPair.new(LispPair.new(LispInt.new(1), LispNil.instance), LispNil.instance), read("((1))")
			assert_equal LispPair.new(LispSym.new("bla"), LispPair.new(LispInt.new(1), LispNil.instance)), read("(bla 1)")
			assert_equal LispPair.new(LispSym.new("quote"), LispPair.new(LispSym.new("a"), LispNil.instance)), read("'a")
			assert_equal nil, read(" ")
			assert_equal nil, read("\n")
			assert_equal nil, read("\t")
			assert_equal nil, read(" \n   \t")
		end
		
		def test(show_log = false)
			test_output_wrapper show_log, "StringIO" do
				test_string_io
			end
			test_output_wrapper show_log, "Scanner" do
				test_scanner
			end
			test_output_wrapper show_log, "Atom reader" do
				test_read_atom
			end
			test_output_wrapper show_log, "List reader" do
				test_read_list
			end
		end
		
	end
end