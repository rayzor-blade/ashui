package ashui.core.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** Where a UI shader reads each display-list field it uses. **/
class Inputs {
	/** The `primitive` fields, in record order; `UiFramework` declares them the same. **/
	public static final FIELDS = [
		"bounds", "cornerRadius", "color", "color2", "border", "borderColor", "shadow", "shadowColor", "clipBounds", "clipRadius", "gradient",
		"typeInfo", "cornerShape"
	];

	/**
		The vertex attributes of `shader`, a `UiShader` class: for each record
		field it still reads after dead-code elimination, its byte offset in
		the record and its location.
	**/
	public static macro function of(shader:Expr):Expr {
		var type = Context.getType(haxe.macro.ExprTools.toString(shader));
		var statics = switch type {
			case TInst(c, _): [for (f in c.get().statics.get()) f.name];
			default: Context.error("expected a UiShader class", shader.pos);
		}
		var attributes = [];
		for (i => name in FIELDS) {
			var input = 'INPUT_$name';
			if (statics.indexOf(input) >= 0)
				attributes.push(macro {offset: $v{i * 16}, location: $shader.$input});
		}
		return macro $a{attributes};
	}
}
