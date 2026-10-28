package ashui.components.code;

import ashui.animation.AnimationScheduler;
import ashui.components.Library;
import ashui.components.code.CodeAnnotations.CodeDecoration;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Div;
import ashui.ui.Svg;
import ashui.ui.Text;
import ashui.ui.TopLayer;

/** Documentation or a hint displayed beside a text range. **/
typedef CodeHint = {
	/** Start offset of the hint range; `to` is the end offset. The popover anchors at the start and stays open while the range is hovered. **/
	var from:Int;
	var to:Int;
	/** Code signature or declaration shown before the documentation, using syntax colors. May span multiple lines. **/
	@:optional var signature:String;
	/** Language used to highlight the signature. Defaults to the editor language. **/
	@:optional var language:String;
	/** Signature range to draw in bold, such as the active parameter. **/
	@:optional var emphasis:{from:Int, to:Int};
	/** Documentation text with blank lines between paragraphs. Lines wrap. **/
	@:optional var docs:String;
	/** Builds rich documentation under the popover owner. Disposed on close; takes precedence over `docs`. **/
	@:optional var renderDocs:Void->Element;
	/**
		Popover CSS class. `ui-code-hint-error`, `ui-code-hint-warning`, and
		`ui-code-hint-info` add a diagnostic icon and a matching border.
	**/
	@:optional var className:String;
}

/** Character rectangle in window coordinates. **/
typedef CodeRect = {x:Float, y:Float, width:Float, height:Float};

/** Editor operations needed by hint popovers. **/
typedef HintHost = {
	final tree:LayoutTree;
	/** Returns a character rectangle in window coordinates, or null when unavailable. **/
	final rectAt:Int->Null<CodeRect>;
	final offsetAt:(Float, Float) -> Int;
	/** Provides a hint after a hover delay. Null falls back to decoration titles. **/
	final provide:Null<Int->Null<CodeHint>>;
	final decorationsAt:Int->Array<CodeDecoration>;
	/** Resolves a language highlighter, or the editor highlighter for null. **/
	final highlighter:Null<String>->CodeHighlighter;
	/** Hover delay before requesting a hint, in seconds. **/
	final delay:Float;
}

/**
	Shows documentation beside a text range.
	Hints come from the hover provider, decoration titles, or an explicit
	application call, including asynchronous language-service results.
	The popover stays open while the pointer is over the range or popover.
	It closes after leaving both, editing, scrolling, or Escape.

	CSS: `.ui-code-hint`, `.ui-code-hint-signature`, and `.ui-code-hint-docs`.
	Variables: `--ui-code-hint-bg`, `--ui-code-hint-width`, and `--ui-code-hint-height`.
**/
class CodeHints {
	/** Delay before closing after leaving the range and popover, in seconds. **/
	static inline var LEAVE = 0.2;

