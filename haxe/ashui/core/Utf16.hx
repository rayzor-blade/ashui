package ashui.core;

/**
	Converts between the UTF-16 offsets that the native text layout reports and
	the indices of a Haxe `String`.

	A HashLink or JavaScript string is indexed by UTF-16 units, so the two
	agree. A string on Haxe's eval target or on Rayzor is indexed by code
	points: a character outside the Basic Multilingual Plane, such as an emoji,
	is one index but two UTF-16 units, so every offset after it is one higher
	than its index.
**/
class Utf16 {
	/** The number of UTF-16 units in `s`; its length where strings are indexed by them. **/
	public static function length(s:String):Int {
		#if (rayzor || eval)
		var n = s.length;
		for (i in 0...s.length)
			if (StringTools.fastCodeAt(s, i) > 0xFFFF)
				n++;
		return n;
		#else
		return s.length;
		#end
	}

	/**
		The string index of each UTF-16 offset of `s`, from 0 to `length(s)`,
		or null where offsets and indices are the same. An offset inside a
		character, the second half of a surrogate pair, has index -1.
	**/
	public static function indices(s:String):Null<Array<Int>> {
		#if (rayzor || eval)
		var wide = false;
		for (i in 0...s.length)
			if (StringTools.fastCodeAt(s, i) > 0xFFFF) {
				wide = true;
				break;
			}
		if (!wide)
			return null;
		var table = [];
		for (i in 0...s.length) {
			table.push(i);
			if (StringTools.fastCodeAt(s, i) > 0xFFFF)
				table.push(-1);
		}
		table.push(s.length);
		return table;
		#else
		return null;
		#end
	}

	/** The string index at UTF-16 offset `unit`, by a table from `indices`: -1 inside a character, past the end the end. **/
	public static inline function indexAt(table:Null<Array<Int>>, unit:Int):Int
		return table == null ? unit : unit < table.length ? table[unit] : table[table.length - 1];
}
