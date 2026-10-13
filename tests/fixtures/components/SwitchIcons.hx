import ashui.animation.AnimationScheduler;
import ashui.components.Size;
import ashui.components.ToggleSwitch;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.DisplayList;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Knob SVG layout, real input and persistent state transitions (26f6deb). **/
class SwitchIcons {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) { if (detail != null) Sys.println(Std.string(detail)); throw name; }
		checks++;
		Sys.println('ok   $name');
	}
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 0.01;
	static function main() {
		for (dark in [true, false]) for (size in [Size.Sm, Size.Md, Size.Lg]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			var tree = new LayoutTree(), stop:Void->Void = null;
			var on = Signal.make(false), disabled = Signal.make(false), shown = Signal.make(true), changes = 0;
			var root = Owner.root(tree, dispose -> {
				stop = dispose;
				return <div class="flex-col items-start gap-4" width={300} height={180}>
					<toggle-switch id="paired" size={size} checked={on} disabled={disabled} onChange={_ -> changes++}>
						<svg class="ui-switch-icon-off" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 6 12 12M18 6 6 18" /></svg>
						<svg class="ui-switch-icon-on" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m5 12 4 4L19 6" /></svg>
					</toggle-switch>
					<toggle-switch id="single" size={size}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="7" /></svg></toggle-switch>
					<toggle-switch id="conditional" size={size}><if {shown.get()}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m5 12 4 4L19 6" /></svg></if></toggle-switch>
					<toggle-switch id="empty" size={size} />
				</div>;
			});
			function settle() for (_ in 0...3) { tree.flush(); tree.computeLayout(root.node, 300, 180); }
			function node(selector:String):Node return Identity.of(tree, Css.query(tree, root.node.id, selector)[0]).node;
			function bounds(selector:String) return tree.getBounds(node(selector));
			function opacity(selector:String):Float {
				var list = new DisplayList(); list.update(tree, node(selector));
				for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_IMAGE) return list.get(i, 15);
				return 0;
			}
			function click(selector:String) {
				var b = bounds(selector);
				Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
				Pointer.press(tree); Pointer.release(tree); settle();
			}
			function finish() { AnimationScheduler.main.tick(1); settle(); }
			settle(); finish();
			var n = size == Sm ? 0 : size == Md ? 1 : 2, iconSize = [8, 12, 16][n];
			var track = node("#paired"), thumb = node("#paired > .ui-switch-thumb"), icons = tree.children(thumb.id);
			check('$size knob mounts both inline SVGs', icons.length == 2 && Identity.of(tree, icons[0]).types.indexOf("svg") >= 0);
			for (selector in ["#paired .ui-switch-icon-off", "#paired .ui-switch-icon-on", "#single svg", "#conditional svg"]) {
				var icon = bounds(selector), knob = tree.getBounds(new Node(tree.ancestors(node(selector).id)[0]));
				check('$size $selector is sized and centered', near(icon.width, iconSize) && near(icon.height, iconSize)
					&& near(icon.x + icon.width / 2, knob.x + knob.width / 2) && near(icon.y + icon.height / 2, knob.y + knob.height / 2), [icon, knob]);
			}
			check('$size empty knobs keep their original dimensions', bounds("#empty").width == [32, 44, 52][n]
				&& bounds("#empty").height == [18, 24, 28][n] && tree.children(node("#empty > .ui-switch-thumb").id).length == 0);
			check('$size starts with only the off icon visible', near(opacity(".ui-switch-icon-off"), 1) && near(opacity(".ui-switch-icon-on"), 0));
			click(".ui-switch-icon-off");
			check('$size clicking the SVG activates the original switch once', on.get() && changes == 1 && Focus.of(tree).node == track);
			AnimationScheduler.main.tick(0.04); settle();
			var incoming = opacity(".ui-switch-icon-on"), outgoing = opacity(".ui-switch-icon-off");
			check('$size both SVGs draw during the crossfade', incoming > 0 && incoming < 1 && outgoing > 0 && outgoing < 1, [incoming, outgoing]);
			finish();
			check('$size settles with only the on icon visible', near(opacity(".ui-switch-icon-off"), 0) && near(opacity(".ui-switch-icon-on"), 1));
			check('$size state changes retain both SVG nodes', tree.children(thumb.id)[0] == icons[0] && tree.children(thumb.id)[1] == icons[1]);
			check('$size decorative knob adds no focus stop', Identity.of(tree, thumb.id).attribute("aria-hidden") == "true"
				&& Interaction.byId(tree, thumb.id) == null && Interaction.byId(tree, icons[0]) == null);
			Focus.set(Interaction.of(track), true);
			Keyboard.input(tree, Input(Code(Enter), Named(Enter), None, Standard, Pressed, false, Unavailable)); settle(); finish();
			check('$size Enter still turns the switch off', !on.get() && changes == 2 && near(opacity(".ui-switch-icon-off"), 1));
			Keyboard.input(tree, Input(Code(Space), Named(Space), None, Standard, Released, false, Unavailable)); settle(); finish();
			check('$size Space still turns the switch on', on.get() && changes == 3);
			disabled.set(true); settle(); click(".ui-switch-icon-on"); finish();
			check('$size disabled SVG clicks do not change state', on.get() && changes == 3);
			on.set(false); settle(); finish();
			check('$size external state also transitions while disabled', !on.get() && changes == 3 && near(opacity(".ui-switch-icon-off"), 1));
			shown.set(false); settle();
			check('$size conditional knob content unmounts', Css.query(tree, root.node.id, "#conditional svg").length == 0);
			shown.set(true); settle();
			check('$size conditional knob content remounts', Css.query(tree, root.node.id, "#conditional svg").length == 1 && bounds("#conditional svg").width == iconSize);
			Pointer.leave(tree); Focus.clear(tree); finish();
			check('$size settled switches leave no active animation ticker', !AnimationScheduler.main.hasActive());
			stop(); tree.flush(); tree.dispose();
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
