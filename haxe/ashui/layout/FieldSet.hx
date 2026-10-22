package ashui.layout;

/**
	A small set of property fields, as a node's own and stylesheet-set ones
	are: a sorted array, so a node holds no hash table of its own.
**/
class FieldSet {
	final keys:Array<Int> = [];

	public function new() {}

	/** The index of `key`, or `-(where it would go) - 1`. **/
	function find(key:Int):Int {
		var lo = 0, hi = keys.length - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1, k = keys[mid];
			if (k < key)
				lo = mid + 1;
			else if (k > key)
				hi = mid - 1;
			else
				return mid;
		}
		return -(lo + 1);
	}

	public inline function exists(key:Int):Bool
		return find(key) >= 0;

	/** Adds `key`; true when it was not there. **/
	public function add(key:Int):Bool {
		var i = find(key);
		if (i >= 0)
			return false;
		keys.insert(-i - 1, key);
		return true;
	}

	/** Takes `key` out; true when it was there. **/
	public function remove(key:Int):Bool {
		var i = find(key);
		if (i < 0)
			return false;
		keys.splice(i, 1);
		return true;
	}

	public var length(get, never):Int;

	inline function get_length():Int
		return keys.length;
}
