package ashui.debug;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/** Each `PropertyId`'s name, kebab-cased (`BorderColor` is `border-color`), read from the enum abstract when it compiles. **/
class PropertyNames {
	#if !macro
	static final names:Map<Int, String> = all();
	#end

	public static function name(id:Int):String {
		#if macro
		return 'property-$id';
		#else
		var n = names.get(id);
		return n == null ? 'property-$id' : n;
		#end
	}

	static macro function all():Expr {
		var entries:Array<Expr> = [];
		switch Context.getType("ashui.layout.PropertyId") {
			case TAbstract(a, _):
				for (f in a.get().impl.get().statics.get()) {
					if (!f.meta.has(":enum"))
						continue;
					var value = constant(f.expr());
					if (value == null)
						continue;
					var kebab = ~/([a-z0-9])([A-Z])/g.replace(f.name, "$1-$2").toLowerCase();
					entries.push(macro $v{value} => $v{kebab});
				}
			case _:
		}
		return macro $a{entries};
	}

	#if macro
	static function constant(e:Null<TypedExpr>):Null<Int> {
		if (e == null)
			return null;
		return switch e.expr {
			case TConst(TInt(v)): v;
			case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner): constant(inner);
			case _: null;
		}
	}
	#end
}
