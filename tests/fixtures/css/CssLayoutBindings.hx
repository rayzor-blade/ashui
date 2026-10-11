import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.DisplayList;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;

/** Exercises the existing native layout fields and HTML defaults through the public styling APIs. **/
class CssLayoutBindings {
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			if (detail != null) Sys.println(Std.string(detail));
			throw name;
		}
		Sys.println('ok   $name');
	}
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 0.1;
	static function layout(tree:LayoutTree, root:Element, w = 200, h = 200) {
		tree.flush();
		tree.computeLayout(root.node, w, h);
	}
	static function child(tree:LayoutTree, node:Node, at = 0):Node return Identity.of(tree, tree.children(node.id)[at]).node;
	static function identity(node:Node):Identity return Identity.of(node.tree, node.id);
	static function drawn(tree:LayoutTree, root:Element):DisplayList {
		var list = new DisplayList();
		list.update(tree, root.node);
		return list;
	}
	static function rectangles(list:DisplayList):Int return [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_RECT) i].length;
	static function textRight(list:DisplayList):Float {
		var right = 0.0;
		for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_TEXT) right = Math.max(right, list.get(i, 0) + list.get(i, 2));
		return right;
	}
	static function glyphs(list:DisplayList):Int return [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_TEXT) i].length;

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load('
			#spacing { padding: 5% 10px 10% 15%; margin: 2%; }
			#grid { display: grid; grid-template-columns: 100px 100px; grid-template-rows: 80px; place-items: end center; }
			#grid > .end { justify-self: end; align-self: start; }
			#wrap { flex-wrap: wrap; align-content: space-between; }
			#inset { left: 50%; top: 10%; }
			#gap { column-gap: 10%; }
			#scroller { overflow: hidden auto; }
		');
		var tree = new LayoutTree();
		var root:ashui.ui.Div = Owner.root(tree, _ -> <div width={200} height={200}>
			<div id="spacing" width={100} height={100}><div width={20} height={20} /></div>
		</div>);
		layout(tree, root);
		var box = child(tree, root.node), content = child(tree, box);
		var b = tree.getBounds(box), c = tree.getBounds(content);
		check("percentage padding and margin resolve against containing width", near(b.x, 4) && near(b.y, 4) && near(c.x - b.x, 30) && near(c.y - b.y, 10));
		identity(box).setInline("padding", "4px").setInline("margin", "0");
		layout(tree, root);
		c = tree.getBounds(content);
		check("pixel spacing replaces percentage spacing on the same fields", near(c.x, 4) && near(c.y, 4));
		var padding = Signal.make((0.25 : Single));
		box.set(Prop.PaddingLeftPercent, padding);
		layout(tree, root);
		check("typed percentage ownership wins over pixel CSS", near(tree.getBounds(content).x, 50));
		padding.set(0.1);
		layout(tree, root);
		check("reactive percentage spacing retains fractional values", near(tree.getBounds(content).x, 20));
		identity(box).setInline("padding", null).setInline("margin", null);
		Css.remove(sheet);
		layout(tree, root);
		check("CSS removal resets unowned sides and keeps owned percentage side", near(tree.getBounds(content).x, 20) && near(tree.getBounds(content).y, 0));
		Css.add(sheet);

		var gridTree = new LayoutTree();
		var grid:ashui.ui.Div = Owner.root(gridTree, _ -> <div id="grid" width={200} height={80}>
			<div width={20} height={20} /><div width={20} height={20} />
		</div>);
		layout(gridTree, grid);
		var first = child(gridTree, grid.node), second = child(gridTree, grid.node, 1);
		check("place-items aligns grid children on both axes", near(gridTree.getBounds(first).x, 40) && near(gridTree.getBounds(first).y, 60));
		identity(second).setClasses(["end"]);
		layout(gridTree, grid);
		check("justify-self and align-self override container alignment", near(gridTree.getBounds(second).x, 180) && near(gridTree.getBounds(second).y, 0));
		identity(second).setInline("place-self", "auto");
		identity(second).setClasses([]);
		layout(gridTree, grid);
		check("place-self auto follows the container again", near(gridTree.getBounds(second).x, 140) && near(gridTree.getBounds(second).y, 60));
		var utility:ashui.ui.Div = Owner.root(gridTree, _ -> <div class="grid place-items-center" gridTemplateColumns={"100px 100px"} gridTemplateRows={"80px"} width={200} height={80}>
			<div width={20} height={20} class="justify-self-end" />
		</div>);
		layout(gridTree, utility);
		check("grid alignment utilities set typed native fields", near(gridTree.getBounds(child(gridTree, utility.node)).x, 80) && near(gridTree.getBounds(child(gridTree, utility.node)).y, 30));

		var wrapTree = new LayoutTree();
		var wrap:ashui.ui.Div = Owner.root(wrapTree, _ -> <div id="wrap" width={100} height={100}>
			<div width={60} height={20} /><div width={60} height={20} />
		</div>);
		layout(wrapTree, wrap);
		check("align-content distributes wrapped flex lines", near(wrapTree.getBounds(child(wrapTree, wrap.node, 1)).y, 80));
		identity(wrap.node).setInline("align-content", "center");
		layout(wrapTree, wrap);
		check("align-content updates without changing child order", near(wrapTree.getBounds(child(wrapTree, wrap.node)).y, 30) && near(wrapTree.getBounds(child(wrapTree, wrap.node, 1)).y, 50));

		var insetTree = new LayoutTree();
		var insetRoot:ashui.ui.Div = Owner.root(insetTree, _ -> <div width={201} height={101}>
			<div id="inset" position={Absolute} width={20} height={20} />
			<div class="absolute left-1/2 top-1/2" width={20} height={20} />
		</div>);
		layout(insetTree, insetRoot, 201, 101);
		check("CSS percentage insets resolve along their own axes", near(insetTree.getBounds(child(insetTree, insetRoot.node)).x, 101) && near(insetTree.getBounds(child(insetTree, insetRoot.node)).y, 10));
		check("fractional inset utilities follow native layout pixel snapping", near(insetTree.getBounds(child(insetTree, insetRoot.node, 1)).x, 101) && near(insetTree.getBounds(child(insetTree, insetRoot.node, 1)).y, 51));

		var gapTree = new LayoutTree();
		var gap:ashui.ui.Div = Owner.root(gapTree, _ -> <div id="gap" width={200} height={100}><div width={20} height={20} /><div width={20} height={20} /></div>);
		layout(gapTree, gap);
		check("percentage column-gap uses definite width", near(gapTree.getBounds(child(gapTree, gap.node, 1)).x, 40));
		identity(gap.node).setInline("gap", "0 5px");
		layout(gapTree, gap);
		check("gap shorthand replaces a percentage longhand", near(gapTree.getBounds(child(gapTree, gap.node, 1)).x, 25));

		var scrollTree = new LayoutTree();
		var scroll:ashui.ui.Div = Owner.root(scrollTree, _ -> <div id="scroller" width={80} height={80}><div width={180} height={180} flexShrink={0} /></div>);
		layout(scrollTree, scroll);
		var scrolling = ashui.input.Scroll.of(scroll.node);
		check("overflow pair scrolls only its auto axis", scrolling != null && near(scrolling.limits().x, 0) && near(scrolling.limits().y, 100));
		identity(scroll.node).setInline("overflow-x", "auto");
		layout(scrollTree, scroll);
		check("adding an overflow axis updates an existing container", near(scrolling.limits().x, 100) && near(scrolling.limits().y, 100));
		scrolling.scrollTo(90, 90);
		identity(scroll.node).setInline("overflow-y", "hidden");
		layout(scrollTree, scroll);
		check("disabling an overflow axis resets its offset", near(scrolling.x.get(), 90) && near(scrolling.y.get(), 0) && near(scrolling.limits().y, 0));
		identity(scroll.node).setInline("overflow-x", null).setInline("overflow-y", null);
		Css.remove(sheet);
		layout(scrollTree, scroll);
		check("removing overflow CSS stops scrolling on both axes", near(scrolling.limits().x, 0) && near(scrolling.limits().y, 0) && near(scrolling.x.get(), 0));
		identity(scroll.node).setInline("overflow", "auto");
		layout(scrollTree, scroll);
		check("overflow shorthand restores both axes after longhand removal", near(scrolling.limits().x, 100) && near(scrolling.limits().y, 100));
		scrolling.scrollTo(90, 90);
		var scrollNode = scroll.node;
		scroll.remove();
		check("removing a CSS scroll container releases its watches and interaction", ashui.input.Scroll.of(scrollNode) == null && ashui.input.Interaction.find(scrollNode) == null);
		var ownedScroll:ashui.ui.Div = Owner.root(scrollTree, _ -> <div id="scroller" class="overflow-auto overflow-x-hidden" width={80} height={80}>
			<div width={180} height={180} flexShrink={0} />
		</div>);
		layout(scrollTree, ownedScroll);
		var ownedScrolling = ashui.input.Scroll.of(ownedScroll.node);
		check("mixed overflow utilities configure the same native and input axes", near(ownedScrolling.limits().x, 0) && near(ownedScrolling.limits().y, 100));
		var axis = Signal.make(ashui.types.Style.Overflow.Hidden);
		Owner.root(scrollTree, _ -> {
			ownedScroll.node.set(Prop.OverflowY, axis);
			return 0;
		});
		layout(scrollTree, ownedScroll);
		check("owned reactive overflow disables CSS scrolling", near(ownedScrolling.limits().y, 0));
		axis.set(ashui.types.Style.Overflow.Scroll);
		layout(scrollTree, ownedScroll);
		check("reactive overflow enables input without another scroll container", ashui.input.Scroll.of(ownedScroll.node) == ownedScrolling && near(ownedScrolling.limits().y, 100));
		ownedScroll.node.set(Prop.OverflowY, ashui.types.Style.Overflow.Hidden);
		axis.set(ashui.types.Style.Overflow.Visible);
		layout(scrollTree, ownedScroll);
		check("replacing an overflow signal detaches its previous input binding", near(ownedScrolling.limits().y, 0));
		ownedScroll.remove();
		var compiled = ashui.css.CompiledCss.file("layout-bindings.css");
		Css.add(compiled);
		var compiledTree = new LayoutTree();
		var compiledRoot:ashui.ui.Div = Owner.root(compiledTree, _ -> <div class="bindings-compiled" width={200} height={100}>
			<div width={20} height={20} />
		</div>);
		layout(compiledTree, compiledRoot);
		check("compiled CSS forwards percentage spacing and grid alignment", near(compiledTree.getBounds(child(compiledTree, compiledRoot.node)).x, 20) && near(compiledTree.getBounds(child(compiledTree, compiledRoot.node)).y, 30));
		Css.remove(compiled);
		layout(compiledTree, compiledRoot);
		check("removing compiled layout CSS resets padding and alignment", near(compiledTree.getBounds(child(compiledTree, compiledRoot.node)).x, 0) && near(compiledTree.getBounds(child(compiledTree, compiledRoot.node)).y, 0));

		var hiddenTree = new LayoutTree();
		var hidden = Signal.make(true);
		var hiddenRoot:ashui.ui.Div = Owner.root(hiddenTree, _ -> <div width={100} height={80}>
			<div hidden={hidden} width={40} height={40} class="bg-error" />
			<div width={40} height={40} class="bg-primary" />
			<a hidden href="about:blank">Hidden link</a>
		</div>);
		layout(hiddenTree, hiddenRoot);
		var hiddenNode = child(hiddenTree, hiddenRoot.node), visibleNode = child(hiddenTree, hiddenRoot.node, 1);
		check("hidden attribute removes layout, drawing and hits", near(hiddenTree.getBounds(visibleNode).x, 0) && hiddenTree.hitTest(10, 10)[0].id == visibleNode.id && rectangles(drawn(hiddenTree, hiddenRoot)) == 1);
		hidden.set(false);
		layout(hiddenTree, hiddenRoot);
		check("reactive hidden false restores the element", identity(hiddenNode).attribute("hidden") == null && near(hiddenTree.getBounds(visibleNode).x, 40) && hiddenTree.hitTest(10, 10)[0].id == hiddenNode.id);
		hidden.set(true);
		identity(hiddenNode).setInline("display", "flex");
		layout(hiddenTree, hiddenRoot);
		check("author display overrides the hidden user-agent default", identity(hiddenNode).attribute("hidden") != null && near(hiddenTree.getBounds(visibleNode).x, 40));
		var inlineHidden = Signal.make(true);
		var paragraph:ashui.ui.Div = Owner.root(hiddenTree, _ -> <p width={400}>Before <span hidden={inlineHidden}>WIDE</span><text hidden={inlineHidden}>!!!</text> After</p>);
		layout(hiddenTree, paragraph, 400);
		var hiddenGlyphs = glyphs(drawn(hiddenTree, paragraph)), hiddenRight = textRight(drawn(hiddenTree, paragraph));
		inlineHidden.set(false);
		layout(hiddenTree, paragraph, 400);
		check("hidden inline content restores its glyphs and space", glyphs(drawn(hiddenTree, paragraph)) > hiddenGlyphs && textRight(drawn(hiddenTree, paragraph)) > hiddenRight + 20);
		inlineHidden.set(true);
		layout(hiddenTree, paragraph, 400);
		check("hidden inline content leaves no glyphs or gap", glyphs(drawn(hiddenTree, paragraph)) == hiddenGlyphs && near(textRight(drawn(hiddenTree, paragraph)), hiddenRight));
		var decorated:ashui.ui.Div = Owner.root(hiddenTree, _ -> <p width={120}>Before <code hidden={inlineHidden}>wrapped code wraps again</code> after</p>);
		layout(hiddenTree, decorated, 120);
		var plainGlyphs = glyphs(drawn(hiddenTree, decorated));
		for (i in 0...3) {
			inlineHidden.set(false);
			layout(hiddenTree, decorated, 120);
			check("showing inline code restores wrapped decoration boxes", rectangles(drawn(hiddenTree, decorated)) >= 2 && glyphs(drawn(hiddenTree, decorated)) > plainGlyphs);
			inlineHidden.set(true);
			layout(hiddenTree, decorated, 120);
			check("hiding inline code removes every copied decoration box", rectangles(drawn(hiddenTree, decorated)) == 0 && glyphs(drawn(hiddenTree, decorated)) == plainGlyphs);
		}
		var text:ashui.ui.Div = Owner.root(hiddenTree, _ -> <div class="flex-col" width={200}>
			<a>Link</a><u>Underlined</u><ins>Inserted</ins><s>Struck</s><del>Deleted</del><abbr title="Application Programming Interface">API</abbr>
		</div>);
		layout(hiddenTree, text);
		check("element defaults draw underline, strike and dotted abbreviation decorations", rectangles(drawn(hiddenTree, text)) >= 6);
		var undecorated = Css.load("a, u, ins, s, del, abbr[title] { text-decoration: none; }");
		layout(hiddenTree, text);
		check("author CSS can remove each element's default decoration", rectangles(drawn(hiddenTree, text)) == 0);
		Css.remove(undecorated);
		var context:ashui.css.Properties.ApplyContext = {viewportWidth: 200, viewportHeight: 100, fontSize: 16, rootFontSize: 16, currentColor: Rgba(0, 1)};
		for (name in ["padding-left", "row-gap"]) {
			var rejected = false;
			try ashui.css.Properties.apply(text.node, name, "-5%", context) catch (_:String) rejected = true;
			check("negative percentage " + name + " is rejected", rejected);
		}
	}
}
