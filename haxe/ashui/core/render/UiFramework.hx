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
		"fadeBounds", "fade", "shapeFrame", "shapeRest", "shape", "notchCorners", "notchTop", "notchBottom"
	];

	/**
		Applies this extension to every `UiShader`; called from a `--macro`.
		Defines `ashui_gpu`, which marks a build that draws: code outside the
		renderer, a canvas's paint, types its GPU parts by it.
	**/
	public static function register() {
		haxe.macro.Compiler.define("ashui_gpu");
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
			// Texels in reading order, `ROW_TEXELS` to a row of the texture.
			function __texel(t : Int) : Vec4 {
				return records.fetch(ivec2(t % $v{ashui.layout.RecordLayout.ROW_TEXELS}, t / $v{ashui.layout.RecordLayout.ROW_TEXELS}));
			}
			// A record is `RECORD_ROWS` texels.
			function __field(row : Int) : Vec4 {
				return __texel(recordIndex * $v{ashui.layout.RecordLayout.RECORD_ROWS} + row);
			}
			// How much of the point `q` the polygon of `count` points from texel `first`, two to a texel, covers,
			// by the nonzero rule, CSS's default; `aa` is half a pixel. A point at 1e30 or past it parts two rings.
			// The winding is also taken at four points around `q`: all four inside is covered whatever edge is
			// near, so the crossings inside a self-crossing polygon leave no seam, and only where they differ, at
			// the outline, does the distance to the nearest edge smooth it.
			function __polygonCoverage(q : Vec2, first : Int, count : Int, aa : Float) : Float {
				var d = 1e20;
				var s = aa * 0.7;
				var w0 = 0;
				var w1 = 0;
				var w2 = 0;
				var w3 = 0;
				var w4 = 0;
				var prev = vec2(0., 0.);
				var i = 0;
				while (i < count) {
					var t = __texel(first + i / 2);
					var v = t.xy;
					if (i % 2 == 1)
						v = t.zw;
					if (i > 0 && v.x < 1e29 && prev.x < 1e29) {
						var e = prev - v;
						var w = q - v;
						var b = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-12), 0., 1.);
						d = min(d, dot(b, b));
						w0 += __crossing(prev, v, q);
						w1 += __crossing(prev, v, q + vec2(s, s));
						w2 += __crossing(prev, v, q + vec2(-s, s));
						w3 += __crossing(prev, v, q + vec2(s, -s));
						w4 += __crossing(prev, v, q + vec2(-s, -s));
					}
					prev = v;
					i++;
				}
				var inside = 0;
				if (w1 != 0)
					inside++;
				if (w2 != 0)
					inside++;
				if (w3 != 0)
					inside++;
				if (w4 != 0)
					inside++;
				var dist = sqrt(d);
				if (w0 != 0)
					dist = -dist;
				var cover = 1. - smoothstep(-aa, aa, dist);
				if (inside == 4)
					cover = 1.;
				if (inside == 0)
					cover = 0.;
				return cover;
			}
			// What the edge from `a` to `b` adds to the winding around `q`: 1 crossing `q`'s row upward with `q`
			// to its left, -1 downward with `q` to its right.
			function __crossing(a : Vec2, b : Vec2, q : Vec2) : Int {
				var side = (b.x - a.x) * (q.y - a.y) - (q.x - a.x) * (b.y - a.y);
				var w = 0;
				if (a.y <= q.y) {
					if (b.y > q.y && side > 0.)
						w = 1;
				} else if (b.y <= q.y && side < 0.)
					w = -1;
				return w;
			}
			/**
				How much of the point `p`, on screen, the record's `clip-path`
				leaves. Its frame takes `p` into the element's coordinates; its
				shape is an ellipse, a rounded rect or a polygon.
			**/
			/**
				For a shader a canvas paints with, drawn with the canvas's
				record as its instance: the canvas's clips, edge fades,
				clip-path and opacity at `p`, a screen position, as boxes and
				images are clipped.
			**/
			function canvasClip(p : Vec2) : Float {
				var b = primitive.bounds;
				var m = primitive.affine;
				var d = p - b.xy;
				var local = vec2(m.w * d.x - m.z * d.y, m.x * d.y - m.y * d.x) / (m.x * m.w - m.z * m.y);
				var aa = halfPixel(local);
				return clipCoverage(p, primitive.clipBounds, primitive.clipRadius, primitive.typeInfo.z, primitive.typeInfo.w)
					* localClipCoverage(local, primitive.shadow, primitive.shadowColor, primitive.typeInfo.z, primitive.typeInfo.w, aa)
					* fadeCoverage(p, primitive.fadeBounds, primitive.fade)
					* shapeCoverage(p)
					* primitive.color2.a;
			}

			function shapeCoverage(p : Vec2) : Float {
				var frame = primitive.shapeFrame;
				var rest = primitive.shapeRest;
				var shape = primitive.shape;
				// The element's coordinates and their pixel size, before any branch, where derivatives are defined.
				var q = vec2(frame.x * p.x + frame.z * p.y + rest.x, frame.y * p.x + frame.w * p.y + rest.y);
				var aa = halfPixel(q);
				var alpha = 1.;
				if (rest.z > 2.5) {
					alpha = __polygonCoverage(q, int(shape.x), int(shape.y), aa);
				} else if (rest.z > 1.5) {
					alpha = 1. - smoothstep(-aa, aa, sdShapedRect(q, shape.xy, shape.zw, vec4(rest.w, rest.w, rest.w, rest.w), vec4(1., 1., 1., 1.)));
				} else if (rest.z > 0.5) {
					// An ellipse's distance, to first order: its implicit function over its gradient.
					var r = max(shape.zw, vec2(0.0001, 0.0001));
					var u = (q - shape.xy) / r;
					var lu = length(u);
					alpha = 1. - smoothstep(-aa, aa, (lu - 1.) * lu / max(length(u / r), 0.0001));
				}
				return alpha;
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

	/**
		The records alone in group 1, a layer's shadow alone in group 2, and
		a canvas's own data in group 3, with the image atlas its images are
		drawn from: each texture and HXSL's sampler for it after, so bindings
		made in order match.
	**/
	override function group(name:String):Null<Int> {
		return switch name {
			case "records": 1;
			case "shadow": 2;
			case "canvas" | "canvasImages": 3;
			case _: null;
		}
	}
}
#end
