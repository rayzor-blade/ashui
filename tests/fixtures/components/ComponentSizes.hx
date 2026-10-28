// Shared Size variants and CSS-driven editing geometry, git-bug e8a1b50.
import ashui.components.Badge;
import ashui.components.Checkbox;
import ashui.components.Combobox;
import ashui.components.Input;
import ashui.components.InputOtp;
import ashui.components.Label;
import ashui.components.RadioGroup;
import ashui.components.Select;
import ashui.components.Size;
import ashui.components.Slider;
import ashui.components.Textarea;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Div;
import ashui.ui.Ref;

class ComponentSizes {
	static var failures = 0;
	static var checks = 0;
	static function check(message:String, ok:Bool, ?detail:Dynamic):Void {
		checks++;
		if (!ok) { failures++; Sys.println('FAIL $message: $detail'); }
		else Sys.println('ok   $message');
	}
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);

	static function variant(size:Size):Void {
		var tree = new LayoutTree(), dispose = () -> {};
		var disabled = Signal.make(false), checked = Signal.make(false), radio = Signal.make("a"), choice = Signal.make("");
		var code = Signal.make(""), completed = "", volume = Signal.make(0.25), vertical = Signal.make(0.25);
		var query = Signal.make(""), entered = "", submitted = "", submits = 0;
		var area = new Ref<Textarea>(), custom = new Ref<Textarea>();
		var root:Div = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={800} height={1600} class="flex-col gap-3 items-start">
				<input id="text" size={size} value="Editable text" disabled={disabled} />
				<input id="password" size={size} type="password" value="secret" revealable={true} disabled={disabled}>
					<input-icon><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg></input-icon>
				</input>
				<form class="flex-col gap-2" onSubmit={data -> { submits++; submitted = data.get("query"); }}>
					<label id="search-label" for="search">Search</label>
					<input id="search" name="query" type="search" size={size} value={query} placeholder="Search projects" required={true} maxlength={12} disabled={disabled} onInput={value -> entered = value}>
						<input-icon><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10" cy="10" r="7" /><path d="m21 21-6-6" /></svg></input-icon>
						<input-icon side={Trailing}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 9 6 6 6-6" /></svg></input-icon>
					</input>
				</form>
				<input id="number" size={size} type="number" valueAsNumber={1.0} />
				<select id="select" size={size} value={choice} placeholder="Choose" disabled={disabled}><select-item value="a">Alpha</select-item><select-item value="b">Beta</select-item></select>
				<combobox id="combo" size={size} options={[{value: "a", label: "Alpha"}, {value: "b", label: "Beta"}]} disabled={disabled} />
				<label id="note-label" for="note">Note</label>
				<textarea id="note" ref={area} size={size} value={Signal.make("A paragraph whose caret must wrap at the same width as its visible text.")} disabled={disabled} />
				<textarea ref={custom} size={size} width={220} height={180} value={Signal.make("Another paragraph, in a developer sized field.")} />
				<input-otp id="otp" size={size} length={4} separator={2} value={code} onComplete={v -> completed = v} disabled={disabled} />
				<checkbox id="check" size={size} checked={checked} disabled={disabled}>Updates</checkbox>
				<radio-group id="radios" size={size} value={radio} disabled={disabled}><radio-group-item id="radio-a" value="a">Alpha</radio-group-item><radio-group-item value="b">Beta</radio-group-item></radio-group>
				<slider id="range" size={size} label="Volume" value={volume} min={0} max={1} step={0.01} disabled={disabled} />
				<slider id="vertical" size={size} orientation="vertical" value={vertical} min={0} max={1} step={0.01} disabled={disabled} />
				<badge id="badge" size={size} variant={Success}>Active</badge>
			</div>;
		});
		function settle():Void {
			for (_ in 0...3) { tree.flush(); tree.computeLayout(root.node, 800, 1600); }
		}
		function node(id:String):haxe.Int64 {
			for (at in tree.order()) { var i = Identity.of(tree, at); if (i != null && i.id == id) return at; }
			throw 'Missing $id';
		}
		function parts(at:haxe.Int64, cls:String):Array<haxe.Int64> {
			var out = [], own = Identity.of(tree, at);
			if (own != null && own.hasClass(cls)) out.push(at);
			for (child in tree.children(at)) out = out.concat(parts(child, cls));
			return out;
		}
		function bounds(at:haxe.Int64)
			return tree.getBounds(new Node(at));
		function click(at:haxe.Int64):Void {
			var b = bounds(at);
			Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
			Pointer.press(tree); Pointer.release(tree); settle();
		}
		settle();
		var n = size == Sm ? 0 : size == Md ? 1 : 2;
		var fieldHeight = [32, 40, 48][n], font = [12, 14, 16][n], marker = [14, 18, 22][n], thumb = [12, 16, 22][n];
		check('$size aligns Input, Select and Combobox', bounds(node("text")).height == fieldHeight && bounds(node("select")).height == fieldHeight
			&& bounds(node("combo")).height == fieldHeight);
		var input = ashui.ui.Input.at(tree, node("text"));
		check('$size edits in the resolved font size', input.editing.fontSize.get() == font
			&& Css.fontSize(Identity.of(tree, input.editing.text.node.id)) == font, input.editing.fontSize.get());
		var password = ashui.ui.Input.at(tree, node("password")), eye = parts(password.node.id, "ui-input-reveal")[0];
		var icon = tree.children(eye)[0];
		check('$size reveal icon fits its button', bounds(eye).height == [24, 28, 32][n] && bounds(icon).width == [14, 16, 18][n]);
		var lock = parts(password.node.id, "ui-input-icon")[0], lockBounds = bounds(lock);
		check('$size password icon stays before the text and reveal button', lockBounds.x + lockBounds.width < bounds(password.editing.text.node.id).x
			&& lockBounds.x < bounds(eye).x);
		click(eye);
		check('$size password reveal preserves focus', password.editing.revealed.get() && password.editing.interaction.focused.get());
		// Icon parts share the actual input and its editing clip, rather than wrapping another field (git-bug 27e0124).
		var search = ashui.ui.Input.at(tree, node("search")), ornaments = parts(search.node.id, "ui-input-icon");
		var leading = bounds(ornaments[0]), trailing = bounds(ornaments[1]), sb = bounds(search.node.id);
		var clip = [for (at in tree.children(search.node.id)) if (!Identity.of(tree, at).hasClass("ui-input-icon")) at][0];
		var clipBounds = bounds(clip), iconSize = [14, 16, 18][n];
		check('$size input icons fit before and after the text clip', ornaments.length == 2 && leading.width == iconSize && leading.height == iconSize
			&& trailing.width == iconSize && trailing.height == iconSize && leading.x + leading.width < clipBounds.x && clipBounds.x + clipBounds.width < trailing.x
			&& sb.height == fieldHeight);
		check('$size input icons are vertically centered', Math.abs(leading.y + leading.height / 2 - sb.y - sb.height / 2) <= 0.5
			&& Math.abs(trailing.y + trailing.height / 2 - sb.y - sb.height / 2) <= 0.5);
		var hint = bounds([for (at in Css.query(tree, search.node.id, "text")) if (ashui.ui.Text.at(at).text() == "Search projects") at][0]);
		check('$size search placeholder clears both icons', hint.x >= clipBounds.x && hint.x + hint.width <= trailing.x);
		check('$size plain inputs reserve no icon space', tree.children(node("text")).length == 1);
		click(tree.children(ornaments[0])[0]);
		check('$size clicking a decorative SVG focuses the original input', search.editing.interaction.focused.get());
		Keyboard.text(tree, "abcdefghijklmnop"); settle();
		check('$size icon input retains typing, maxlength and onInput', query.get() == "abcdefghijkl" && entered == query.get());
		Keyboard.input(tree, key(Named(Tab), Tab)); settle();
		check('$size icons add no Tab focus stops', Interaction.byId(tree, node("number")).focused.get());
		click(node("search-label"));
		check('$size labels still focus an input containing icons', search.editing.interaction.focused.get());
		query.set("A long search value that scrolls inside the text clip instead of beneath the icons"); settle();
		Keyboard.input(tree, key(Named(End), End)); settle();
		var caretX = bounds(search.editing.text.node.id).x + search.editing.stopAt(search.editing.displayCaret(), search.editing.display()).x;
		check('$size long text keeps its caret inside the remaining clip', caretX >= clipBounds.x && caretX <= clipBounds.x + clipBounds.width,
			[caretX, clipBounds]);
		Keyboard.input(tree, key(Named(Home), Home)); settle();
		check('$size Home returns to the visible start after the leading icon', search.editing.caret.get() == 0
			&& bounds(search.editing.text.node.id).x >= clipBounds.x);
		query.set("tools"); settle();
		Keyboard.input(tree, key(Named(Enter), Enter)); settle();
		check('$size icon input submits its named value through the existing form', submits == 1 && submitted == "tools");
		Keyboard.input(tree, key(Named(Escape), Escape)); settle();
		check('$size Escape clears a search with icons and preserves focus', query.get() == "" && entered == "" && search.editing.interaction.focused.get());
		Keyboard.input(tree, key(Named(Enter), Enter)); settle();
		check('$size required search with icons blocks empty form submission', submits == 1 && search.validity().valueMissing);
		var coreArea = ashui.ui.TextArea.at(area.get().node.id), edges = tree.getBox(area.get().node), b = bounds(area.get().node.id);
		check('$size Textarea keeps its id on the editable control', node("note") == area.get().node.id && Css.query(tree, root.node.id, "textarea#note.ui-textarea").length == 1);
		click(node("note-label"));
		check('$size Textarea labels focus the editing control', coreArea.editing.interaction.focused.get());
		var wrap = b.width - edges.padding[1] - edges.padding[3] - edges.border[1] - edges.border[3] - 4;
		check('$size Textarea measures its actual inner width', coreArea.editing.wrapWidth == wrap && coreArea.editing.fontSize.get() == font,
			[coreArea.editing.wrapWidth, wrap, coreArea.editing.fontSize.get()]);
		var cb = bounds(custom.get().node.id);
		check('$size Textarea preserves explicit dimensions', cb.width == 220 && cb.height == 180, cb);
		var otp = node("otp"), otpRoot = tree.ancestors(otp)[0], slots = parts(otpRoot, "ui-input-otp-slot");
		var ob = bounds(otp), outer = bounds(otpRoot);
		check('$size OTP field covers every slot', ob.x == outer.x && ob.y == outer.y && ob.width == outer.width && ob.height == [36, 44, 52][n]
			&& bounds(slots[0]).width == [32, 40, 48][n]);
		click(otp); Keyboard.text(tree, "1a2"); settle(); Keyboard.text(tree, "345"); settle();
		check('$size OTP filters, limits and completes', code.get() == "1234" && completed == "1234", [code.get(), completed]);
		var checkable = node("check"), checkRoot = tree.ancestors(checkable)[0];
		check('$size checkbox scales its mark', bounds(checkable).width == marker && bounds(parts(checkable, "check")[0]).width == [8, 12, 16][n]);
		click(parts(checkRoot, "ui-checkbox-text")[0]);
		check('$size checkbox label activates its existing input', checked.get());
		var dial = node("radio-a");
		check('$size RadioGroup passes density to its item and dot', bounds(dial).width == marker && bounds(parts(dial, "dot")[0]).width == [6, 8, 10][n]);
		Focus.set(Interaction.byId(tree, dial), true); Keyboard.input(tree, key(Named(ArrowDown), ArrowDown)); settle();
		check('$size RadioGroup retains arrow navigation', radio.get() == "b", radio.get());
		for (id in ["range", "vertical"]) {
			var range = node(id), t = bounds(parts(range, "thumb")[0]);
			check('$size $id thumb scales on both axes', t.width == thumb && t.height == thumb, t);
			var rb = bounds(range);
			Pointer.move(tree, id == "range" ? rb.x + rb.width - thumb / 2 : rb.x + rb.width / 2,
				id == "range" ? rb.y + rb.height / 2 : rb.y + thumb / 2);
			Pointer.press(tree); Pointer.release(tree); settle();
			check('$size $id seeks to the maximum using thumb bounds', (id == "range" ? volume.get() : vertical.get()) == 1);
		}
		check('$size Badge has proportional type and padding', bounds(node("badge")).height == [20, 24, 30][n], bounds(node("badge")));
		click(node("select"));
		var rows = Css.query(tree, root.node.id, "option.ui-select-item");
		check('$size Select sizes its top-layer options', rows.length == 2 && Css.fontSize(Identity.of(tree, rows[0])) == font, rows.length);
		Keyboard.input(tree, key(Named(ArrowDown), ArrowDown)); Keyboard.input(tree, key(Named(Enter), Enter)); settle();
		check('$size Select retains option selection', choice.get() == "b", choice.get());
		click(node("combo")); Keyboard.text(tree, "beta"); settle();
		var searches = Css.query(tree, root.node.id, "input.ui-command-field");
		check('$size Combobox search uses matching typography', searches.length == 1 && ashui.ui.Input.at(tree, searches[0]).editing.fontSize.get() == font,
			[searches.length, searches.length == 0 ? -1 : ashui.ui.Input.at(tree, searches[0]).editing.fontSize.get()]);
		Keyboard.input(tree, key(Named(Enter), Enter)); settle();
		disabled.set(true); settle();
		click(parts(checkRoot, "ui-checkbox-text")[0]);
		check('$size disabled controls keep their state', checked.get() && Interaction.byId(tree, node("text")).disabled.get()
			&& Interaction.byId(tree, node("combo")).disabled.get() && Interaction.byId(tree, otp).disabled.get());
		Focus.clear(tree);
		click(tree.children(ornaments[0])[0]); Keyboard.text(tree, "ignored"); settle();
		check('$size disabled icon inputs refuse focus and typing', !search.editing.interaction.focused.get() && query.get() == "");
		// CSS overrides must update caret wrapping as well as visual dimensions (e8a1b50).
		var sheet = Css.load('textarea.ui-textarea[data-size] { padding: 16px 20px; font-size: 18px; }');
		settle();
		var changedEdges = tree.getBox(area.get().node), changedBounds = bounds(area.get().node.id);
		check('$size Textarea CSS overrides update editing geometry', coreArea.editing.fontSize.get() == 18
			&& coreArea.editing.wrapWidth == changedBounds.width - changedEdges.padding[1] - changedEdges.padding[3] - changedEdges.border[1] - changedEdges.border[3] - 4);
		Css.remove(sheet); settle();
		check('$size removing CSS restores editing geometry', coreArea.editing.fontSize.get() == font && coreArea.editing.wrapWidth == wrap);
		dispose(); tree.dispose();
	}

	static function defaults():Void {
		var tree = new LayoutTree(), dispose = () -> {};
		var field = new Ref<Input>(), checkable = new Ref<Checkbox>();
		var group = new Ref<RadioGroup>(), icon = new Ref<ashui.ui.Svg>(), explicit = new Ref<ashui.ui.Svg>();
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={400} height={300} class="flex-col gap-3 items-start">
				<input ref={field} />
				<checkbox ref={checkable} />
				<radio-group ref={group} size={Lg}><radio-group-item value="a" size={Sm}>Small item</radio-group-item></radio-group>
				<svg ref={icon} id="intrinsic-icon" viewBox="0 0 24 24"><path d="M2 2h20v20H2z" /></svg>
				<svg ref={explicit} id="explicit-icon" width={32} height={28} viewBox="0 0 24 24"><path d="M2 2h20v20H2z" /></svg>
			</div>;
		});
		Identity.of(tree, icon.get().node.id).setId("intrinsic-icon");
		Identity.of(tree, explicit.get().node.id).setId("explicit-icon");
		function settle():Void { tree.flush(); tree.computeLayout(root.node, 400, 300); }
		settle();
		check('omitted size preserves medium defaults', tree.getBounds(field.get().node).height == 40 && tree.getBounds(checkable.get().node).width == 18);
		var dials = Css.query(tree, root.node.id, "input.ui-radio");
		check('radio item can override its group size', dials.length == 1 && tree.getBounds(new Node(dials[0])).width == 14);
		var sheet = Css.load('#intrinsic-icon, #explicit-icon { width: 10px; height: 12px; }');
		settle();
		check('CSS sizes an SVG without overriding explicit attributes', tree.getBounds(icon.get().node).width == 10
			&& tree.getBounds(icon.get().node).height == 12 && tree.getBounds(explicit.get().node).width == 32 && tree.getBounds(explicit.get().node).height == 28);
		Css.remove(sheet); settle();
		check('removing SVG size rules restores intrinsic dimensions', tree.getBounds(icon.get().node).width == icon.get().document.width
			&& tree.getBounds(icon.get().node).height == icon.get().document.height);
		dispose(); tree.dispose();
	}

	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		defaults();
		for (size in [Size.Sm, Size.Md, Size.Lg]) variant(size);
		Sys.println('$checks checks, $failures failures');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
