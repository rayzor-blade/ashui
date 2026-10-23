package ashui.components.code;

/**
	Where the rows of an editor sit when elements, its zones, are placed between them. Every row has the one height of a line;
	a zone adds its own below the row it follows, and pushes every later row down by it. The zones are kept sorted by row with
	the heights of those before each summed, so the top of a row and the row at a height are a binary search each, and a
	document of tens of thousands of lines with a few zones costs nothing it did not.
**/
class CodeZones {
	var at:Array<Int> = [];
	/** `sum[i]` is the height of the zones at `at[0]` to `at[i]`. **/
	var sum:Array<Float> = [];

	public function new() {}

	/** The zones: each a row it follows and a height. Zones on one row add up; a row below 0 follows nothing and is left out. **/
	public function set(zones:Array<{row:Int, height:Float}>):Void {
		var sorted = [for (z in zones) if (z.row >= 0 && z.height > 0) z];
		sorted.sort((a, b) -> a.row - b.row);
		at = [];
		sum = [];
		var total = 0.0;
		for (z in sorted) {
			total += z.height;
			if (at.length > 0 && at[at.length - 1] == z.row)
				sum[sum.length - 1] = total;
			else {
				at.push(z.row);
				sum.push(total);
			}
		}
	}

	public var count(get, never):Int;

	inline function get_count():Int
		return at.length;

	/** The height of every zone. **/
	public inline function total():Float
		return sum.length == 0 ? 0.0 : sum[sum.length - 1];

	/** The height of the zones after the rows before `row`. **/
	public function before(row:Int):Float {
		// The last zone row below `row`.
		var low = 0, high = at.length;
		while (low < high) {
			var middle = (low + high) >> 1;
			if (at[middle] < row)
				low = middle + 1;
			else
				high = middle;
		}
		return low == 0 ? 0.0 : sum[low - 1];
	}

	/** The height of the zones on `row`: what stands between it and the next row. **/
	public function after(row:Int):Float {
		var low = 0, high = at.length;
		while (low < high) {
			var middle = (low + high) >> 1;
			if (at[middle] < row)
				low = middle + 1;
			else
				high = middle;
		}
		return low < at.length && at[low] == row ? sum[low] - (low == 0 ? 0.0 : sum[low - 1]) : 0.0;
	}

	/** The distance from the text's top to the top of `row`, rows `lineHeight` high. **/
	public inline function yOf(row:Int, lineHeight:Float):Float
		return row * lineHeight + before(row);

	/** The last of `count` rows whose top is at or above `y`; 0 above the first. **/
	public function rowAt(y:Float, lineHeight:Float, count:Int):Int {
		if (count <= 0 || y <= 0)
			return 0;
		var low = 0, high = count - 1;
		while (low < high) {
			var middle = (low + high + 1) >> 1;
			if (yOf(middle, lineHeight) <= y)
				low = middle;
			else
				high = middle - 1;
		}
		return low;
	}

	/** Whether `y` is in the height of a zone, between a row and the next. **/
	public function inZone(y:Float, lineHeight:Float, count:Int):Bool {
		if (at.length == 0 || y < 0)
			return false;
		var row = rowAt(y, lineHeight, count);
		return y >= yOf(row, lineHeight) + lineHeight && after(row) > 0;
	}

	/** `y` as a row and the part of the way through it, so a position in a zone is its row's bottom. **/
	public function fraction(y:Float, lineHeight:Float, count:Int):Float {
		var row = rowAt(y, lineHeight, count), into = y - yOf(row, lineHeight);
		return row + Math.max(0, Math.min(1, into / Math.max(1, lineHeight)));
	}
}
