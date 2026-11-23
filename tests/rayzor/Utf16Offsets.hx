import ashui.core.Utf16;

/**
	UTF-16 offsets and string indices on Rayzor, where a string is indexed by code points. Run by `run.sh`.
**/
class Utf16Offsets {
	static var failed = 0;
	static var passed = 0;

	static function check(name:String, ok:Bool):Void {
		if (ok) {
			passed++;
			Sys.println("ok   " + name);
		} else {
			failed++;
			Sys.println("FAIL " + name);
		}
	}

	static function same(a:Null<Array<Int>>, b:Array<Int>):Bool {
		if (a == null || a.length != b.length)
			return false;
		for (i in 0...b.length)
			if (a[i] != b[i])
				return false;
		return true;
	}

	static function main() {
		var emoji = "\u{1F30D}";
		check("a code point is one index", ("a" + emoji + "b").length == 3);
		check("it is two UTF-16 units", Utf16.length("a" + emoji + "b") == 4);
		check("text outside the plane has no table", Utf16.indices("abc") == null);
		var table = Utf16.indices("a" + emoji + "b");
		check("each offset has its index, none inside the pair", same(table, [0, 1, -1, 2, 3]));
		check("an offset after the emoji is the next index", Utf16.indexAt(table, 3) == 2);
		check("an offset inside the pair is -1", Utf16.indexAt(table, 2) == -1);
		check("an offset past the end is the end", Utf16.indexAt(table, 9) == 3);
		check("without a table an offset is its index", Utf16.indexAt(null, 5) == 5);
		check("two emoji", same(Utf16.indices(emoji + emoji), [0, -1, 1, -1, 2]) && Utf16.length(emoji + emoji) == 4);
		Sys.println(failed == 0 ? "ALL PASSED " + passed : "FAILED " + failed + " of " + (passed + failed));
	}
}
