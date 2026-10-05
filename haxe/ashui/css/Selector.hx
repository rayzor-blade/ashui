package ashui.css;

/**
	How two compounds of a selector relate: `a b` any descendant, `a > b` a
	child, `a + b` the next sibling, `a ~ b` any later sibling.
**/
enum Combinator {
	Descendant;
	Child;
	NextSibling;
	LaterSibling;
}

/** An `an+b` pattern, as `:nth-child()` takes: `odd` is 2n+1, `3` is 0n+3. **/
typedef Nth = {
	final a:Int;
	final b:Int;
}

/** A pseudo-class of a compound selector. **/
enum Pseudo {
	/** An element state: `hover`, `active`, `focus`, `focus-visible`, `focus-within`, `disabled`, `enabled`, `checked`. **/
	State(name:String);
	Root;
	Empty;
	FirstChild;
	LastChild;
	OnlyChild;
	NthChild(nth:Nth);
	NthLastChild(nth:Nth);
	FirstOfType;
	LastOfType;
	OnlyOfType;
	NthOfType(nth:Nth);
	NthLastOfType(nth:Nth);
	/** Matches when none of the selectors does. **/
	Not(selectors:Array<Selector>);
	/** Matches when any of the selectors does. **/
	Is(selectors:Array<Selector>);
	/** As `Is`, adding nothing to the specificity. **/
	Where(selectors:Array<Selector>);
	/** Matches when an element relative to this one matches: `:has(.icon)`, `:has(> img)`. **/
	Has(selectors:Array<Selector>);
}

/**
	One compound selector: an element type or `*`, then any id, classes and
	pseudo-classes it must have, all of them; `button.primary:hover`.
**/
class Compound {
	/** The element type, or null for any. **/
	public var type:Null<String> = null;

	public var id:Null<String> = null;
	public final classes:Array<String> = [];

	/** Attribute tests: `[name]`, or `[name op "value"]` with op one of `=`, `~=`, `|=`, `^=`, `$=`, `*=`. **/
	public final attributes:Array<{name:String, op:Null<String>, value:Null<String>}> = [];
	public final pseudos:Array<Pseudo> = [];

	/** A pseudo-element, `placeholder` for `::placeholder`, or null. **/
	public var pseudoElement:Null<String> = null;

	public function new() {}

	/** A compound made of what was parsed already: what `CompiledCss` builds at run time. **/
	public static function of(type:Null<String>, id:Null<String>, classes:Array<String>, attributes:Array<{name:String, op:Null<String>, value:Null<String>}>,
			pseudos:Array<Pseudo>, pseudoElement:Null<String>):Compound {
		var c = new Compound();
		c.type = type;
		c.id = id;
		for (x in classes)
			c.classes.push(x);
		for (x in attributes)
			c.attributes.push(x);
		for (x in pseudos)
			c.pseudos.push(x);
		c.pseudoElement = pseudoElement;
		return c;
	}

	public function toString():String {
		var out = type == null ? "" : type;
		if (id != null)
			out += '#$id';
		for (c in classes)
			out += '.$c';
		for (a in attributes)
			out += a.op == null ? '[${a.name}]' : '[${a.name}${a.op}"${a.value}"]';
		for (p in pseudos)
			out += pseudoString(p);
		if (pseudoElement != null)
			out += '::$pseudoElement';
		return out == "" ? "*" : out;
	}

	static function pseudoString(p:Pseudo):String {
		inline function nth(n:Nth):String
			return n.a == 0 ? '${n.b}' : '${n.a}n${n.b < 0 ? "" : "+"}${n.b}';
		inline function list(s:Array<Selector>):String
			return [for (x in s) x.toString()].join(", ");
		return switch p {
			case State(name): ':$name';
			case Root: ":root";
			case Empty: ":empty";
			case FirstChild: ":first-child";
			case LastChild: ":last-child";
			case OnlyChild: ":only-child";
			case NthChild(n): ':nth-child(${nth(n)})';
			case NthLastChild(n): ':nth-last-child(${nth(n)})';
			case FirstOfType: ":first-of-type";
			case LastOfType: ":last-of-type";
			case OnlyOfType: ":only-of-type";
			case NthOfType(n): ':nth-of-type(${nth(n)})';
			case NthLastOfType(n): ':nth-last-of-type(${nth(n)})';
			case Not(s): ':not(${list(s)})';
			case Is(s): ':is(${list(s)})';
			case Where(s): ':where(${list(s)})';
			case Has(s): ':has(${list(s)})';
		}
	}
}

/**
	A complex selector: compounds joined by combinators, read right to left
	when matching; `.card > .title:hover`. `combinators[i]` joins
	`compounds[i]` to `compounds[i + 1]`. In a `:has()` argument the first
	combinator, if any, relates the subject to the element `:has` is on,
	and `leading` holds it.
**/
class Selector {
	/** The states a `State` pseudo-class may name. **/
	public static final STATES = [
		"hover", "active", "focus", "focus-visible", "focus-within", "disabled", "enabled", "checked", "indeterminate", "placeholder-shown", "valid", "invalid",
		"user-valid", "user-invalid", "required", "optional"
	];

	/** The states a form control sets (see `Interaction.formState`). **/
	public static final FORM_STATES = ["placeholder-shown", "valid", "invalid", "user-valid", "user-invalid", "required", "optional"];

	public final compounds:Array<Compound>;
	public final combinators:Array<Combinator>;

	/** A `:has()` argument's combinator before its first compound; null elsewhere. **/
	public final leading:Null<Combinator>;

	public function new(compounds:Array<Compound>, combinators:Array<Combinator>, ?leading:Combinator) {
		this.compounds = compounds;
		this.combinators = combinators;
		this.leading = leading;
	}

	/** The compound the selector applies its declarations to: its last. **/
	public var subject(get, never):Compound;

	inline function get_subject():Compound
		return compounds[compounds.length - 1];

	/**
		CSS's specificity as one number: ids × 10⁶, then classes, attributes
		and pseudo-classes × 10³, then types and pseudo-elements. `:is`,
		`:not` and `:has` count their most specific argument; `:where` none.
	**/
	public function specificity():Int {
		var total = 0;
		for (c in compounds)
			total += compoundSpecificity(c);
		return total;
	}

	static function compoundSpecificity(c:Compound):Int {
		var n = 0;
		if (c.id != null)
			n += 1000000;
		n += 1000 * (c.classes.length + c.attributes.length);
		if (c.type != null)
			n += 1;
		if (c.pseudoElement != null)
			n += 1;
		for (p in c.pseudos)
			n += switch p {
				case Not(s) | Is(s) | Has(s): most(s);
				case Where(_): 0;
				case _: 1000;
			}
		return n;
	}

	static function most(selectors:Array<Selector>):Int {
		var best = 0;
		for (s in selectors)
			best = Std.int(Math.max(best, s.specificity()));
		return best;
	}

	public function toString():String {
		var out = leading == null ? "" : combinatorString(leading) + " ";
		for (i => c in compounds) {
			out += c.toString();
			if (i < combinators.length)
				out += switch combinators[i] {
					case Descendant: " ";
					case other: ' ${combinatorString(other)} ';
				}
		}
		return out;
	}

	static function combinatorString(c:Combinator):String
		return switch c {
			case Descendant: "";
			case Child: ">";
			case NextSibling: "+";
			case LaterSibling: "~";
		}
}
