package ashui.canvaskit;

/** A rectangle in a `SpatialIndex`, and its place in drawing order: a later one is on top. **/
typedef Region = {id:String, x:Float, y:Float, width:Float, height:Float, order:Int};

/**
	Rectangles by id, found by point or by area without looking at all of
	them: the plane is cut into square cells `cellSize` across, and each
	rectangle is listed in every cell it touches. A point looks in one cell,
	an area in the cells it covers, so lookups stay fast however many
	rectangles there are, as long as most are not much larger than a cell.

	```haxe
	var index = new SpatialIndex(100);
	index.set("a", 10, 10, 50, 30);
	index.hitTest(20, 20); // "a"
	index.query(0, 0, 200, 200); // ["a"]
	```
**/
class SpatialIndex {
	public final cellSize:Float;

	final regions = new Map<String, Region>();
	final cells = new Map<String, Array<Region>>();
	var counter = 0;

	public function new(cellSize = 100.0)
		this.cellSize = cellSize;

	/** How many rectangles it holds. **/
	public var length(default, null) = 0;

	/** Puts `id` at this rectangle, on top of all before it; moves it there if it is in already. **/
	public function set(id:String, x:Float, y:Float, width:Float, height:Float):Void {
		remove(id);
		var r:Region = {id: id, x: x, y: y, width: width, height: height, order: counter++};
		regions.set(id, r);
		length++;
		forCells(x, y, x + width, y + height, key -> {
			var list = cells.get(key);
			if (list == null)
				cells.set(key, list = []);
			list.push(r);
		});
	}

	/** Takes `id` out; false when it was not in. **/
	public function remove(id:String):Bool {
		var r = regions.get(id);
		if (r == null)
			return false;
		regions.remove(id);
		length--;
		forCells(r.x, r.y, r.x + r.width, r.y + r.height, key -> {
			var list = cells.get(key);
			if (list != null) {
				list.remove(r);
				if (list.length == 0)
					cells.remove(key);
			}
		});
		return true;
	}

	/** Empties it. **/
	public function clear():Void {
		regions.clear();
		cells.clear();
		length = 0;
		counter = 0;
	}

	public function get(id:String):Null<Region>
		return regions.get(id);

	/** The topmost rectangle containing the point, or null. **/
	public function hitTest(x:Float, y:Float):Null<Region> {
		var list = cells.get(key(Math.floor(x / cellSize), Math.floor(y / cellSize)));
		if (list == null)
			return null;
		var best:Null<Region> = null;
		for (r in list)
			if (x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height && (best == null || r.order > best.order))
				best = r;
		return best;
	}

	/** The ids of every rectangle that overlaps the area, bottom first. **/
	public function query(x:Float, y:Float, width:Float, height:Float):Array<String> {
		var x1 = x + width, y1 = y + height;
		var seen = new Map<String, Bool>();
		var found:Array<Region> = [];
		forCells(x, y, x1, y1, k -> {
			var list = cells.get(k);
			if (list != null)
				for (r in list)
					if (!seen.exists(r.id) && r.x <= x1 && r.x + r.width >= x && r.y <= y1 && r.y + r.height >= y) {
						seen.set(r.id, true);
						found.push(r);
					}
		});
		found.sort((a, b) -> a.order - b.order);
		return [for (r in found) r.id];
	}

	function forCells(x0:Float, y0:Float, x1:Float, y1:Float, f:String->Void):Void {
		var i0 = Math.floor(x0 / cellSize), i1 = Math.floor(x1 / cellSize);
		var j0 = Math.floor(y0 / cellSize), j1 = Math.floor(y1 / cellSize);
		for (j in j0...j1 + 1)
			for (i in i0...i1 + 1)
				f(key(i, j));
	}

	static inline function key(i:Int, j:Int):String
		return '$i,$j';
}
