package ashui.core.render;

#if macro
#if ashui_caribou
import caribou.hxsl.Ast;
import caribou.hxsl.Extension;
import caribou.hxsl.Extensions;
#else
import hlwgpu.hxsl.Ast;
import hlwgpu.hxsl.Extension;
import hlwgpu.hxsl.Extensions;
#end

/**
	ashui's extension of HXSL for `UiShader`s. Each draws one display-list
	record per instance, and reads it as `primitive`, field for field as
	`ashui.layout.DisplayList` packs it (see `RecordLayout`): `primitive.bounds` and the like.
	Globals go in a `frame` block, bound once per frame and shared by every
	UI shader.

	The records are rows of a float texture, `records`, which every
	platform can read from both stages, WebGL2 and GLES among them, where
	storage buffers are missing. Each `primitive.field` a shader reads
	becomes a load of that field's row of its instance's record, so a
	stage loads only the fields it uses and none passes between stages:
	one source for every platform.

	Registered from ashui's extraParams.hxml, or `--macro
	ashui.core.render.UiFramework.register()`.
**/
class UiFramework extends Extension {
	/** The record's fields, a row each, in `DisplayList`'s order. **/
	public static final FIELDS = [
		"bounds", "cornerRadius", "color", "color2", "border", "borderColor", "shadow", "shadowColor", "clipBounds", "clipRadius", "gradient",
		"typeInfo", "cornerShape", "via", "stops", "affine", "borderTop", "borderRight", "borderBottom", "borderLeft",
		"fadeBounds", "fade"
	];

	public static function register() {
		Extensions.register(new UiFramework(), "ashui.core.render.UiShader");
	}

	override function prelude():Null<haxe.macro.Expr> {
		var fields:Array<haxe.macro.Expr.Field> = [
			for (f in FIELDS) {name: f, kind: FVar(macro :Vec4), pos: haxe.macro.Context.currentPos()}
		];
		var struct = haxe.macro.Expr.ComplexType.TAnonymous(fields);
		return macro {
			@param var records : Sampler2D;
			@global var viewport : Vec2;
			// What the shader reads; each field read becomes a `__field` load, so it is never a vertex input.
			@input var primitive : $struct;
			var recordIndex : Int;
			function __init__vertex() {
				recordIndex = instanceID;
			}
			// A record's rows are `ROW_TEXELS` apart in reading order, `RECORD_ROWS` to a record.
			function __field(row : Int) : Vec4 {
				var t = recordIndex * $v{ashui.layout.RecordLayout.RECORD_ROWS} + row;
				return records.fetch(ivec2(t % $v{ashui.layout.RecordLayout.ROW_TEXELS}, t / $v{ashui.layout.RecordLayout.ROW_TEXELS}));
			}
		};
	}

	override function transform(shader:ShaderData):ShaderData {
		var field = Lambda.find(shader.funs, f -> f.ref.name == "__field");
		if (field == null)
			return shader;
		function rewrite(e:TExpr):TExpr {
			return switch e.e {
				// HXSL gives each field of a struct input a variable of its own, its parent the struct.
				case TVar(v) if (v.parent != null && v.parent.name == "primitive" && v.parent.kind == Input):
					var row = FIELDS.indexOf(v.name);
					{
						e: TCall({e: TVar(field.ref), t: field.ref.type, p: e.p}, [{e: TConst(CInt(row)), t: TInt, p: e.p}]),
						t: e.t,
						p: e.p
					};
				case _: Tools.map(e, rewrite);
			}
		}
		for (f in shader.funs)
			f.expr = rewrite(f.expr);
		return shader;
	}

	override function block(v:TVar, path:String):Null<String> {
		return v.kind == Global ? "frame" : null;
	}

	/** The records alone in group 1: their texture at binding 0, and HXSL's unused sampler for it after. **/
	override function group(name:String):Null<Int> {
		return name == "records" ? 1 : null;
	}
}
#end
