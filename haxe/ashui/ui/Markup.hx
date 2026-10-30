package ashui.ui;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.ExprTools;
#end

/**
	Enables HXX elements as first-class expressions in Haxe code:

	```haxe
	function card(title:String):Element
	    return <card><card-header><card-title>{title}</card-title></card-header></card>;

	var list = <ul><for {item in items}><li>{item}</li></for></ul>;
	```

	Add `--macro ashui.ui.Markup.enable()` to the build. The macro processes
	application and library classes, excluding the standard library.
	Each expression has the type of its resulting element. Embedded Haxe
	expressions keep their source positions for errors and completion.
**/
class Markup {
	#if macro
	static var enabled = false;

	/** Packages excluded from template processing, including the standard library and compiler internals. **/
	static final SKIPPED = [
		"haxe", "sys", "hl", "cpp", "js", "jvm", "eval", "neko", "php", "python", "cs", "java", "lua", "flash", "tink"
	];

	/** Macros that accept inline markup, including `hxx`, `SvgDocument.of`, and `SvgDocument.embed`. **/
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

	/** Enables inline HXX processing for subsequently typed classes. **/
	public static function enable():Void {
		if (enabled)
			return;
		enabled = true;
		Compiler.addGlobalMetadata("", "@:build(ashui.ui.Markup.build())", true, true, false);
	}

	/**
		Parses the embedded Haxe expression under the compiler display cursor,
		preserving file positions for completion. Returns null when the cursor
		is in markup text or a tag rather than an expression.
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


	/**
		Where the display cursor is in the markup's tags, as a Haxe completion request: after `<` or `</`,
		a type listing the tags to complete a field of; among a tag's attributes, a structure literal
		typed against the tag's props, for the compiler to complete the missing fields of. Null where the
		cursor is in text, a quoted value or an expression. A tag's name completes only where it is a
		Haxe identifier: those with a hyphen are not offered.
	**/
	static function displayedTag(pos:Position, source:String):Null<Expr> {
		var at = Compiler.getDisplayPos();
		if (at == null)
			return null;
		var info = Context.getPosInfos(pos);
		var offset = at.pos - info.min;
		if (offset < 0 || offset > source.length)
			return null;
		// Walk to the cursor, tracking whether it is in a tag, outside braces and quotes.
		var tagStart = -1, depth = 0, quote = "", text = 0;
		var i = 0;
		while (i < offset) {
			var c = source.charAt(i);
			if (tagStart < 0) {
				if (c == "{")
					text++;
				else if (c == "}" && text > 0)
					text--;
				else if (c == "<" && text == 0 && ~/[a-zA-Z\/]/.match(source.charAt(i + 1))) {
					tagStart = i;
					depth = 0;
					quote = "";
				}
			} else if (quote != "") {
				if (c == quote)
					quote = "";
			} else if (depth > 0) {
				if (c == "{")
					depth++;
				else if (c == "}")
					depth--;
			} else if (c == "{")
				depth++;
			else if (c == "\"" || c == "'")
				quote = c;
			else if (c == ">")
				tagStart = -1;
			i++;
		}
		if (tagStart < 0 || depth > 0 || quote != "")
			return null;
		var inside = source.substring(tagStart + 1, offset);
		var here = Context.makePosition({file: at.file, min: at.pos, max: at.pos});
		if (~/^\/?[a-zA-Z0-9.\-]*$/.match(inside))
			return {expr: EDisplay(macro @:pos(here) (null : ashui.ui.HxxTags), DKDot), pos: here};
		// A value being typed, after an equals sign, is not an attribute's name.
		var last = inside.substring(inside.lastIndexOf(" ") + 1);
		if (inside.charAt(inside.length - 1) != " " && last.indexOf("=") >= 0)
			return null;
		var tag = ~/^\/?([a-zA-Z0-9.\-]+)/;
		if (!tag.match(inside))
			return null;
		var type = Hxx.attributeType(tag.matched(1));
		if (type == null)
			return null;
		// The display sits inside the check, where the type it is checked against reaches the literal.
		var literal:Expr = {expr: EDisplay({expr: EObjectDecl([]), pos: here}, DKStructure), pos: here};
		return {expr: ECheckType(literal, type), pos: here};
	}

	/** Finds the closing brace of the interpolation containing `offset`, or the source end if unclosed. **/
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

	/** Parses a source slice as a Haxe expression at its file position. Returns null on parse failure. **/
	static function parseAt(source:String, start:Int, end:Int, info:{file:String, min:Int, max:Int}):Null<Expr> {
		var p = Context.makePosition({file: info.file, min: info.min + start, max: info.min + end});
		return try Context.parseInlineString(source.substring(start, end), p) catch (_:Dynamic) null;
	}

	/** Returns enclosing `<for>` header ranges at a position, outermost first. **/
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

	/** Rewrites inline markup in class fields through the HXX macro. Returns null when no markup needs processing. **/
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
					if (focus == null)
						focus = displayedTag(e.pos, source);
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
