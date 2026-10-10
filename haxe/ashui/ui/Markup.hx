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

	/**
		The embedded `{expr}` of markup `source` at `pos` that holds the
		display position, up to it, parsed where it stands in the file, so
		the compiler's display request lands in it; null when the cursor is
		in no expression, as in a tag's name or text.
	**/
	static function displayed(pos:Position, source:String):Null<Expr> {
		var at = Compiler.getDisplayPos();
		if (at == null)
			return null;
		var info = Context.getPosInfos(pos);
		// The markup's text starts where its position does.
		var offset = at.pos - info.min;
		if (offset < 0 || offset > source.length)
			return null;
		var start = -1, depth = 0, i = offset - 1;
		while (i >= 0) {
			var c = source.charAt(i);
			if (c == "}")
				depth++;
			else if (c == "{") {
				if (depth == 0) {
					start = i;
					break;
				}
				depth--;
			}
			i--;
		}
		if (start < 0)
			return null;
		var end = closing(source, offset);
		var focus = parseAt(source, start + 1, end, info);
		// After a dot, what follows the cursor is the word being typed, which an inline parse does not read past:
		// cut there, and an editor filters by that word itself.
		if (focus == null)
			focus = parseAt(source, start + 1, offset, info);
		if (focus == null)
			return null;
		// Inside <for {x in xs}>, the loop's variables are in scope.
		// Innermost loop first, so each outer one wraps it.
		var heads = loopHeads(source, start);
		heads.reverse();
		for (head in heads) {
			var it = parseAt(source, head.start, head.end, info);
			if (it != null)
				focus = {expr: EFor(it, focus), pos: focus.pos};
		}
		return focus;
	}

	/** Where the `{` … `}` around `offset` closes, or the end of `source` when it does not. **/
	static function closing(source:String, offset:Int):Int {
		var depth = 0;
		for (i in offset...source.length) {
			var c = source.charAt(i);
			if (c == "{")
				depth++;
			else if (c == "}") {
				if (depth == 0)
					return i;
				depth--;
			}
		}
		return source.length;
	}

	/** `source` from `start` to `end` parsed as an expression where it stands in the file; null when it does not parse. **/
	static function parseAt(source:String, start:Int, end:Int, info:{file:String, min:Int, max:Int}):Null<Expr> {
		var p = Context.makePosition({file: info.file, min: info.min + start, max: info.min + end});
		return try Context.parseInlineString(source.substring(start, end), p) catch (_:Dynamic) null;
	}

	/** The heads of the `<for {…}>` tags still open at `before`, outermost first: where each head's text starts and ends. **/
	static function loopHeads(source:String, before:Int):Array<{start:Int, end:Int}> {
		var open:Array<{start:Int, end:Int}> = [];
		var tag = ~/<(\/?)for\b/g;
		var at = 0;
		while (at < before && tag.matchSub(source, at, before - at)) {
			var m = tag.matchedPos();
			at = m.pos + m.len;
			if (tag.matched(1) == "/") {
				open.pop();
				continue;
			}
			var brace = source.indexOf("{", at);
			if (brace < 0 || brace >= before)
				break;
			var end = closing(source, brace + 1);
			open.push({start: brace + 1, end: end});
			at = end;
		}
		return open;
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
				case EMeta({name: ":markup"}, {expr: EConst(CString(source, _))}) if (Context.containsDisplayPosition(e.pos)):
					// The compiler answers a display request inside a macro's arguments without running the macro, for the
					// markup as a whole: the expression under the cursor is typed first, so the request is answered there.
					found = true;
					var lowered = macro @:pos(e.pos) ashui.ui.Hxx.hxx($e);
					var focus = displayed(e.pos, source);
					focus == null ? lowered : macro @:pos(e.pos) {
						$focus;
						$lowered;
					};
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
