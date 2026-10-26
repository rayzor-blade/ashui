package ashui.components.code;

import ashui.components.Button;
import ashui.components.CodeEditor;
import ashui.components.Library;
import ashui.components.Toggle;
import ashui.components.Tooltip;
import ashui.css.Identity;
import ashui.input.Events.KeyEvent;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Ref;

/** Search controls and results live only as long as their editor view. */
class CodeFind {
	public final state:CodeFindState;
	public final result = Signal.make(new CodeSearch("", ""));
	final editor:CodeEditor;
	final field = new Ref<ashui.ui.Input>();
	var focusRequested = false;
	final writable:Void->Bool;
	final shortcuts:Bool;
	var pendingOffset:Null<Int>;

	public function new(editor:CodeEditor, writable:Void->Bool, shortcuts = true) {
		this.shortcuts = shortcuts;
		var lastOpen = false, lastQuery = "", lastCase = false, lastWord = false, lastRegex = false;
		this.editor = editor; this.writable = writable; state = editor.state.search;
		new Watch(() -> {
			var open = state.opened.get();
			{open:open, text:open ? editor.value.get() : "", query:state.query.get(), sensitive:state.matchCase.get(), word:state.wholeWord.get(), regex:state.regex.get()};
		}, input -> {
			if (input.open) fresh();
			else if (result.get().query != "" || result.get().text != "") result.set(new CodeSearch("", ""));
			var moved = input.open && (!lastOpen || input.query != lastQuery || input.sensitive != lastCase || input.word != lastWord || input.regex != lastRegex);
			lastOpen = input.open; lastQuery = input.query; lastCase = input.sensitive; lastWord = input.word; lastRegex = input.regex;
			if (input.open && pendingOffset != null) { choose(pendingOffset); pendingOffset = null; }
			else if (moved) choose(editor.editing.selectionRange().from);
		});
		new Watch(() -> field.get(), input -> if (input != null && focusRequested) focusInput());
	}

	public function show(replace = false):Void {
		var range = editor.editing.selectionRange(), selected = editor.value.get().substring(range.from, range.to);
		if (!state.opened.get() && selected != "" && selected.indexOf("\n") < 0) { state.regex.set(false); state.query.set(selected); }
		state.replacing.set(replace && writable()); state.opened.set(true);
		focusRequested = true; focusInput();
	}

	function focusInput():Void {
		var input = field.get();
		if (input == null || !state.opened.get()) return;
		focusRequested = false;
		input.focus(); input.editing.anchor.set(0); input.editing.caret.set(state.query.get().length);
	}

	public function hide():Void { focusRequested = false; state.opened.set(false); editor.focus(); }

	function current():Int {
		var range = editor.editing.selectionRange(), found = result.get(), at = found.lowerBound(range.from);
		return at < found.matches.length && found.matches[at].from == range.from && found.matches[at].to == range.to ? at : -1;
	}
	function select(index:Int):Void {
		var found = result.get(); if (found.matches.length == 0) return;
		var m = found.matches[(index + found.matches.length) % found.matches.length];
		editor.select(m.from, m.to); editor.revealSelection();
	}
	function choose(offset:Int):Void select(result.get().lowerBound(offset));

	// Input and an action may arrive in one event batch, before the reactive watch flushes.
	function fresh():CodeSearch {
		var found = result.get(), text = editor.value.get();
		if (found.text != text || found.query != state.query.get() || found.matchCase != state.matchCase.get() || found.wholeWord != state.wholeWord.get() || found.regex != state.regex.get())
			result.set(found = new CodeSearch(text, state.query.get(), state.matchCase.get(), state.wholeWord.get(), state.regex.get()));
		return found;
	}

	public function next(backward = false):Void {
		if (!state.opened.get()) {
			state.opened.set(true);
			fresh();
		}
		var found = fresh(), at = current();
		if (at >= 0) select(at + (backward ? -1 : 1));
		else { at = found.lowerBound(editor.editing.selectionRange().from); select(at - (backward ? 1 : 0)); }
	}

	public function replaceOne():Void {
		if (!writable()) return;
		var found = fresh(), at = current();
		if (at < 0) { choose(editor.editing.selectionRange().from); at = current(); }
		if (at < 0) return;
		var m = found.matches[at], text = found.replacement(m, state.replacement.get());
		if (text == editor.value.get().substring(m.from,m.to)) { next(); return; }
		pendingOffset = m.from+text.length;
		editor.applyEdits([{from:m.from, to:m.to, text:text}]); editor.select(m.from+text.length, m.from+text.length);
	}
	public function replaceAll():Void {
		if (writable()) editor.applyEdits(fresh().edits(state.replacement.get()));
	}

