import ashui.components.code.CodeZones;

/** The arithmetic of rows with zones between them agrees with adding it up one row at a time. **/
class CodeZonesCheck {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static var seed = 7;

	static function next(n:Int):Int {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return (seed >> 8) % n;
	}

	static function main():Void {
		var z = new CodeZones();
		check("with no zones a row is where its number puts it", z.yOf(10, 20) == 200 && z.total() == 0 && z.rowAt(205, 20, 100) == 10);
		z.set([{row: 2, height: 50}]);
		check("a zone pushes the rows after it down, not the one it follows", z.yOf(2, 20) == 40 && z.yOf(3, 20) == 110, [z.yOf(2, 20), z.yOf(3, 20)]);
		check("the height at a row below the zone is in the row above", z.rowAt(80, 20, 10) == 2 && z.inZone(80, 20, 10) && !z.inZone(50, 20, 10) && !z.inZone(110, 20, 10));
		check("a row's fraction is clamped at its bottom inside a zone", z.fraction(80, 20, 10) == 3.0 || z.fraction(80, 20, 10) == 3, z.fraction(80, 20, 10));
		z.set([{row: 4, height: 10}, {row: 4, height: 15}, {row: 1, height: 5}, {row: -1, height: 99}, {row: 6, height: 0}]);
		check("zones on one row add, a row below 0 or no height is left out", z.count == 2 && z.total() == 30 && z.after(4) == 25 && z.after(1) == 5, [z.count, z.total()]);
		z.set([{row: 0, height: 24, before: true}, {row: 1, height: 16, before: true}, {row: 0, height: 8}]);
		check("space above the first row moves its text and is not a character", z.yOf(0, 20) == 24 && z.inZone(12, 20, 3) && !z.inZone(30, 20, 3));
		check("above and below zones share the same gap without overlap", z.yOf(1, 20) == 68 && z.total() == 48 && z.after(0) == 24);
		check("the leading action row maps to the document start in the minimap", z.rowAt(12, 20, 3) == 0 && z.fraction(12, 20, 3) == 0);
		var wrong:Null<String> = null;
		for (round in 0...400) {
			var n = 1 + next(60), lh = 10 + next(20), zones = [for (_ in 0...next(8)) {row: next(n + 2) - 1, height: next(40) * 1.0}];
			z.set(zones);
			var tops = [], at = 0.0;
			for (r in 0...n) {
				tops.push(at);
				var extra = 0.0;
				for (zone in zones)
					if (zone.row == r && zone.height > 0)
						extra += zone.height;
				at += lh + extra;
			}
			for (r in 0...n)
				if (Math.abs(z.yOf(r, lh) - tops[r]) > 1e-9) {
					wrong = 'round $round row $r: ${z.yOf(r, lh)} against ${tops[r]}';
					break;
				}
			for (probe in 0...40) {
				var y = next(Std.int(at) + 30) - 10 + 0.5, expect = 0;
				for (r in 0...n)
					if (tops[r] <= y)
						expect = r;
				if (wrong == null && z.rowAt(y, lh, n) != expect)
					wrong = 'round $round y $y: ${z.rowAt(y, lh, n)} against $expect';
			}
			var all = 0.0;
			for (zone in zones)
				if (zone.row >= 0 && zone.height > 0)
					all += zone.height;
			if (wrong == null && Math.abs(z.total() - all) > 1e-9)
				wrong = 'round $round total';
			if (wrong != null)
				break;
		}
		check("four hundred random layouts agree with a sum made row by row, in tops and in the row at a height", wrong == null, wrong);
		Sys.println('$checks checks: ALL PASSED');
	}
}
