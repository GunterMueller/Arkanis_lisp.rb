import scan;
static import std.ctype, std.conv;
import std.stdio, std.string;

/**
 * Tests if every character of a string conforms to the specified function.
 */
bool conforms(string subject, int function(dchar) classifier){
	foreach(dchar c; subject){
		if (!classifier(c))
			return false;
	}
	return true;
}

class Element {
	string print(){ return "unknown"; };
	bool isAtom(){ return false; }
}

class Atom : Element {
	static Atom Nil, True, False;
	
	static this(){
		Nil = new Atom();
		True = new Atom();
		False = new Atom();
	}
	
	bool isAtom(){ return true; }
}

class String : Atom {
	public string val;
	this(string val){ this.val = val; }
	
	override bool opEquals(Object other){
		auto other_string = cast(String) other;
		if (other_string is null)
			return false;
		return this.val == other_string.val;
	}
	
	override string print(){
		return format(`"%s"`, val);
	}
}

class Symbol : Atom {
	public string val;
	this(string val){ this.val = val; }
	
	override bool opEquals(Object other){
		auto other_sym = cast(Symbol) other;
		if (other_sym is null)
			return false;
		return this.val == other_sym.val;
	}
	
	override string print(){
		return val;
	}
}

class Int : Atom {
	public long val;
	this(long val){ this.val = val; }
	
	override bool opEquals(Object other){
		auto other_int = cast(Int) other;
		if (other_int is null)
			return false;
		return this.val == other_int.val;
	}
	
	override string print(){
		return std.conv.to!string(val);
	}
}

class NilClass : Atom {
	private static NilClass singleton;
	static NilClass instance(){
		if (singleton is null)
			singleton = new NilClass();
		return singleton;
	}
	private this(){}
	
	override string print(){
		return "nil";
	}
}

class TrueClass : Atom {
	private static TrueClass singleton;
	static TrueClass instance(){
		if (singleton is null)
			singleton = new TrueClass();
		return singleton;
	}
	private this(){}
	
	override string print(){
		return "true";
	}
}

class FalseClass : Atom {
	private static FalseClass singleton;
	static FalseClass instance(){
		if (singleton is null)
			singleton = new FalseClass();
		return singleton;
	}
	private this(){}
	
	override string print(){
		return "false";
	}
}

class Pair : Element {
	public Element first, rest;
	this(Element first, Element rest){
		this.first = first;
		this.rest = rest;
	}
	
	override string print(){
		return "(" ~ this.print_rest();
	}
	
	private string print_rest(){
		auto rest_pair = cast(Pair) rest;
		if (rest_pair !is null)
			return format("%s %s", first.print(), rest_pair.print_rest());
		
		auto rest_nil = cast(NilClass) rest;
		if (rest_nil)
			return format("%s)", first.print());
		
		return format("%s . %s)", first.print(), rest.print());
	}
}



Element read(string code){
	auto scan = scanner(code);
	return read(scan);
}

Element read(ref scanner scan){
	scan.skip_whitespaces();
	if (scan.peek == '(')
		return read_list(scan);
	else
		return read_atom(scan);
}

/**
 * Reads one atom and returns it's value
 */
Atom read_atom(ref scanner scan){
	if (scan.peek == '"') {
		// Got a string
		scan.one_of('"');
		auto content = scan.until('"');
		scan.one_of('"');
		return new String(content);
	} else {
		// Got a one word atom
		auto word = scan.until(' ', ')', '\0');
		
		if (word.length == 0)
			return NilClass.instance;
		if (word == "nil")
			return NilClass.instance;
		if (word == "true")
			return TrueClass.instance;
		if (word == "false")
			return FalseClass.instance;
		if (conforms(word, &std.ctype.isdigit))
			return new Int(std.conv.to!int(word));
		
		return new Symbol(word);
	}
}

unittest {
	assert(read_atom(scanner("")) == NilClass.instance);
	assert(read_atom(scanner("nil")) == NilClass.instance);
	assert(read_atom(scanner("true")) == TrueClass.instance);
	assert(read_atom(scanner("false")) == FalseClass.instance);
	assert(read_atom(scanner(`"str"`)) == new String("str"));
	assert(read_atom(scanner("1")) == new Int(1));
	assert(read_atom(scanner("9987")) == new Int(9987));
	assert(read_atom(scanner("sym")) == new Symbol("sym"));
}

/**
 * Reads a list of atoms
 */
Element read_list(ref scanner scan){
	scan.one_of('(');
	return read_list_rest(scan);
}

Element read_list_rest(ref scanner scan){
	scan.skip_whitespaces();
	if (scan.peek == ')') {
		scan.one_of(')');
		return NilClass.instance;
	} else if (scan.ended) {
		throw new Exception("unterminated list");
	} else {
		auto first = read(scan);
		auto rest = read_list_rest(scan);
		return new Pair(first, rest);
	}
}

unittest {
	assert(read_list(scanner("()")) == NilClass.instance);
	
	Pair list = cast(Pair) read_list(scanner("(1)"));
	assert(list.first == new Int(1));
	assert(list.rest == NilClass.instance);
	
	list = cast(Pair) read_list(scanner("(abc def)"));
	assert(list.first == new Symbol("abc"));
	assert((cast(Pair)list.rest).first == new Symbol("def"));
	assert((cast(Pair)list.rest).rest == NilClass.instance);
}


/**
 * Prints the parsed stuff
 */
string print(Element code){
	return code.print();
}

unittest {
	string[] samples = [
		"true", "false", "nil", "1", "123", "sym", `"str"`,
		"(1)", "(123 abc)", "((abc) 1)"
	];
	
	foreach(sample; samples){
		auto code = read(scanner(sample));
		auto output = print(code);
		assert(sample == output, format(`print sample failed, expected "%s", got "%s"`, sample, output));
	}
}
