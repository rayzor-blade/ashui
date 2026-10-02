package ashui.types;

/** A style value held natively: one immutable `blinc_value` per instance. **/
interface IValue {
	var ptr(default, null):hl.Abstract<"blinc_value">;
}
