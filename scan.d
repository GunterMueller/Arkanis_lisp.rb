import std.string;

struct scanner {
	string input;
	uint pos;
	
	/**
	 * Returns the current character without incrementing the position.
	 */
	immutable(char) peek(){
		if (this.ended)
			return '\0';
		return input[pos];
	}
	
	/**
	 * Consumes and returns the current character.
	 */
	immutable(char) next(){
		if (this.ended)
			return '\0';
		return input[pos++];
	}
	
	/**
	 * Consumes one of the specified characters and returns it. You can use '\0'
	 * to represent the end of the string. If no option matches the current
	 * character an exception is thrown.
	 */
	immutable(char) one_of(immutable(char)[] options ...){
		foreach(option; options){
			if (option == '\0') {
				if (this.ended)
					return '\0';
			} else {
				if (!this.ended && input[pos] == option) {
					pos++;
					return option;
				}
			}
		}
		
		throw new Exception(format("Expected one of %s at %s", options, this.rest));
	}
	
	/**
	 * Consumes the string until one of the terminators is found. The consumed
	 * string is returned. The terminator is not consumed. If none of the
	 * terminators was found before the end of string an exception is thrown.
	 * If '\0' is the last specified terminator an end of string is a valid
	 * terminator and no execption is thrown but the matching string is returned.
	 */
	string until(immutable(char)[] terminators ...){
		auto start = pos;
		
		while(pos < input.length){
			foreach(term; terminators){
				if (term != '\0' && input[pos] == term)
					return input[start..pos];
			}
			pos++;
		}
		
		foreach(term; terminators){
			if (term == '\0')
				return input[start..$];
		}
		
		throw new Exception(format("Expected to find one of %s at %s", terminators, this.rest));
	}
	
	/**
	 * Consumes all whitespaces.
	 */
	void skip_whitespaces(){
		while( pos < input.length && (input[pos] == ' ' || input[pos] == '\n' || input[pos] == '\t') )
			pos++;
	}
	
	/**
	 * Returns the rest of the string.
	 */
	string rest(){
		return input[pos..$];
	}
	
	/**
	 * Returns `true` if the scanner is at the end of the string.
	 */
	bool ended(){
		return ! (pos < input.length);
	}
}

unittest {
	auto scan = scanner("abc 123");
	
	assert(scan.one_of('a', 'b') == 'a');
	assert(scan.one_of('c', 'b') == 'b');
	assert(scan.until('2', '3') == "c 1");
	assert(scan.until('\0') == "23");
	
	scan = scanner("  word");
	scan.skip_whitespaces();
	assert(scan.rest == "word");
	assert(scan.until('\0') == "word");
	assert(scan.one_of('\0') == '\0');
	assert(scan.ended);
}
