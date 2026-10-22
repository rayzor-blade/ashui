package ashui.layout;

/**
	A small table from property field to value, as a node keeps for its
	tweens and bound properties: sorted arrays, so a node holds no hash table
	of its own. Tens of entries at most.
**/
class FieldTable<T> {
	final keys:Array<Int> = [];
	final values:Array<T> = [];

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

	/** The value at `key`, null if there is none. **/
	public function get(key:Int):Null<T> {
		var i = find(key);
		return i >= 0 ? values[i] : null;
	}

	public function set(key:Int, value:T):Void {
		var i = find(key);
		if (i >= 0) {
			values[i] = value;
			return;
		}
		keys.insert(-i - 1, key);
		values.insert(-i - 1, value);
	}

	/** Takes `key` out; true when it was there. **/
	public function remove(key:Int):Bool {
		var i = find(key);
		if (i < 0)
			return false;
		keys.splice(i, 1);
		values.splice(i, 1);
		return true;
	}

	public var length(get, never):Int;

	inline function get_length():Int
		return keys.length;

	/** The key at index `i`, in key order. **/
	public inline function keyAt(i:Int):Int
		return keys[i];

	/** The value at index `i`, in key order. **/
	public inline function valueAt(i:Int):T
		return values[i];
}
