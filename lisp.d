import reader, std.stdio;

void main(){
	char[] input;
	size_t bytes_read;
	
	while(true){
		write("> ");
		bytes_read = readln(input);
		if (bytes_read == 0)
			break;
		
		try {
			auto code = read(input[0 .. $-1].idup);
			auto result = eval(code);
			writeln(print(result));
		} catch(Exception e) {
			writefln("Something exploded: %s", e.msg);
		}
	}
	
	writeln("\nExiting, have a nice day :)");
}

Element eval(Element code){
	auto list = cast(Pair) code;
	if (list !is null) {
		auto function_slot = list.first;
		auto sym = cast(Symbol) function_slot;
		if ( sym !is null ) {
			// We got a list with a symbol in the function slot
			switch(sym.val){
				case "plus":
					return eval_plus(list.rest);
				case "minus":
					return eval_minus(list.rest);
				case "cons":
					return eval_cons(list.rest);
				case "first":
					return eval_first(list.rest);
				case "rest":
					return eval_rest(list.rest);
				case "gt?":
					return eval_gt(list.rest);
				case "eq?":
					return eval_eq(list.rest);
				case "if":
					return eval_if(list.rest);
				default:
					return code;
			}
		} else {
			// We got a list
			return code;
		}
	} else {
		// We got an atom
		return code;
	}
}

Int eval_plus(Element code){
	auto list = cast(Pair) code;
	if (list is null)
		return new Int(0);
	
	auto int_val = cast(Int) eval(list.first);
	if (int_val is null)
		throw new Exception("plus: only works with Int");
	
	return new Int(int_val.val + eval_plus(list.rest).val);
}

Int eval_minus(Element code){
	auto list = cast(Pair) code;
	if (list is null)
		return new Int(0);
	
	auto int_val = cast(Int) eval(list.first);
	if (int_val is null)
		throw new Exception("plus: only works with Int");
	
	return new Int(int_val.val - eval_minus(list.rest).val);
}

Pair eval_cons(Element code){
	auto list = cast(Pair) code;
	if (list is null)
		throw new Exception("cons: only works with 2 args");
	
	return new Pair(eval(list.first), eval(list.rest));
}

Element eval_first(Element code){
	auto list = cast(Pair) code;
	if (list is null)
		throw new Exception("first: need one argument");
	
	auto evaled_arg = eval(list.first);
	auto result_list = cast(Pair) evaled_arg;
	if (result_list is null)
		throw new Exception("first: only works on lists");
	
	return result_list.first;
}

Element eval_rest(Element code){
	auto list = cast(Pair) code;
	if (list is null)
		throw new Exception("rest: need one argument");
	
	auto evaled_arg = eval(list.first);
	auto result_list = cast(Pair) evaled_arg;
	if (result_list is null)
		throw new Exception("rest: only works on lists");
	
	return result_list.rest;
}

Element eval_gt(Element code){
	auto list = cast(Pair) code;
	
	auto arg1 = cast(Int) eval(list.first);
	auto arg2 = cast(Int) eval((cast(Pair) list.rest).first);
	
	if (arg1.val > arg2.val)
		return TrueClass.instance;
	else
		return FalseClass.instance;
}

Element eval_eq(Element code){
	auto list = cast(Pair) code;
	
	auto arg1 = cast(Int) eval(list.first);
	auto arg2 = cast(Int) eval((cast(Pair) list.rest).first);
	
	if (arg1.val == arg2.val)
		return TrueClass.instance;
	else
		return FalseClass.instance;
}

Element eval_if(Element code){
	auto list = cast(Pair) code;
	
	auto cond = eval(list.first);
	if (cond == TrueClass.instance)
		return eval( (cast(Pair) list.rest).first );
	else
		return eval( (cast(Pair) (cast(Pair) list.rest).rest).first );
}
