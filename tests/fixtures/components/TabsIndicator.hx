import ashui.animation.AnimationScheduler;
import ashui.animation.LayoutAnimation;
import ashui.components.Size;
import ashui.components.Tabs;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.debug.MotionTrace;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.DisplayList;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Selected backgrounds use FLIP, retain input behavior and leave no idle ticker (5bc757e). **/
class TabsIndicator {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) { if (detail != null) Sys.println(Std.string(detail)); throw name; }
		checks++;
		Sys.println('ok   $name');
	}
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 0.05;
	static function watches():Int return [for (w in @:privateAccess Watch.bySlot) if (w != null) w].length;
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
	static function warmup() {
		var tree = new LayoutTree(), stop:Void->Void = null;
		var root = Owner.root(tree, dispose -> {
			stop = dispose;
			return <tabs><tabs-list><tabs-trigger value="a">One</tabs-trigger></tabs-list></tabs>;
		});
		tree.flush(); tree.computeLayout(root.node, 200, 40);
		stop(); tree.dispose();
	}
	static function main() {
		for (dark in [true, false]) for (size in [Size.Sm, Size.Md, Size.Lg]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			warmup();
			var baseHooks = LayoutTree.layoutHooks.length, baseWatches = watches();
			var tree = new LayoutTree(), stop:Void->Void = null;
			var value = Signal.make("a"), width = Signal.make((500 : Single)), padding = Signal.make((10 : Single));
			var changes = 0;
			var trace = MotionTrace.start();
			var root = Owner.root(tree, dispose -> {
				stop = dispose;
				return <div class="flex-col items-start gap-4" padding={padding} width={620} height={400}>
					<tabs id="main" value={value} size={size} width={width} height={100} onValueChange={_ -> changes++}>
						<tabs-list id="list" class="border-2 border-border">
							<tabs-trigger id="a" value="a" flexGrow={1}>Overview</tabs-trigger>
							<tabs-trigger id="b" value="b" flexGrow={1}>Activity</tabs-trigger>
							<tabs-trigger id="c" value="c" flexGrow={1}>Keyboard shortcuts</tabs-trigger>
							<tabs-trigger id="disabled" value="disabled" disabled={true} flexGrow={1}>Disabled</tabs-trigger>
						</tabs-list>
						<tabs-content value="a">Overview content</tabs-content>
						<tabs-content value="b">Activity content</tabs-content>
						<tabs-content value="c">Keyboard content</tabs-content>
					</tabs>
					<tabs id="other" value="x"><tabs-list><tabs-trigger value="x">First</tabs-trigger><tabs-trigger value="y">Second</tabs-trigger></tabs-list></tabs>
					<tabs id="static" value="x"><tabs-list indicator={false}><tabs-trigger value="x">Stationary</tabs-trigger><tabs-trigger value="y">Background</tabs-trigger></tabs-list></tabs>
				</div>;
			});
			function settle() { tree.flush(); tree.computeLayout(root.node, 620, 400); }
			function advance(seconds:Float) { AnimationScheduler.main.tick(seconds); settle(); }
			function node(selector:String):Node return Identity.of(tree, Css.query(tree, root.node.id, selector)[0]).node;
			function bounds(selector:String) return tree.getBounds(node(selector));
			function paint(selector:String):Null<{x:Float, y:Float, w:Float, h:Float}> {
				var at = node(selector), parent = tree.getBounds(new Node(tree.ancestors(at.id)[0]));
				var list = new DisplayList(); list.update(tree, at);
				// A subtree's display list starts in its parent's coordinates (5bc757e).
				for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_RECT) return {x: parent.x + list.get(i, 0), y: parent.y + list.get(i, 1), w: list.get(i, 2), h: list.get(i, 3)};
				return null;
			}
			function covers(selector:String):Bool {
				var a = paint("#main .ui-tabs-indicator"), b = bounds(selector);
				return a != null && near(a.x, b.x) && near(a.y, b.y) && near(a.w, b.width) && near(a.h, b.height);
			}
			function same(a:{x:Float, y:Float, w:Float, h:Float}, b:{x:Float, y:Float, w:Float, h:Float}):Bool
				return near(a.x, b.x) && near(a.y, b.y) && near(a.w, b.w) && near(a.h, b.h);
			function click(selector:String) {
				var b = bounds(selector); Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
				Pointer.press(tree); Pointer.release(tree); settle();
			}
			function press(k:window.Key, code:window.KeyCode) { Keyboard.input(tree, key(k, code)); settle(); }
			settle();
			var pill = node("#main .ui-tabs-indicator"), first = paint("#main .ui-tabs-indicator");
			check('$size first paint covers the selected tab including the tray border', covers("#a"), [first, bounds("#a")]);
			check('$size no layout animation runs on initial placement', !Lambda.exists(trace.tracks, t -> t.kind == Layout && t.node == pill.id));
			advance(1);
			var other = paint("#other .ui-tabs-indicator");
			click("#b");
			check('$size clicking a tab preserves selection and focus', value.get() == "b" && changes == 1 && Focus.of(tree).node.id == node("#b").id);
			check('$size moving background starts at its previous drawn box', same(first, paint("#main .ui-tabs-indicator")), [first, paint("#main .ui-tabs-indicator")]);
			advance(0.05);
			var halfway = paint("#main .ui-tabs-indicator"), target = bounds("#b");
			check('$size background moves between the two tabs', halfway.x > first.x && halfway.x < target.x, [first, halfway, target]);
			click("#c");
			check('$size an interrupted move continues from its visible position', same(halfway, paint("#main .ui-tabs-indicator")));
			check('$size retargeting closes the old layout trace', Lambda.exists(trace.tracks, t -> t.kind == Layout && t.node == pill.id && t.end == Interrupted));
			advance(1);
			check('$size background resizes to a longer label', covers("#c") && bounds("#c").width > first.w);
			check('$size selection keeps the same indicator node', node("#main .ui-tabs-indicator").id == pill.id);
			check('$size a second tabs list remains independent', same(other, paint("#other .ui-tabs-indicator")));
			click("#disabled"); advance(1);
			check('$size disabled tabs do not select or move the background', value.get() == "c" && changes == 2 && covers("#c"));
			Focus.set(Interaction.of(node("#c")), true); press(Named(Home), Home); advance(1);
			check('$size Home selects and reveals the first tab', value.get() == "a" && covers("#a"));
			press(Named(End), End); advance(1);
			check('$size End skips the disabled tab', value.get() == "c" && covers("#c"));
			press(Named(ArrowLeft), ArrowLeft); advance(1);
			check('$size arrows still select and move the background', value.get() == "b" && covers("#b"));
			var callbacks = changes;
			value.set("a"); settle(); advance(1);
			check('$size external value changes move the background without a callback', covers("#a") && changes == callbacks);
			width.set(560); settle(); advance(1);
			check('$size resized tabs update the selected background', covers("#a"));
			Pointer.leave(tree); Focus.clear(tree); settle(); advance(1);
			padding.set(30); settle();
			check('$size moving the parent carries the background without extra animation', covers("#a") && !AnimationScheduler.main.hasActive(),
				[paint("#main .ui-tabs-indicator"), bounds("#a"), AnimationScheduler.main.hasActive(), [for (t in trace.tracks) if (t.running) t.label + ": " + t.from + " -> " + t.to]]);
			check('$size the indicator is decorative and below the triggers', Identity.of(tree, pill.id).attribute("aria-hidden") == "true"
				&& Interaction.byId(tree, pill.id) == null && tree.children(node("#list").id)[0] == pill.id);
			var a = bounds("#a"), hits = tree.hitTest(a.x + a.width / 2, a.y + a.height / 2);
			check('$size indicator does not intercept tab hits', !Lambda.exists(hits, h -> h.id == pill.id));
			check('$size indicator opt out keeps the stationary active background', Css.query(tree, root.node.id, "#static .ui-tabs-indicator").length == 0
				&& paint("#static .ui-tabs-trigger") != null);
			value.set("missing"); settle();
			check('$size unmatched values hide the indicator', paint("#main .ui-tabs-indicator") == null);
			value.set("a"); settle(); advance(1);
			check('$size matching values restore the indicator', covers("#a"));
			check('$size settled tabs have no animation ticker', !AnimationScheduler.main.hasActive());
			value.set("c"); settle(); stop(); AnimationScheduler.main.tick(0); tree.flush();
			check('$size disposing during motion releases watches and layout hooks', LayoutTree.layoutHooks.length == baseHooks && watches() == baseWatches,
				[LayoutTree.layoutHooks.length, baseHooks, watches(), baseWatches]);
			var animated = @:privateAccess LayoutAnimation.animated.get(tree);
			check('$size disposal releases every background animation and its tree registry', animated == null
				&& !Lambda.exists(trace.tracks, t -> t.kind == Layout && t.running));
			// Existing CSS color transition disposal is tracked by 7ac6110; drain it between variants.
			AnimationScheduler.main.tick(1); tree.flush();
			trace.stop(); tree.dispose();
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