	public function shortcut(event:KeyEvent):Bool {
		if (!shortcuts) return switch event.key { case Named(Escape) if (state.opened.get()): event.preventDefault(); hide(); true; case _: false; };
		var mac = ashui.input.Keyboard.isMac(), mod = mac ? event.superKey && !event.control : event.control && !event.superKey;
		switch event.key {
			case Character(c) if (mod && c.toLowerCase() == "f" && !event.shift && (!event.alt || mac)):
				event.preventDefault(); show(event.alt); return true;
			case Character(c) if (!mac && mod && c.toLowerCase() == "h" && !event.alt && !event.shift):
				event.preventDefault(); show(true); return true;
			case Named(F3) if (!event.control && !event.superKey && !event.alt):
				event.preventDefault(); if (!state.opened.get() && state.query.get() == "") show(); else next(event.shift); return true;
			case Character(c) if (mac && mod && c.toLowerCase() == "g" && !event.alt && state.opened.get()):
				event.preventDefault(); next(event.shift); return true;
			case Named(Escape) if (state.opened.get()): event.preventDefault(); hide(); return true;
			case _: return false;
		}
	}

	public function view(maxWidth:ashui.layout.IntoReactive<Single>):Element return <if {state.opened.get()}>${controls(maxWidth)}</if>;

	function controls(maxWidth:ashui.layout.IntoReactive<Single>):Element {
		var search = new ashui.ui.Input({value:state.query, placeholder:"Find"}); field.bind(search);
		Identity.of(search.tree, search.node.id).addClasses(["ui-input", "ui-code-find-query"]).setAttribute("aria-label", "Find");
		search.editing.onKey = event -> switch event.key {
			case Named(Enter): event.preventDefault(); next(event.shift); true;
			case _: shortcut(event);
		};
		var empty = Computed.make(() -> result.get().matches.length == 0);
		var controls = <div class="ui-code-find" maxWidth={maxWidth} onKeyDown={event -> { if (!event.defaultPrevented) shortcut(event); }}>
			<div class="ui-code-find-row">
				<tooltip label="Toggle replace"><toggle pressed={state.replacing} disabled={Computed.make(() -> !writable())} size={Sm} class="ui-code-find-toggle"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6"/></svg></toggle></tooltip>
				${search}
				<tooltip label="Match case"><toggle pressed={state.matchCase} size={Sm} class="ui-code-find-case"><text>Aa</text></toggle></tooltip>
				<tooltip label="Match whole word"><toggle pressed={state.wholeWord} size={Sm} class="ui-code-find-word"><text>Ab</text></toggle></tooltip>
				<tooltip label="Use regular expression (optional Haxe ~/pattern/flags)"><toggle pressed={state.regex} size={Sm} class="ui-code-find-regex"><text>.*</text></toggle></tooltip>
				${action("Close find (Escape)", "close", "M6 6l12 12M6 18L18 6", hide)}
			</div>
			<if {state.replacing.get() && writable()}><div class="ui-code-find-row ui-code-find-replace-row">
				${replacementInput()}
				${action("Replace", "replace", "M4 7h13l-3-3m3 3-3 3M20 17H7l3-3m-3 3 3 3", replaceOne, () -> empty.get() || !writable())}
				${action("Replace all (Ctrl/Cmd+Enter in replace field)", "replace-all", "M4 4v16m16-16v16M7 8h10l-3-3m3 3-3 3M17 16H7l3-3m-3 3 3 3", replaceAll, () -> empty.get() || !writable())}
			</div></if>
			<div class="ui-code-find-row ui-code-find-status-row">
				<text class="ui-code-find-status">${result.get().error != null ? result.get().error : state.query.get() == "" ? "" : result.get().matches.length == 0 ? "No results" : (current() < 0 ? "" : (current()+1) + " of ") + result.get().matches.length}</text>
				${action("Previous match (Shift+Enter)", "previous", "M6 14l6-6 6 6", () -> next(true), () -> empty.get())}
				${action("Next match (Enter)", "next", "M6 10l6 6 6-6", () -> next(), () -> empty.get())}
			</div>
		</div>;
		Identity.of(controls.tree, controls.node.id).bindAttribute("data-invalid", Computed.make(() -> result.get().error == null ? null : "true"));
		return controls;
	}

	function replacementInput():Element {
		var input = new ashui.ui.Input({value:state.replacement, placeholder:"Replace"});
		Identity.of(input.tree, input.node.id).addClasses(["ui-input", "ui-code-find-replacement"]).setAttribute("aria-label", "Replace");
		input.editing.onKey = event -> switch event.key {
			case Named(Enter): event.preventDefault(); event.control || event.superKey ? replaceAll() : replaceOne(); true;
			case _: shortcut(event);
		};
		return input;
	}

	function action(label:String, name:String, path:String, run:Void->Void, ?disabled:Void->Bool):Element {
		var icon = new ashui.ui.Svg(ashui.svg.SvgDocument.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="'+path+'"/></svg>'));
		var button =
		<button type="button" variant={Ghost} size={Icon} disabled={Computed.make(() -> disabled != null && disabled())} onClick={_ -> run()}>
			${icon}
		</button>;
		Identity.of(button.tree, button.node.id).addClasses(["ui-code-find-" + name]).setAttribute("aria-label", label);
		return <tooltip label={label}>${button}</tooltip>;
	}
}
