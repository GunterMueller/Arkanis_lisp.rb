#!/usr/bin/ruby1.9.1
# encoding: utf-8

# command line options
require "getoptlong"

opts = GetoptLong.new(
	["--help", "-h", GetoptLong::NO_ARGUMENT],
	["--interactive", "-i", GetoptLong::NO_ARGUMENT],
	["--code", "-c", GetoptLong::REQUIRED_ARGUMENT],
	["--log-tests", GetoptLong::NO_ARGUMENT],
	["--log-conts", GetoptLong::OPTIONAL_ARGUMENT]
)
opts.ordering = GetoptLong::REQUIRE_ORDER

options = { interactive: nil, lisp_file: nil, lisp_code: nil, lisp_args: [], log_tests: false, log_conts: 0 }
usage = <<EOD
lisp.rb - A small Lisp interpreter written in Ruby 1.9

#{$0} [OPTIONS] [FILE [SCRIPT-OPTIONS]]

Executes the Lisp code in FILE, passing any optional SCRIPIT-OPTION on to the executed
Lisp script. If no file was specified an interactive Lisp shell is started.

-h, --help
	Show this help message

-i, --interactive
	Starts an interactive Lisp shell after all files have been executed.
	The shell is automatically started if no lisp files are specified as
	arguments. So you only need this if you want to execute files and
	have an interactive shell.

-c CODE, --code CODE
	Executes CODE after FILE has been executed.

--log-tests
	Outputs the tests performed during startup to verify that the
	interpreter is operational to stderr.

--log-conts [DEPTHS]
	Outputs each continuation to stderr. The optional argument is the depts
	of the continuation chain shown. 1 just shows the current continuation,
	2 the current and the next, and so on. Default is 2.
EOD

opts.each do |opt, arg|
	case opt
		when "--help"
			puts usage
			exit
		when "--interactive"
			options[:interactive] = true
		when "--code"
			options[:lisp_code] = arg
		when "--log-tests"
			options[:log_tests] = true
		when "--log-conts"
			options[:log_conts] = arg.empty? ? 2 : arg.to_i
	end
end

options[:lisp_file] = ARGV.shift if ARGV.size > 0
options[:interactive] = options[:lisp_file].nil? if options[:interactive].nil?
options[:lisp_args] = ARGV

# Load the modules (reader and printer are loaded by the evaluator) and test them
require File.dirname(__FILE__) + '/lib/evaluator'

Reader.test options[:log_tests]
Printer.test options[:log_tests]
Evaluator.test options[:log_tests], options[:log_conts]
$stderr.puts "All tests passed... lisp.rb interpreter operational" if options[:log_tests]


#
# The basic read-eval-print loop in continuation passing style (CPS)
#

$global_env = Evaluator.construct_buildin_env

$input_streams = []
$input_streams << File.new(options[:lisp_file]) if options[:lisp_file]
$input_streams << options[:lisp_code] if options[:lisp_code]
$input_streams << $stdin if options[:interactive]


# Reads an AST from the topmost input stream in the queue and passes it to
# `eval`. If the current input stream is `$stdin` a prompt is shown on $stdout
# and a print continuation is inserted to output the results of the evaluation.
# 
# Once an input stream is finished (EOF) the next one is used. If no input stream
# is left `nil` is returned to exit the interpreter trampoline.
# 
# Expected arguments: none
# 
# Gives to the next continuation:
# - ast: The unevaled AST read from the input stream
# - env: The global environment in which the input AST should be evaled
def read_stream(args, current_cont)
	scanner = args[:scanner]
	
	# If no scanner is set in the args we have no input stream open. Take the
	# next stream and use it for a new scanner. If no stream is left exit the trampoline.
	unless scanner
		return nil if $input_streams.empty?
		
		input_stream = $input_streams.shift
		input_stream = Reader::StringIO(input_stream) if input_stream.kind_of?(String)
		scanner = Reader::Scanner.new input_stream
		
		# Store the new scanner in our continuations arguments. This will
		# be here if the continuation is run the next time.
		current_cont.args[:scanner] = scanner
	end
	
	$stdout.print "> " and $stdout.flush if scanner.stream == $stdin
	begin
		input_ast = Reader.read(scanner)
	rescue Interrupt
		return nil
	end
	
	# Check if we are at the end of a stream or got an empty input line in
	# interactive mode.
	if input_ast.nil?
		# Remove the scanner if the stream is finished. The next stream will
		# be opened on the next invocation.
		current_cont.args.delete(:scanner) if scanner.stream.eof?
		
		# Restart with reading. If we got an empty input line there is nothing
		# more we can do.
		return current_cont
	end
	
	# This is a bit ugly. If we are in interactive mode ($stdin) `eval` (the next cont)
	# should be followed by `print_result` (which in turn calls us again). Without
	# interactive mode eval should directly continue with us.
	if scanner.stream == $stdin
		current_cont.next.next = Evaluator::Continuation.new current_cont, method(:print_result)
	else
		current_cont.next.next = current_cont
	end
	
	return current_cont.next_with(ast: input_ast, env: $global_env)
end

# Outputs the given AST to stdout and continues with the next continuation (no
# args are set).
# 
# Expected arguments:
# - ast: The AST to output
def print_result(args, current_cont)
	puts Printer.print(args[:ast])
	return current_cont.next
end

# We only need the read cont followed by the eval cont. The print cont
# is inserted by the read cont whenever necessary.
eval_cont = Evaluator::Continuation.new nil, Evaluator.method(:eval)
read_cont = Evaluator::Continuation.new eval_cont, method(:read_stream)




=begin
$input_stream = $stdin
$scan = Reader::Scanner.new($input_stream)

# Reads from the input scanner (global variable `scan`). Expects no arguments.
def read_cps(args, current_cont)
	# Exit the trampoline if the input stream is finished
	#return nil if $input_stream.eof?
	
	$stdout.print "> "
	$stdout.flush
	read_ast = Reader.read($scan)
	return nil if read_ast.nil? or $input_stream.eof?
	
	# continue with next cont (usually eval) and give the read AST and the global
	# environment to it
	return current_cont.next_with(ast: read_ast, env: $global_env)
rescue LispException => e
	puts "error while reading: #{e}"
	
	# Retry this continuation again (continue with reading)
	return current_cont
end



read_cont = Evaluator::Continuation.new nil, method(:read_cps)
eval_cont = Evaluator::Continuation.new nil, Evaluator.method(:eval)
print_cont = Evaluator::Continuation.new nil, method(:print_cps)

read_cont.next = eval_cont
eval_cont.next = print_cont
print_cont.next = read_cont
=end

#
# The continuation trampoline, start of with the read continuation
#

cont = read_cont
cont_log_depth = options[:log_conts]
while cont
	puts cont.to_s(cont_log_depth) if cont_log_depth > 0
	cont = cont.func.call(cont.args, cont)
end

$stderr.print "\nBye. Have a nice day :)\n" if options[:interactive]