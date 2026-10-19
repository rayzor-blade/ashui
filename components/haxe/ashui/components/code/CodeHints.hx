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

/** A piece of documentation or a hint about a range of the text, shown in a popover over it. **/
typedef CodeHint = {
	/** The range it is about, as offsets into the text; the popover opens at its start and stays while the pointer is over it. **/
	var from:Int;
	var to:Int;
	/** Code shown first in the editor's own colours, a declaration or a signature; may run over several lines. **/
	@:optional var signature:String;
	/** The language of `signature`, the editor's own by default. **/
	@:optional var language:String;
	/** The text under it, in paragraphs set apart by blank lines; each line wraps. **/
	@:optional var docs:String;
	/** A CSS class for the popover; `ui-code-hint-error`, `-warning` and `-info` give it an icon and a border in the diagnostic's colour, as a toast has. **/
	@:optional var className:String;
}

/** The anchor on a character in the window's coordinates. **/
typedef CodeRect = {x:Float, y:Float, width:Float, height:Float};

/** What the hints need of the editor they belong to. **/
typedef HintHost = {
	final tree:LayoutTree;
	/** Where a character is in the window, and what character is under a point; null and -1 where there is none. **/
	final rectAt:Int->Null<CodeRect>;
	final offsetAt:(Float, Float) -> Int;
	/** The app's hover, asked after the pointer rests; what it gives is shown, and null leaves it to the decorations' titles. **/
	final provide:Null<Int->Null<CodeHint>>;
	final decorationsAt:Int->Array<CodeDecoration>;
	/** The highlighter for a language name, or the editor's own for null. **/
	final highlighter:Null<String>->CodeHighlighter;
	/** Seconds the pointer rests on a character before the hover is asked. **/
	final delay:Float;
}

/**
	A popover of documentation or hints beside a range of an editor's text.
	It opens when the pointer has rested on a character for a moment, from
	what the app's hover gives, or from the titles of the decorations over the
	character, or when the app shows one itself, as a language server's
	answer arrives. It stays while the pointer is on the range or on the
	popover, so it can be read, and closes when it leaves both, when the text
	changes or scrolls, and on Escape. Styled by `.ui-code-hint`, its
	`.ui-code-hint-signature` and `.ui-code-hint-docs`, and by
	`--ui-code-hint-bg`, `--ui-code-hint-width`.
**/
class CodeHints {
	/** Seconds the pointer may be off both before the popover closes. **/
	static inline var LEAVE = 0.2;

	/** The icon beside a diagnostic's message, as a toast's: a cross in a circle, a warning triangle, an information mark. **/
	static final ICONS = [
		"error" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>),
		"warning" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>),
		"info" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>)
	];

	/** `error`, `warning` or `info` for a popover whose class says so, which gives it an icon and a border in that colour. **/
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
	/** What the open popover was built under, disposed when it closes. **/
	var owner:Null<Owner> = null;

	/** The character the pointer rests on, or -1. **/
	public var hovered(default, null) = -1;

	public function new(host:HintHost)
		this.host = host;

	var panelNode:Null<Div> = null;

	/** Whether the pointer is over the popover: a press on it takes focus from the editor, which must not close it. **/
	public function pointerOver():Bool {
		if (panelNode == null || entry == null)
			return false;
		var b = host.tree.getScrolledBounds(panelNode.node), at = ashui.input.Pointer.at(host.tree);
		return b != null && at.x >= b.x && at.x < b.x + b.width && at.y >= b.y && at.y < b.y + b.height;
	}

	/** Whether a popover is open. **/
	public function isOpen():Bool
		return entry != null;

	/** The pointer is at `(x, y)` in the window, over the editor's text, with no button down. **/
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

	/** The pointer left the editor's text. **/
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

	/** Opens `hint`, replacing what is open. A `pinned` one stays until it is closed, whatever the pointer does; the text changing or scrolling still closes it. **/
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

	/** Closes the popover, if there is one. **/
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

	/** The text changed or moved under the popover. **/
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

	/** The popover itself: the signature in the editor's colours, then the paragraphs of the docs. **/
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
			var syntax = host.highlighter(hint.language), state = "";
			for (line in hint.signature.split("\n")) {
				var result = syntax.highlight(line, state);
				state = result.state;
				var row = Library.part("ui-code-hint-line");
				var tokens:Array<CodeHighlighter.CodeToken> = result.tokens.length == 0 ? [{from: 0, to: line.length, kind: CodeHighlighter.CodeTokenKind.Plain}] : result.tokens;
				for (token in tokens) {
					var text:Text = <text class="ui-code-text ui-code-hint-token">${line.substring(token.from, token.to)}</text>;
					Identity.of(text.tree, text.node.id).setAttribute("data-token", token.kind);
					row.appendChild(text);
				}
				if (line == "")
					row.appendChild(<text class="ui-code-text ui-code-hint-token">${" "}</text>);
				signature.appendChild(row);
			}
			body.appendChild(signature);
		}
		if (hint.docs != null && hint.docs != "") {
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
