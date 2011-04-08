import std.stdio, std.string;
static import std.ctype, std.conv;

struct scanner {
	string input;
	uint pos;
	
	char peek(){
		if (pos < input.length)
			return input[pos];
		return '\0';
	}
	
	char consume(char[] options ...){
		if ( !(pos < input.length) )
			return '\0';
		
		foreach(option; options){
			if (input[pos] == option){
				pos++;
				return option;
			}
		}
		
		throw new Exception(format("Expected one of %s at %s", options, this.rest));
	}
	
	char next(){
		if (pos < input.length)
			return input[pos++];
		return '\0';	
	}
	
	void skip_whitespaces(){
		while( pos < input.length && (input[pos] == ' ' || input[pos] == '\n' || input[pos] == '\t') )
			pos++;
	}
	
	string until(char[] terminators ...){
		auto start = pos;
		
		while(pos < input.length){
			foreach(term; terminators){
				if (input[pos] == term)
					return input[start..pos];
			}
			pos++;
		}
		
		throw new Exception(format("Expected to find one of %s at %s", terminators, this.rest));
	}
	
	string rest(){
		return input[pos..$];
	}
	
	bool finished(){
		return ! (pos < input.length);
	}
}

bool conforms(string subject, int function(dchar) classifier){
	foreach(dchar c; subject){
		if (!classifier(c))
			return false;
	}
	return true;
}

/+
class Element {
	static Element from_input(string input){
		if ( conforms(input, &std.ctype.isdigit) ){
			return new Int(std.conv.toInt(input));
		} else if ( input[0] == '"' ) {
			return new String(input[1..($-1)]);
		} else {
			return new Symbol(input);
		}
	}
}

class Atom : Element {
}

class Symbol : Atom {
	public string value;
	this(string value){ this.value = value; }
}

class Int : Atom {
	public int value;
	this(int value){ this.value = value; }
}

class String : Atom {
	public string value;
	this(string value){ this.value = value; }
}

class Nil : Atom {
	
}

class Cons : Element {
	public 
}

+/


struct val_t {
	enum type_t {SYM, INT, FLOAT, STR};
	type_t type;
	
	union {
		string sym_val;
		int int_val;
		float float_val;
		string str_val;
	}
	
	static val_t from_input(string input){
		val_t val;
		
		if ( conforms(input, &std.ctype.isdigit) ){
			val.type = type_t.INT;
			val.int_val = std.conv.to!int(input);
		} else if ( input[0] == '"' ) {
			val.type = type_t.STR;
			val.str_val = input[1..($-1)];
		} else {
			val.type = type_t.SYM;
			val.sym_val = input;
		}
		
		return val;
	}
	
	string toString(){
		switch(type){
			case type_t.SYM: return format(":%s", sym_val); break;
			case type_t.INT: return format("%d", int_val); break;
			case type_t.FLOAT: return format(":%f", float_val); break;
			case type_t.STR: return format("\"%s\"", str_val); break;
		}
	}
}

void main(string[] args){
	
	if (args.length < 2){
		writefln("Code required!");
		return;
	}
	
	auto scan = scanner(args[1]);
	while(!scan.finished)
		read(scan);
}

void read(ref scanner scan){
	writefln("read: %s", scan.rest);
	scan.skip_whitespaces();
	
	if (scan.peek == '(') {
		read_list(scan);
	} else {
		read_atom(scan);
	}
}

val_t read_atom(ref scanner scan){
	writefln("read atom: %s", scan.rest);
	scan.skip_whitespaces();
	
	auto atom = scan.until('(', ')', ' ', '.', '\t', '\n');
	auto val = val_t.from_input(atom);
	writefln("found: %s, %s", atom, val.toString());
	return val;
}

void read_list(ref scanner scan){
	writefln("read list: %s", scan.rest);
	// consume '(' or '.'
	scan.next();
	
	while (scan.peek != ')'){
		read(scan);
		scan.skip_whitespaces();
	}
	
	//while( scan.next == '.' )
	//	read(scan);
}
