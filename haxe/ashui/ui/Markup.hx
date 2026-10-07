package ashui.ui;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.ExprTools;
#end

/**
	Templates written as Haxe's own inline markup, with no `hxx('...')`
	around them: an element where an expression goes, as JSX writes one.

	    function card(title:String):Element
	        return <card><card-header><card-title>{title}</card-title></card-header></card>;

	    var list = <ul><for {item in items}><li>{item}</li></for></ul>;

	Each is what `hxx` makes of the same template, typed as the element it
	builds; the expressions inside keep their place in the file, so the
	compiler's completion and errors point into them. Turned on for a build
	by `--macro ashui.ui.Markup.enable()`; then every class but the
	standard library's has its markup lowered.
**/
class Markup {
	#if macro
	static var enabled = false;

	/** Packages whose classes hold no templates: the standard library and the compiler's own. **/
	static final SKIPPED = ["haxe", "sys", "hl", "cpp", "js", "jvm", "eval", "neko", "php", "python", "cs", "java", "lua", "flash", "tink"];

	/** Macros that take inline markup as it is written: `hxx(<div/>)`, `SvgDocument.of(<svg/>)`, `SvgDocument.embed`. **/
	static final READERS = ["hxx", "of", "embed"];

	static function readsMarkup(callee:Expr):Bool {
		return switch callee.expr {
			case EConst(CIdent(name)) | EField(_, name): READERS.indexOf(name) >= 0;
			case _: false;
		}
	}

	static function isMarkup(e:Expr):Bool {
		return switch e.expr {
			case EMeta({name: ":markup"}, _): true;
			case _: false;
		}
	}

	/** Lowers inline markup in every class the build types from here on. **/
	public static function enable():Void {
		if (enabled)
			return;
		enabled = true;
		Compiler.addGlobalMetadata("", "@:build(ashui.ui.Markup.build())", true, true, false);
	}

	/** The class's fields with each inline markup expression made the `hxx` of it; null when it has none, so the class is left alone. **/
	public static function build():Null<Array<Field>> {
		var cls = Context.getLocalClass();
		if (cls == null)
			return null;
		var c = cls.get();
		if (c.isExtern || (c.pack.length > 0 && SKIPPED.indexOf(c.pack[0]) >= 0))
			return null;
		var fields = Context.getBuildFields();
		var found = false;
		function lower(e:Expr):Expr {
			return switch e.expr {
				case EMeta({name: ":markup"}, _):
					found = true;
					macro @:pos(e.pos) ashui.ui.Hxx.hxx($e);
				// A macro that reads markup itself, as hxx and SvgDocument.of do, is handed it as written.
				case ECall(callee, args) if (readsMarkup(callee)):
					{expr: ECall(callee, [for (a in args) isMarkup(a) ? a : lower(a)]), pos: e.pos};
				case _: e.map(lower);
			}
		}
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null):
					fn.expr = lower(fn.expr);
				case FVar(t, e) if (e != null):
					f.kind = FVar(t, lower(e));
				case FProp(g, s, t, e) if (e != null):
					f.kind = FProp(g, s, t, lower(e));
				case _:
			}
		return found ? fields : null;
	}
	#end
}
