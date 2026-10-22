import ashui.layout.FieldSet;
import ashui.layout.FieldTable;

/** The sorted tables a node keeps its fields in behave as the hash maps they replace, over thousands of random writes and removals. **/
class FieldTables {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		var seed = 12345;
		function next(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		// Keys as fields are: mostly small, a few far away (the corner shape's and a transition's).
		function key():Int
			return switch next(10) {
				case 0: 1003;
				case 1: 2000;
				case _: next(120);
			}
		var set = new FieldSet(), oracle = new Map<Int, Bool>();
		var table = new FieldTable<String>(), values = new Map<Int, String>();
		var mismatch = null;
		for (step in 0...20000) {
			var k = key();
			switch next(3) {
				case 0:
					var fresh = set.add(k);
					if (fresh != !oracle.exists(k))
						mismatch = 'add $k said $fresh at step $step';
					oracle.set(k, true);
					var v = 'v$step';
					table.set(k, v);
					values.set(k, v);
				case 1:
					var removed = set.remove(k);
					if (removed != oracle.remove(k))
						mismatch = 'remove $k said $removed at step $step';
					if (table.remove(k) != values.remove(k))
						mismatch = 'table remove $k differed at step $step';
				case _:
					if (set.exists(k) != oracle.exists(k) || table.exists(k) != values.exists(k) || table.get(k) != values.get(k))
						mismatch = 'lookup of $k differed at step $step';
			}
			if (mismatch != null)
				break;
		}
		check("a set and a table follow a map through twenty thousand random steps", mismatch == null, mismatch);
		check("the set's size is the map's", set.length == Lambda.count(oracle), [set.length, Lambda.count(oracle)]);
		check("the table's size is the map's", table.length == Lambda.count(values), [table.length, Lambda.count(values)]);
		var inOrder = true;
		for (i in 1...table.length)
			if (table.keyAt(i - 1) >= table.keyAt(i))
				inOrder = false;
		check("the table's keys are in order, each once", inOrder);
		var same = true;
		for (i in 0...table.length)
			if (values.get(table.keyAt(i)) != table.valueAt(i))
				same = false;
		check("each key's value is the map's", same);
		Sys.println('$checks checks: ALL PASSED');
	}
}
