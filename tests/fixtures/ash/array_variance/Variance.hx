/**
	A switch whose branches build an `Array<Null<Float>>` and an `Array<Float>`
	is typed `Array<Null<Float>>`, so the `Array<Float>` branch is a cast
	HashLink rejects: "Can't cast hl.types.ArrayBytes_Float to
	hl.types.ArrayObj", thrown where the cast is.
**/
class Variance {
	static function maybe(v:Null<String>):Null<Float>
		return v == null ? null : Std.parseFloat(v);

	static function main() {
		var height = maybe(null);
		var box = switch "0 0 10 10" {
			case null: [0.0, 0.0, 1.0, height];
			case _: [0.0, 0.0, 10.0, 10.0];
		}
		Sys.println("not cast: " + box[3]);
	}
}
