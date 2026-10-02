package ashui.reactive;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

/** Picks the native signal or computed class for a value type. **/
class Kinds {
	/**
		The class-name suffix for values of `type`: `I32`, `F32`, `F64`, `Bool`,
		`String`, `Value`, `Array` or `Dynamic`. An enum abstract over a
		primitive takes that primitive's kind.
	**/
	public static function of(type:Type):String {
		switch Context.follow(type) {
			case TInst(_.get() => {pack: [], name: "String"}, _):
				return "String";
			case TInst(_.get() => {pack: [], name: "Array"}, _):
				return "Array";
			case TInst(_, _) if (Context.unify(type, Context.getType("ashui.types.IValue"))):
				return "Value";
			case _:
		}
		return switch Context.followWithAbstracts(type) {
			case TAbstract(_.get() => {pack: [], name: "Int"}, _): "I32";
			case TAbstract(_.get() => {pack: [], name: "Single"}, _): "F32";
			case TAbstract(_.get() => {pack: [], name: "Float"}, _): "F64";
			case TAbstract(_.get() => {pack: [], name: "Bool"}, _): "Bool";
			case _: "Dynamic";
		}
	}

	/** `new ashui.reactive.<prefix><kind>(arg)`, typed as `<prefix><type>`. **/
	public static function build(prefix:String, type:Type, arg:Expr):Expr {
		var ct = Context.toComplexType(type);
		var pack = ["ashui", "reactive"];
		var path:TypePath = switch of(type) {
			case "Array" if (prefix == "Signal"):
				var elem = switch Context.follow(type) {
					case TInst(_, [e]): Context.toComplexType(e);
					case _: macro :Dynamic;
				}
				{pack: pack, name: "SignalArray", params: [TPType(elem)]};
			case "Array" | "Dynamic":
				{pack: pack, name: prefix + "Dynamic", params: [TPType(ct)]};
			case "Value":
				{pack: pack, name: prefix + "Value", params: [TPType(ct)]};
			case kind:
				{pack: pack, name: prefix + kind};
		}
		var target:ComplexType = TPath({pack: pack, name: prefix, params: [TPType(ct)]});
		return macro (cast new $path(cast $arg) : $target);
	}
}
#end
