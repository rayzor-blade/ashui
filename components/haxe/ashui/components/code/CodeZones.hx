package ashui.components.code;

/**
	Maps text rows to vertical positions when view zones add height between lines.

	Rows retain a fixed line height; each zone pushes subsequent rows down.
	Sorted zone positions and cumulative heights allow binary searches
	between rows and Y coordinates without allocating data for every line.
**/
class CodeZones {
	var at:Array<Int> = [];
	/** Cumulative zone heights through each sorted row position. **/
	var sum:Array<Float> = [];

	public function new() {}

	/** Replaces zone row/height data. Combines zones on the same row and ignores negative row indices. **/
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

	/** Returns total added zone height. **/
	public inline function total():Float
		return sum.length == 0 ? 0.0 : sum[sum.length - 1];

	/** Returns zone height added before a row. **/
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

	/** Returns zone height between a row and the next row. **/
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

	/** Returns the row top, including preceding zones, for the given line height. **/
	public inline function yOf(row:Int, lineHeight:Float):Float
		return row * lineHeight + before(row);

	/** Returns the last row starting at or above `y`, or zero above the first row. **/
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

	/** Returns whether `y` lies inside a zone between rows. **/
	public function inZone(y:Float, lineHeight:Float, count:Int):Bool {
		if (at.length == 0 || y < 0)
			return false;
		var row = rowAt(y, lineHeight, count);
		return y >= yOf(row, lineHeight) + lineHeight && after(row) > 0;
	}

	/** Converts `y` to a fractional row position. Positions inside a zone map to the preceding row bottom. **/
	public function fraction(y:Float, lineHeight:Float, count:Int):Float {
		var row = rowAt(y, lineHeight, count), into = y - yOf(row, lineHeight);
		return row + Math.max(0, Math.min(1, into / Math.max(1, lineHeight)));
	}
}
