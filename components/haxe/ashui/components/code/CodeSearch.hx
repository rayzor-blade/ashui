package ashui.components.code;

import ashui.components.code.CodeHistory.CodeEdit;

typedef CodeSearchMatch = {from:Int, to:Int};

/** Text search results and a compiled regular expression, independent of editor views and rendered rows. **/
class CodeSearch {
	public final matches:Array<CodeSearchMatch> = [];
	public var error(default, null):Null<String>;
	public final text:String;
	public final query:String;
	public final matchCase:Bool;
	public final wholeWord:Bool;
	public final regex:Bool;
	var expression:EReg;
	static final word = new EReg("[\\p{L}\\p{N}_]", "u");

	public function new(text:String, query:String, matchCase = false, wholeWord = false, regex = false) {
		this.text = text; this.query = query; this.matchCase = matchCase; this.wholeWord = wholeWord; this.regex = regex;
		if (query == "") return;
		try {
			var pattern = regex ? query : EReg.escape(query), flags = "mu" + (matchCase ? "" : "i");
			if (regex && StringTools.startsWith(query, "~/")) {
				var end = query.lastIndexOf("/");
				if (end < 2) throw "Expected ~/pattern/flags";
				pattern = query.substring(2, end); flags = query.substr(end + 1);
				if (!~/^[gimsu]*$/.match(flags)) throw "Regex flags must be g, i, m, s or u";
			}
			expression = new EReg(pattern, flags);
			#if hl
			// Some hosts return a null handle instead of throwing for a rejected pattern.
			if ((@:privateAccess expression.r) == null) throw "Invalid regular expression";
			#end
			var at = 0;
			while (at <= text.length && expression.matchSub(text, at)) {
				var p = expression.matchedPos(), end = p.pos + p.len;
				if (!wholeWord || (!wordBefore(p.pos) && !wordAfter(end))) matches.push({from:p.pos, to:end});
				if (p.len > 0) at = end;
				else if (p.pos == text.length) break;
				else at = step(text, p.pos);
			}
		} catch (failure:Dynamic) {
			matches.resize(0); error = Std.string(failure);
		}
	}

	static function step(text:String, at:Int):Int {
		var code = text.charCodeAt(at);
		return at + (code >= 0xd800 && code <= 0xdbff && at + 1 < text.length && text.charCodeAt(at+1) >= 0xdc00 && text.charCodeAt(at+1) <= 0xdfff ? 2 : 1);
	}
	function wordBefore(at:Int):Bool {
		if (at <= 0) return false;
		var start = at - 1, code = text.charCodeAt(start);
		if (code >= 0xdc00 && code <= 0xdfff && start > 0) start--;
		return word.match(text.substring(start, at));
	}
	function wordAfter(at:Int):Bool return at < text.length && word.match(text.substring(at, step(text, at)));

	/** First match starting at or after an offset. Also bounds visible-row highlighting. */
	public function lowerBound(offset:Int):Int {
		var low = 0, high = matches.length;
		while (low < high) { var mid = (low + high) >> 1; if (matches[mid].from < offset) low = mid + 1; else high = mid; }
		return low;
	}

	public function replacement(match:CodeSearchMatch, value:String):String {
		if (!regex) return value;
		expression.matchSub(text, match.from);
		function group(index:Int):Null<String> return try expression.matched(index) ?? "" catch (_:Dynamic) null;
		var out = new StringBuf(), at = 0;
		while (at < value.length) {
			var c = value.charAt(at++);
			if (c != "$" || at == value.length) { out.add(c); continue; }
			var next = value.charAt(at);
			if (next == "$") { out.add("$"); at++; }
			else if (next == "&") { out.add(group(0)); at++; }
			else if (next >= "0" && next <= "9") {
				var index = Std.parseInt(next), count = 1;
				if (at+1 < value.length && value.charAt(at+1) >= "0" && value.charAt(at+1) <= "9" && group(Std.parseInt(value.substr(at, 2))) != null) { index = Std.parseInt(value.substr(at, 2)); count = 2; }
				var captured = group(index);
				if (captured == null) out.add("$"); else { out.add(captured); at += count; }
			} else out.add("$");
		}
		return out.toString();
	}

	public function edits(replacement:String):Array<CodeEdit>
		return [for (match in matches) {from:match.from, to:match.to, text:this.replacement(match, replacement)}];
}
