typedef class Context;
typedef class Stmt;
typedef class Value;
typedef class Func;

typedef class Context;
typedef class Value;

integer STDIN;

function automatic void run(Context ctx, integer fd, string prompt);
	Value v = new;
	Value r;

	while (!$feof(fd)) begin
		$write(prompt);
		r = v.parse(fd);
		if (r != null)
			void'(r.eval(ctx));
	end
endfunction

class Context;
	Context upper;
	Value vars[string];

	function automatic new(Context u = null);
		upper = u;
	endfunction

	function automatic void def(string s, Value v);
		vars[s] = v;
	endfunction

	function automatic void set(string s, Value v);
		if (bit'(vars.exists(s)))
			vars[s] = v;
		else if (upper != null)
			upper.set(s, v);
		else
			$error("undefined variable: %s", s);
	endfunction

	function automatic Value get(string s);
		if (bit'(vars.exists(s)))
			return vars[s];
		if (upper != null)
			return upper.get(s);
		$error("undefined variable: %s", s);
	endfunction
endclass

class Value;
	extern function Value parse(integer f);

	static integer indent = 0;
	static string space = "  ";

	virtual function automatic string format();
		return "nil";
	endfunction

	virtual function automatic string help();
		return "no help string for this object";
	endfunction

	virtual function automatic Value eval(Context ctx);
		return this;
	endfunction

	function automatic Value debug_eval(Context ctx);
		Value r;
		$display("%s%s", {indent{space}}, this.format());
		indent++;
		r = this.eval(ctx);
		indent--;
		$display("%svalue: %s\n", {indent{space}}, r.format());
		return r;
	endfunction
endclass

class List extends Value;
	Value v[$];

	virtual function automatic string format();
		string s = "(";

		foreach (v[i])
			s = {s, v[i].format(), i+1 < v.size() ? " " : ""};
		s = {s, ")"};
		return s;
	endfunction

	virtual function automatic string help();
		return "an object of list type";
	endfunction

	virtual function automatic Value eval(Context ctx);
		Value r = v[0].eval(ctx);
		Stmt f;
		Func l;
		if ($cast(f, r)) begin
			return f.call(ctx, this);
		end else if ($cast(l, r)) begin
			Value res;
			List args;
			Context c = new(l.scope);
			$cast(args, l.v[1]);
			foreach (args.v[i])
				c.def(args.v[i].format(), v[i+1].eval(ctx));
			for (integer i = 2; i < l.v.size(); i++)
				res = l.v[i].eval(c);
			return res;
		end
		return this;
	endfunction
endclass

class Func extends List;
	Context scope;

	function automatic new(Context s, List args);
		scope = s;
		v = args.v;
	endfunction

	virtual function automatic string help();
		return "an object of function type";
	endfunction
endclass

class Number extends Value;
	integer v;

	function automatic new(integer n = 0);
		v = n;
	endfunction

	virtual function automatic string format();
		string s;

		s.itoa(v);
		return s;
	endfunction

	virtual function automatic string help();
		return "an object of number type";
	endfunction
endclass

class String extends Value;
	string v;

	function automatic new(string s = "");
		v = s;
	endfunction

	virtual function automatic string format();
		return v;
	endfunction

	virtual function automatic string help();
		return "an object of string type";
	endfunction
endclass

class Symbol extends Value;
	string v;

	function automatic new(string s = "");
		v = s;
	endfunction

	virtual function automatic string format();
		return v;
	endfunction

	virtual function automatic string help();
		return "an object of symbol type";
	endfunction

	virtual function automatic Value eval(Context ctx);
		return ctx.get(v);
	endfunction
endclass

class Stmt extends Value;
	string name;

	virtual function automatic void create(Context ctx, string n);
		name = n;
		ctx.def(n, this);
	endfunction

	virtual function automatic string format();
		return {"[built-in \"", name, "\"]"};
	endfunction

	virtual function automatic string help();
		return "an object of built-in function type";
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		$error("undefined function automatic: %s", args.v[0].format());
	endfunction
endclass

class StmtImport extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "import");
	endfunction

	virtual function automatic string help();
		return {"(import {source path})\n\n",
		        "reads files and runs them in the current scope"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		String s;
		integer fd;

		$cast(s, args.v[1].eval(ctx));
		fd = $fopen(s.v, "r");
		run(ctx, fd, "");
		$fclose(fd);
	endfunction
endclass

class StmtDef extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "def");
	endfunction

	virtual function automatic string help();
		return {"(def {symbol} {value})\n\n",
		        "defines a variable and initiates it with a value"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		ctx.def(args.v[1].format(), args.v[2].eval(ctx));
		return args;
	endfunction
endclass

class StmtSet extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "set");
	endfunction

	virtual function automatic string help();
		return {"(set {symbol} {value})\n\n",
		        "sets variable to a value"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		ctx.set(args.v[1].format(), args.v[2].eval(ctx));
		return args;
	endfunction
endclass

class StmtFn extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "fn");
	endfunction

	virtual function automatic string help();
		return {"(fn ([argument name] ...) [expression] ...)\n\n",
						"creates a function object"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Func f = new(ctx, args);
		return f;
	endfunction
endclass

class StmtDo extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "do");
	endfunction

	virtual function automatic string help();
		return {"(do [expression] ...)\n\n",
						"evaluates an expression list, useful in loops"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Value res = new;

		for (integer i = 1; i < args.v.size(); i++)
			res = args.v[i].eval(ctx);
		return res;
	endfunction
endclass

class StmtIf extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "if");
	endfunction

	virtual function automatic string help();
		return {"(if {condition} {eval if true} [eval if false])\n\n",
						"checks if a condition is true (not equal 0) then evaluates and returns\n",
						"an appropriate expression"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Number cond;

		if ($cast(cond, args.v[1].eval(ctx)) && cond.v != 0)
			return args.v[2].eval(ctx);
		if (args.v.size() >= 4)
			return args.v[3].eval(ctx);
		return cond;
	endfunction
endclass

class StmtAnd extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "and");
	endfunction

	virtual function automatic string help();
		return {"(and {expression} {expression})\n\n",
						"returns the first expression if its false, ",
						"otherwise returns the value of the second one"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Number cond;

		if ($cast(cond, args.v[1].eval(ctx)) && cond.v != 0)
			if ($cast(cond, args.v[2].eval(ctx)))
				return cond;
		return cond;
	endfunction
endclass

class StmtOr extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "or");
	endfunction

	virtual function automatic string help();
		return {"(or {expression} {expression})\n\n",
						"returns the first expression if its true, ",
						"otherwise returns the value of the second one"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Number cond;

		if ($cast(cond, args.v[1].eval(ctx)) && cond.v != 0)
			return cond;
		if ($cast(cond, args.v[2].eval(ctx)))
			return cond;
		return cond;
	endfunction
endclass

class StmtFor extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "for");
	endfunction

	virtual function automatic string help();
		return {"(for {condition} {expression})\n\n",
						"repeats evaluation of an expression as long as ",
						"the condition is true"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Number cond;
		Value res = new;

		while ($cast(cond, args.v[1].eval(ctx)) && cond.v != 0)
			res = args.v[2].eval(ctx);
		return res;
	endfunction
endclass

class StmtRead extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "read");
	endfunction

	virtual function automatic string help();
		return {"(read)\n\n",
						"parses user input as an s-expression and returns it"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Value v = new;
		Value r;

		r = v.parse(STDIN);
		if (r != null)
			return r.eval(ctx);
		return v;
	endfunction
endclass

class StmtWrite extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "write");
	endfunction

	virtual function automatic string help();
		return {"(write [expression] ...)\n\n",
						"prints values"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		for (integer i = 1; i < args.v.size(); i++)
			$display("%s ", args.v[i].eval(ctx).format());
		return this;
	endfunction
endclass

class StmtList extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "list");
	endfunction

	virtual function automatic string help();
		return {"(list [expression] ...)\n\n",
						"creates a list of values"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		List l = new;

		for (integer i = 1; i < args.v.size(); i++)
			l.v.push_back(args.v[i].eval(ctx));
		return l;
	endfunction
endclass

class StmtAccess extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "access");
		create(ctx, "@");
	endfunction

	virtual function automatic string help();
		return {"(access {list} {index} [value]) ",
						"or (@ {list} {index} [value])\n\n",
						"returns a list element under a given index ",
						"if value argument is not given,\n",
						"otherwise stores the value in the list"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		List l;
		Number n;
		integer idx;

		$cast(l, args.v[1].eval(ctx));
		$cast(n, args.v[2].eval(ctx));

		idx = n.v;

		if (args.v.size() >= 4)
			l.v[idx] = args.v[3].eval(ctx);
		return l.v[idx];
	endfunction
endclass

class StmtAppend extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "append");
	endfunction

	virtual function automatic string help();
		return {"(append {list} {value})\n\n",
						"appends a value to the end of the list"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		List l;

		$cast(l, args.v[1].eval(ctx));

		l.v.push_back(args.v[2].eval(ctx));
		return l;
	endfunction
endclass

class StmtLen extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "len");
		create(ctx, "#");
	endfunction

	virtual function automatic string help();
		return {"(len {list}) or (# {list})\n\n",
						"returns length of the list"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		List l;
		Number n;

		$cast(l, args.v[1].eval(ctx));

		n = new(l.v.size());

		return n;
	endfunction
endclass

class StmtHelp extends Stmt;
	function automatic new(Context ctx);
		create(ctx, "help");
	endfunction

	virtual function automatic string help();
		return {"(help {object})\n\n",
						"prints help about objects, for build-in functions there is ",
						"also syntax info displayed,\n",
						"the following convention is used:\n\n",
						"  string   -- entering this exact string is required\n",
						"  {string} -- required argument\n",
						"  [string] -- optional argument\n",
						"  ...      -- preceeding argument can be repeated"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Value v = args.v[1].eval(ctx);

		if (v)
			$display("help: %s", v.help());

		return v;
	endfunction
endclass

class StmtMath extends Stmt;
	virtual function automatic integer op(integer a, b);
		return 0;
	endfunction

	virtual function automatic string help();
		return {"(", this.name, " {expression} ...)\n\n",
						"evaluates ", this.name, " operation"};
	endfunction

	virtual function automatic Value call(Context ctx, List args);
		Number first, res = new;
		Number n;

		$cast(first, args.v[1].eval(ctx));
		res.v = first.v;
		for (integer i = 2; i < args.v.size(); i++) begin
			$cast(n, args.v[i].eval(ctx));
			res.v = op(res.v, n.v);
		end
		return res;
	endfunction
endclass

class StmtAdd extends StmtMath;
	function automatic new(Context ctx);
		create(ctx, "+");
	endfunction

	virtual function automatic integer op(integer a, b);
		return a + b;
	endfunction
endclass

class StmtSub extends StmtMath;
	function automatic new(Context ctx);
		create(ctx, "-");
	endfunction

	virtual function automatic integer op(integer a, b);
		return a - b;
	endfunction
endclass

class StmtRem extends StmtMath;
	function automatic new(Context ctx);
		create(ctx, "%");
	endfunction

	virtual function automatic integer op(integer a, b);
		return a % b;
	endfunction
endclass

class StmtShiftLeft extends StmtMath;
	function automatic new(Context ctx);
		create(ctx, "<<");
	endfunction

	virtual function automatic integer op(integer a, b);
		return a << b;
	endfunction
endclass

class StmtShiftRight extends StmtMath;
	function automatic new(Context ctx);
		create(ctx, ">>");
	endfunction

	virtual function automatic integer op(integer a, b);
		return a >> b;
	endfunction
endclass

class StmtLess extends StmtMath;
	function automatic new(Context ctx);
		create(ctx, "<");
	endfunction

	virtual function automatic integer op(integer a, b);
		if (a < b)
			return 1;
		return 0;
	endfunction
endclass

function automatic bit isspace(integer ch);
	return ch == "\n" || ch == "\r" || ch == "\t" || ch == " ";
endfunction

function automatic bit ispunct(integer ch);
	return ch[7:0] == "(" || ch[7:0] == ")" || ch[7:0] == ";";
endfunction

function automatic string itoa(integer ch);
	return string'(ch[7:0]);
endfunction

function automatic Value Value::parse(integer f);
	integer n;
	integer ch, i;

	forever begin
		forever begin
			ch = $fgetc(f);
			if (!isspace(ch))
				break;
		end
		if (ch == ";") begin
			forever begin
				ch = $fgetc(f);
				if (ch == 10)
					break;
			end
		end else if (ch < 0)
		 	return null;
		else break;
	end
	if (ch == "\"") begin
		String s = new;
		for (i = 0; (ch = $fgetc(f)) != "\"" && ch > 0; i++)
			s.v = {s.v, itoa(ch)};
		return s;
	end else if (ch == "(") begin
		List l = new;
		Value elem;
		for (i = 0; (elem = parse(f)) != null; i++)
			l.v.push_back(elem);
		return l;
	end else if (ch == ")") begin
		return null;
	end else begin
		Symbol s = new;
		$ungetc(ch, f);
		for (i = 0; (ch = $fgetc(f)) != 0 && !isspace(ch) && !ispunct(ch); i++)
			s.v = {s.v, itoa(ch)};
		$ungetc(ch, f);
		if (s.v != "+" && s.v != "-" && $sscanf(s.v, "%d", n) > 0) begin
			Number num = new(n);
			return num;
		end
		return s;
	end
	$error("unexpected character %s", itoa(ch));
	return null;
endfunction

function automatic void main();
	Context ctx = new;
	Value v = new;
	string fname, prompt;
	integer stdlib, source;

	StmtImport     _0  = new(ctx);
	StmtDef        _1  = new(ctx);
	StmtSet        _2  = new(ctx);
	StmtFn         _3  = new(ctx);
	StmtIf         _4  = new(ctx);
	StmtAnd        _5  = new(ctx);
	StmtOr         _6  = new(ctx);
	StmtDo         _7  = new(ctx);
	StmtFor        _8  = new(ctx);
	StmtRead       _9  = new(ctx);
	StmtWrite      _10 = new(ctx);
	StmtList       _11 = new(ctx);
	StmtAccess     _12 = new(ctx);
	StmtLen        _13 = new(ctx);
	StmtHelp       _14 = new(ctx);
	StmtAppend     _15 = new(ctx);
	StmtAdd        _16 = new(ctx);
	StmtSub        _17 = new(ctx);
	StmtRem        _18 = new(ctx);
	StmtShiftLeft  _19 = new(ctx);
	StmtShiftRight _20 = new(ctx);
	StmtLess       _21 = new(ctx);

	STDIN = $fopen("/dev/stdin", "r");

	stdlib = $fopen("stdlib.vl", "r");
	run(ctx, stdlib, "");
	$fclose(stdlib);

	if ($value$plusargs("run=%s", fname)) begin
		prompt = "";
	end else begin
		fname = "/dev/stdin";
		prompt = "> ";
	end

	source = $fopen(fname, "r");
	run(ctx, source, prompt);
endfunction

module t();
	initial begin
		main();
		$finish;
	end
endmodule
