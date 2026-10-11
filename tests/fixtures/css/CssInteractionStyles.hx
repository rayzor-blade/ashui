import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.input.Scroll as ScrollInput;
import ashui.layout.DisplayList;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;

/** CSS paint/hit changes must preserve layout and invalidate quiet pointer regions. **/
class CssInteractionStyles {
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 0.01;
	static function identity(node:Node):Identity return Identity.of(node.tree, node.id);
	static function child(tree:LayoutTree, node:Node, index = 0):Node return identityId(tree, tree.children(node.id)[index]).node;
	static function identityId(tree:LayoutTree, id:haxe.Int64):Identity return Identity.of(tree, id);
	static function layout(tree:LayoutTree, root:Element) {
		tree.flush();
		tree.computeLayout(root.node, 200, 100);
	}
	static function records(tree:LayoutTree, root:Element):DisplayList {
		var list = new DisplayList();
		list.update(tree, root.node);
		return list;
	}
	static function rects(list:DisplayList):Array<Int> return [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_RECT) i];
	static function bars(list:DisplayList, red:Bool):Array<Int> return [for (i in rects(list))
		if (list.get(i, red ? 8 : 10) > 0.99 && list.get(i, red ? 10 : 8) < 0.01) i];

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree();
		var clicked = 0;
		var root:ashui.ui.Div = Owner.root(tree, _ -> <div width={200} height={100}>
			<div width={80} height={80} class="bg-primary" onClick={_ -> clicked++} />
			<div id="overlay" position={Absolute} width={80} height={80} class="bg-error" onClick={_ -> clicked += 10}>
				<div width={30} height={30} onClick={_ -> clicked += 100} />
			</div>
		</div>);
		layout(tree, root);
		var back = child(tree, root.node), overlay = child(tree, root.node, 1), inner = child(tree, overlay);
		Pointer.move(tree, 10, 10);
		check("overlay is hit and quiet motion is cached", tree.hitTest(10, 10)[0].id == inner.id && Pointer.quietRegion(tree) != null);
		var sheet = Css.load('#overlay { pointer-events: none; }');
		tree.flush();
		check("pointer CSS invalidates the cached hit region", Pointer.quietRegion(tree) == null);
		Pointer.refresh(tree);
		Pointer.press(tree);
		Pointer.release(tree);
		check("none passes through the painted subtree to the control behind it", tree.hitTest(10, 10)[0].id == back.id && clicked == 1 && rects(records(tree, root)).length == 2);
		Css.remove(sheet);
		tree.flush();
		check("removing pointer CSS restores hits", tree.hitTest(10, 10)[0].id == inner.id);
		identity(overlay).setInline("visibility", "hidden");
		layout(tree, root);
		check("hidden suppresses painting and hits without removing layout space", rects(records(tree, root)).length == 1 && near(tree.getBounds(overlay).width, 80) && tree.hitTest(10, 10)[0].id == back.id);
		identity(overlay).setInline("visibility", "collapse");
		tree.flush();
		check("collapse currently uses the same native subtree suppression", rects(records(tree, root)).length == 1);
		identity(overlay).setInline("visibility", null);
		tree.flush();
		check("removing visibility CSS restores paint and hits", rects(records(tree, root)).length == 2 && tree.hitTest(10, 10)[0].id == inner.id);

		var visible = Signal.make(Visibility.Hidden), events = Signal.make(PointerEvents.None);
		var typed:ashui.ui.Div = Owner.root(tree, _ -> <div width={100} height={60}>
			<div id="typed" visibility={visible} pointerEvents={events} width={40} height={40} class="bg-primary" />
			<div width={40} height={40} class="bg-error" />
		</div>);
		layout(tree, typed);
		var target = child(tree, typed.node), sibling = child(tree, typed.node, 1);
		check("typed hidden keeps its sibling's layout position", rects(records(tree, typed)).length == 1 && near(tree.getBounds(sibling).x, 40));
		visible.set(Visibility.Visible);
		tree.flush();
		check("reactive visibility restores drawing while pointer none remains", rects(records(tree, typed)).length == 2 && tree.hitTest(10, 10)[0].id == typed.node.id);
		events.set(PointerEvents.Auto);
		tree.flush();
		check("reactive pointer events restores the same target", tree.hitTest(10, 10)[0].id == target.id);
		sheet = Css.load('#typed { visibility: hidden; pointer-events: none; }');
		tree.flush();
		check("typed bindings retain ownership over CSS rules", rects(records(tree, typed)).length == 2 && tree.hitTest(10, 10)[0].id == target.id);
		Css.remove(sheet);

		var utility:ashui.ui.Div = Owner.root(tree, _ -> <div width={100} height={60}>
			<div width={40} height={40} class="bg-primary invisible hover:visible pointer-events-none hover:pointer-events-auto" />
		</div>);
		layout(tree, utility);
		check("visibility and pointer utilities bind native fields", rects(records(tree, utility)).length == 0 && tree.hitTest(10, 10)[0].id == utility.node.id);
		var utilityNode = child(tree, utility.node);
		Interaction.of(utilityNode).hovered.set(true);
		tree.flush();
		check("utility state variants update paint and hits", rects(records(tree, utility)).length == 1 && tree.hitTest(10, 10)[0].id == utilityNode.id);

		var compiled = ashui.css.CompiledCss.file("interaction-styles.css");
		Css.add(compiled);
		var compiledRoot:ashui.ui.Div = Owner.root(tree, _ -> <div class="interaction-compiled" width={100} height={60}>
			<div width={40} height={40} class="bg-primary" />
		</div>);
		layout(tree, compiledRoot);
		check("compiled interaction styles suppress subtree drawing and hits", records(tree, compiledRoot).count == 0 && tree.hitTest(10, 10).length == 0);
		Css.remove(compiled);
		tree.flush();
		check("compiled interaction styles reset on removal", rects(records(tree, compiledRoot)).length == 1 && tree.hitTest(10, 10).length > 0);
		sheet = Css.load('#concealed { visibility: hidden; }');
		var paragraph:ashui.ui.Div = Owner.root(tree, _ -> <p width={200}>Before <span id="concealed">HIDDEN</span> after</p>);
		layout(tree, paragraph);
		var hiddenText = records(tree, paragraph);
		function glyphCount(list:DisplayList):Int return [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_TEXT) i].length;
		function right(list:DisplayList):Float {
			var edge = 0.0;
			for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_TEXT) edge = Math.max(edge, list.get(i, 0) + list.get(i, 2));
			return edge;
		}
		Css.remove(sheet);
		layout(tree, paragraph);
		var visibleText = records(tree, paragraph);
		check("inline visibility hides glyphs but preserves the following text's position", glyphCount(hiddenText) < glyphCount(visibleText) && near(right(hiddenText), right(visibleText)));

		Css.add(compiled);
		var scrollTree = new LayoutTree();
		var scroll:ashui.ui.Div = Owner.root(scrollTree, _ -> <div class="scroll-compiled" width={100} height={100}>
			<div width={200} height={200} flexShrink={0} />
		</div>);
		layout(scrollTree, scroll);
		var scrolling = ScrollInput.of(scroll.node);
		var list = records(scrollTree, scroll), thumb = bars(list, true), track = bars(list, false);
		check("compiled CSS draws thin red thumbs on blue tracks on both axes", thumb.length == 2 && track.length == 2
			&& near(list.get(thumb[0], 2), 2) && near(list.get(thumb[1], 3), 2));
		identity(scroll.node).setInline("scrollbar-width", "none");
		scrollTree.flush();
		check("none hides bars while wheel scrolling stays enabled", records(scrollTree, scroll).count == 0 && scrolling.scrollTo(30, 40));
		scrollTree.flush();
		check("hidden bars preserve their offsets and allocate no fade timer", near(scrolling.x.get(), 30) && near(scrolling.y.get(), 40) && (@:privateAccess scrolling.stay) == null);
		identity(scroll.node).setInline("scrollbar-width", "auto").setInline("scrollbar-color", "transparent blue");
		scrollTree.flush();
		list = records(scrollTree, scroll);
		check("a transparent thumb does not suppress an opaque track", bars(list, true).length == 0 && bars(list, false).length == 2 && near(list.get(bars(list, false)[0], 2), 4));
		identity(scroll.node).setInline("scrollbar-color", "rgba(255,0,0,0.5) transparent");
		scrollTree.flush();
		list = records(scrollTree, scroll);
		check("explicit scrollbar alpha is preserved", bars(list, true).length == 2 && bars(list, false).length == 0 && Math.abs(list.get(bars(list, true)[0], 11) - 0.5) < 0.01);
		identity(scroll.node).setInline("scrollbar-color", null).setInline("scrollbar-width", null).setInline("scrollbar-visibility", "always");
		Css.remove(compiled);
		scrollTree.flush();
		list = records(scrollTree, scroll);
		check("removing scrollbar styles restores theme color and default width", rects(list).length == 0);
		identity(scroll.node).setInline("overflow", "auto");
		layout(scrollTree, scroll);
		list = records(scrollTree, scroll);
		check("re-enabling overflow uses the default scrollbar style", rects(list).length == 2 && near(list.get(rects(list)[0], 2), 4) && bars(list, true).length == 0 && bars(list, false).length == 0);
		identity(scroll.node).setInline("scrollbar-color", "currentColor transparent").setInline("color", "#00ff00");
		scrollTree.flush();
		list = records(scrollTree, scroll);
		check("scrollbar currentColor follows the container's CSS color", rects(list).length == 2 && near(list.get(rects(list)[0], 9), 1));
		identity(scroll.node).setInline("color", "#ff0000");
		scrollTree.flush();
		check("changing currentColor updates the existing thumb watcher", bars(records(scrollTree, scroll), true).length == 2);
		identity(scroll.node).setInline("scrollbar-color", "red blue").setInline("scrollbar-visibility", "auto");
		scrollTree.flush();
		ashui.animation.AnimationScheduler.main.tick(0.3);
		scrollTree.flush();
		check("returning to auto fades both the custom thumb and track", records(scrollTree, scroll).count == 0);
		identity(scroll.node).setInline("scrollbar-visibility", "always");
		scrollTree.flush();
		scroll.remove();
		check("scroll removal releases the existing watchers", ScrollInput.of(scrolling.node) == null && (@:privateAccess scrolling.disposed));
		var inherited:ashui.ui.Div = Owner.root(scrollTree, _ -> <div id="scroll-parent" width={100} height={100}>
			<div class="overflow-auto scrollbar-none" width={100} height={100}><div width={200} height={200} flexShrink={0} /></div>
		</div>);
		sheet = Css.load('#scroll-parent { scrollbar-color: red blue; } #scroll-parent > div { scrollbar-visibility: always; }');
		layout(scrollTree, inherited);
		var inheritedNode = child(scrollTree, inherited.node);
		check("scrollbar-none utility retains scrolling without drawing bars", records(scrollTree, inherited).count == 0 && ScrollInput.of(inheritedNode).limits().y > 0);
		identity(inheritedNode).setInline("scrollbar-width", "thin");
		scrollTree.flush();
		list = records(scrollTree, inherited);
		check("scrollbar colors inherit through non-scroll hosts", bars(list, true).length == 2 && bars(list, false).length == 2);
		Css.remove(sheet);
		scrollTree.dispose();

		var context:ashui.css.Properties.ApplyContext = {viewportWidth: 200, viewportHeight: 100, fontSize: 16, rootFontSize: 16, currentColor: Rgba(0, 1)};
		for (entry in [{name: "visibility", value: "transparent"}, {name: "pointer-events", value: "visiblePainted"},
			{name: "scrollbar-width", value: "3px"}, {name: "scrollbar-color", value: "red"}]) {
			var rejected = false;
			try ashui.css.Properties.apply(root.node, entry.name, entry.value, context) catch (_:String) rejected = true;
			check("invalid " + entry.name + " reports a diagnostic", rejected);
		}
		tree.dispose();
		Css.problems.resize(0);
	}
}