	/** Default icons for error, warning, and information hints. **/
	static final ICONS = [
		"error" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>),
		"warning" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>),
		"info" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>)
	];

	/** Resolves a diagnostic type from the popover class, or null for an ordinary hint. **/
	static function kindOf(className:Null<String>):Null<String> {
		if (className != null)
			for (kind in ["error", "warning", "info"])
				if (className.indexOf("ui-code-hint-" + kind) >= 0)
					return kind;
		return null;
	}

	final host:HintHost;
	var resting:Null<ashui.animation.AnimationScheduler.Timer> = null;
	var leaving:Null<ashui.animation.AnimationScheduler.Timer> = null;
	var entry:Null<ashui.ui.TopLayer.TopEntry> = null;
	var shown:Null<CodeHint> = null;
	var pinned = false;
	var overPanel = false;
	/** Owner of the open popover, disposed when the popover closes. **/
	var owner:Null<Owner> = null;

	/** Character offset under the resting pointer, or -1. **/
	public var hovered(default, null) = -1;

	public function new(host:HintHost)
		this.host = host;

	var panelNode:Null<Div> = null;

	/** Returns whether the pointer is over the popover, allowing presses without closing it on editor blur. **/
	public function pointerOver():Bool {
		if (panelNode == null || entry == null)
			return false;
		var b = host.tree.getScrolledBounds(panelNode.node), at = ashui.input.Pointer.at(host.tree);
		return b != null && at.x >= b.x && at.x < b.x + b.width && at.y >= b.y && at.y < b.y + b.height;
	}

	/** Returns whether a hint popover is open. **/
	public function isOpen():Bool
		return entry != null;

	/** Tracks pointer movement over editor text in window coordinates, with no button pressed. **/
	public function pointerAt(x:Float, y:Float):Void {
		var offset = host.offsetAt(x, y);
		if (offset == hovered)
			return;
		hovered = offset;
		stopResting();
		if (shown != null && !pinned) {
			if (offset >= shown.from && offset < shown.to)
				return stopLeaving();
			closeSoon();
		}
		if (offset >= 0 && (shown == null || !pinned))
			resting = AnimationScheduler.main.after(host.delay, () -> {
				resting = null;
				ask(offset);
			});
	}

	/** Handles the pointer leaving editor text. **/
	public function pointerLeft():Void {
		hovered = -1;
		stopResting();
		if (shown != null && !pinned)
			closeSoon();
	}

	function ask(offset:Int):Void {
		var hint = host.provide == null ? null : host.provide(offset);
		if (hint == null) {
			var titled = [for (d in host.decorationsAt(offset)) if (d.title != null && d.title != "") d];
			if (titled.length > 0) {
				var from = titled[0].from, to = titled[0].to;
				for (d in titled) {
					from = Std.int(Math.min(from, d.from));
					to = Std.int(Math.max(to, d.to));
				}
				hint = {from: from, to: Std.int(Math.max(to, from + 1)), docs: [for (d in titled) d.title].join("\n\n"), className: StringTools.replace(titled[0].className, "squiggle", "hint")};
			}
		}
		if (hint != null)
			show(hint, false);
	}

	/**
		Replaces the current popover with a hint. Pinned hints ignore pointer
		leaving but still close on explicit dismissal, editing, or scrolling.
	**/
	public function show(hint:CodeHint, pinned:Bool):Void {
		hide();
		var anchor = host.rectAt(hint.from);
		if (anchor == null || host.tree.root == null)
			return;
		var last = host.rectAt(Std.int(Math.max(hint.from, hint.to - 1)));
		var width = last == null || last.y != anchor.y ? anchor.width : Math.max(anchor.width, last.x + last.width - anchor.x);
		var scope = new Owner(host.tree);
		var panel = scope.run(() -> build(hint));
		panelNode = panel;
		overPanel = false;
		var i = Interaction.of(panel.node);
		i.onPointerEnter(_ -> {
			overPanel = true;
			stopLeaving();
		});
		i.onPointerLeave(_ -> {
			overPanel = false;
			if (!this.pinned)
				closeSoon();
		});
		shown = hint;
		this.pinned = pinned;
		owner = scope;
		entry = TopLayer.open(host.tree, panel, Beside(anchor.x, anchor.y, width, anchor.height, "bottom", 4, "start"), null, () -> {
			entry = null;
			shown = null;
			release(scope);
		}, false, true, true);
	}

	/** Closes the current hint popover, if any. **/
	public function hide():Void {
		stopLeaving();
		var open = entry;
		entry = null;
		shown = null;
		pinned = false;
		overPanel = false;
		panelNode = null;
		if (open != null)
			open.close();
		if (owner != null)
			release(owner);
	}

	function release(scope:Owner):Void {
		scope.dispose();
		if (owner == scope)
			owner = null;
	}

	/** Closes the hint after the text changes or scrolls. **/
	public function moved():Void {
		stopResting();
		hide();
	}

	public function dispose():Void {
		stopResting();
		hide();
	}

	function closeSoon():Void {
		if (leaving != null || entry == null || overPanel)
			return;
		leaving = AnimationScheduler.main.after(LEAVE, () -> {
			leaving = null;
			if (!overPanel)
				hide();
		});
	}

	function stopResting():Void {
		if (resting != null)
			resting.cancel();
		resting = null;
	}

	function stopLeaving():Void {
		if (leaving != null)
			leaving.cancel();
		leaving = null;
	}

	/** Splits a signature line at the emphasized range boundaries. **/
	static function pieces(from:Int, to:Int, lineStart:Int, emphasis:Null<{from:Int, to:Int}>):Array<{from:Int, to:Int, emphasised:Bool}> {
		if (emphasis == null)
			return [{from: from, to: to, emphasised: false}];
		var start = emphasis.from - lineStart, end = emphasis.to - lineStart, cuts = [from];
		for (cut in [start, end])
			if (cut > from && cut < to)
				cuts.push(cut);
		cuts.push(to);
		return [for (i in 0...cuts.length - 1) {from: cuts[i], to: cuts[i + 1], emphasised: cuts[i] >= start && cuts[i + 1] <= end}];
	}

	/** Builds the signature and documentation content of a hint. **/
	function build(hint:CodeHint):Div {
		var panel = Library.part("ui-code-hint", null, null, null, null, hint.className == null ? null : hint.className.split(" "));
		var kind = kindOf(hint.className);
		if (kind != null) {
			var icon = new Svg(ICONS.get(kind), {width: 16, height: 16});
			Identity.of(icon.tree, icon.node.id).setClasses(["ui-code-hint-icon"]);
			panel.appendChild(icon);
		}
		var body = Library.part("ui-code-hint-body");
		panel.appendChild(body);
		if (hint.signature != null && hint.signature != "") {
			var signature = Library.part("ui-code-hint-signature");
			var syntax = host.highlighter(hint.language), state = "", lineStart = 0;
			for (line in hint.signature.split("\n")) {
				var result = syntax.highlight(line, state);
				state = result.state;
				var row = Library.part("ui-code-hint-line");
				var tokens:Array<CodeHighlighter.CodeToken> = result.tokens.length == 0 ? [{from: 0, to: line.length, kind: CodeHighlighter.CodeTokenKind.Plain}] : result.tokens;
				for (token in tokens)
					for (piece in pieces(token.from, token.to, lineStart, hint.emphasis)) {
						var text:Text = <text class="ui-code-text ui-code-hint-token">${line.substring(piece.from, piece.to)}</text>;
						var identity = Identity.of(text.tree, text.node.id);
						identity.setAttribute("data-token", token.kind);
						if (piece.emphasised)
							identity.setAttribute("data-emphasis", "true");
						row.appendChild(text);
					}
				if (line == "")
					row.appendChild(<text class="ui-code-text ui-code-hint-token">${" "}</text>);
				signature.appendChild(row);
				lineStart += line.length + 1;
			}
			body.appendChild(signature);
		}
		if (hint.renderDocs != null) body.appendChild(hint.renderDocs());
		else if (hint.docs != null && hint.docs != "") {
			var docs = Library.part("ui-code-hint-docs");
			for (line in hint.docs.split("\n")) {
				if (line == "")
					docs.appendChild(Library.part("ui-code-hint-gap"));
				else
					docs.appendChild(<text class="ui-code-hint-text">${line}</text>);
			}
			body.appendChild(docs);
		}
		return panel;
	}
}
