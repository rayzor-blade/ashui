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
	static function imageSlots(list:DisplayList):Array<Int> return [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_IMAGE) Std.int(list.get(i, 40))];

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
		var bitmap = ashui.types.Bitmap.fromBytes(haxe.crypto.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="));
		Css.add(compiled);
		var imageTree = new LayoutTree();
		var images:ashui.ui.Div = Owner.root(imageTree, _ -> <div width={100} height={24}>
			<img src={bitmap} class="fit-compiled" width={24} height={24} />
			<img src={bitmap} class="fit-compiled object-cover" width={24} height={24} />
			<img src={bitmap} fit={Fill} class="fit-compiled object-cover" width={24} height={24} />
			<img src={bitmap} class="fit-compiled object-cover" fit={Fill} width={24} height={24} />
		</div>);
		layout(imageTree, images);
		var slots = imageSlots(drawn(imageTree, images));
		check("compiled object-fit reuses the existing contain bitmap slot", slots[0] == bitmap.slotFor(Contain));
		check("object utilities keep their fitting over stylesheet rules", slots[1] == bitmap.slotFor(Cover));
		check("explicit fit wins over utilities in either attribute order", slots[2] == bitmap.slotFor(Fill) && slots[3] == bitmap.slotFor(Fill));
		var image = child(imageTree, images.node);
		identity(image).setInline("object-fit", "cover");
		layout(imageTree, images);
		check("restyling object-fit selects the same decoded bitmap's cover slot", imageSlots(drawn(imageTree, images))[0] == bitmap.slotFor(Cover));
		identity(image).setInline("object-fit", null);
		Css.remove(compiled);
		layout(imageTree, images);
		check("removing object-fit restores fill without changing owned fits", imageSlots(drawn(imageTree, images))[0] == bitmap.slotFor(Fill) && imageSlots(drawn(imageTree, images))[1] == bitmap.slotFor(Cover));
		var rejected = false;
		try ashui.css.Properties.apply(image, "object-fit", "tile", context) catch (_:String) rejected = true;
		check("unsupported image modes report a diagnostic instead of silently tiling", rejected);
		images.remove();
		check("removed images leave no retained CSS image lookup", @:privateAccess ashui.ui.Image.byNode.get(image) == null);
		var disposableTree = new LayoutTree();
		var disposable = new ashui.ui.Image(bitmap, null, disposableTree);
		var disposableNode = disposable.node;
		disposableTree.dispose();
		check("disposing an unowned image tree clears its styling lookup and identity", (@:privateAccess ashui.ui.Image.byNode.get(disposableNode)) == null && Identity.of(disposableTree, disposableNode.id) == null);
		imagePositioning(bitmap, context);
		bitmap.dispose();
		backgroundImages(context);
		listAndCursor();
		ordering(context);
	}
	// git-bug: 7977648 / ABI 62aa0b0. Exercise the public CSS, HXX and input paths together.
	static function ordering(context:ashui.css.Properties.ApplyContext) {
		var compiled = ashui.css.CompiledCss.file("layout-bindings.css");
		Css.add(compiled);
		var sheet = Css.load('#order-a { order: 2; } #order-b { order: -1; }');
		var tree = new LayoutTree();
		var root:ashui.ui.Div = Owner.root(tree, _ -> <div width={120} height={30}>
			<div id="order-a" width={30} height={30} focusable={true} />
			<div id="order-b" width={30} height={30} focusable={true} />
			<div id="order-c" width={30} height={30} focusable={true} />
		</div>);
		layout(tree, root);
		var a = child(tree, root.node), b = child(tree, root.node, 1), c = child(tree, root.node, 2);
		check("CSS order sorts native flex layout stably", near(tree.getBounds(a).x, 60) && near(tree.getBounds(b).x, 0) && near(tree.getBounds(c).x, 30));
		check("CSS order preserves authored child and selector order", tree.children(root.node.id)[0] == a.id && Css.query(tree, root.node.id, "#order-a:first-child")[0] == a.id);
		ashui.input.Focus.move(tree);
		check("Tab focus follows authored order after CSS order changes", ashui.input.Interaction.of(a).focused.get());
		ashui.input.Focus.move(tree);
		check("Tab focus advances to the next authored sibling", ashui.input.Interaction.of(b).focused.get());
		identity(a).setInline("order", "-1"); layout(tree, root);
		check("equal order values retain authored ties", near(tree.getBounds(a).x, 0) && near(tree.getBounds(b).x, 30));
		identity(a).setInline("order", "2147483647");
		identity(b).setInline("order", "2147483646");
		identity(c).setInline("order", "-2147483648"); layout(tree, root);
		check("CSS order keeps full signed integer precision", near(tree.getBounds(c).x, 0) && near(tree.getBounds(b).x, 30) && near(tree.getBounds(a).x, 60));
		for (n in [a,b,c]) identity(n).setInline("order", null);
		Css.remove(sheet); layout(tree, root);
		check("removing order declarations restores authored layout", near(tree.getBounds(a).x, 0) && near(tree.getBounds(b).x, 30));
		identity(a).setClasses(["order-compiled"]); layout(tree, root);
		check("compiled order uses the same native integer field", near(tree.getBounds(a).x, 60));
		Css.remove(compiled); layout(tree, root);
		check("removing compiled order resets the native ordering", near(tree.getBounds(a).x, 0));
		identity(a).setInline("order", "1");
		identity(root.node).setInline("display", "block"); layout(tree, root);
		check("order does not reorder block children", near(tree.getBounds(a).y, 0) && near(tree.getBounds(b).y, 30));
		identity(root.node).setInline("display", "grid").setInline("grid-template-columns", "30px 30px 30px"); layout(tree, root);
		check("order sorts grid auto-placement after display changes", near(tree.getBounds(a).x, 60) && near(tree.getBounds(b).x, 0));
		identity(root.node).setInline("display", "flex").setInline("grid-template-columns", null);
		var order = Signal.make(2), direction = Signal.make(FlexDirection.Row);
		var reactive:ashui.ui.Div = Owner.root(tree, _ -> <div width={90} height={30}>
			<div order={order} flexDirection={direction} width={30} height={30} />
			<div width={30} height={30} /><div width={30} height={30} />
		</div>);
		layout(tree, reactive);
		var r = child(tree, reactive.node);
		check("HXX order signal applies its initial native value", near(tree.getBounds(r).x, 60));
		order.set(-1); direction.set(FlexDirection.Column); layout(tree, reactive);
		check("reactive order and flex direction bindings coexist", near(tree.getBounds(r).x, 0));
		identity(r).setInline("order", "100"); layout(tree, reactive);
		check("typed order ownership wins over stylesheet order", near(tree.getBounds(r).x, 0));
		var utilities:ashui.ui.Div = Owner.root(tree, _ -> <div width={90} height={30}>
			<div class="order-last hover:order-first" width={30} height={30} />
			<div class="-order-2" width={30} height={30} /><div class="order-none" width={30} height={30} />
		</div>);
		layout(tree, utilities);
		var u = child(tree, utilities.node);
		check("order utilities support positive negative and none", near(tree.getBounds(u).x, 60));
		ashui.input.Interaction.of(u).setHovered(true); layout(tree, utilities);
		check("hover order utility changes layout", near(tree.getBounds(u).x, 0));
		ashui.input.Interaction.of(u).setHovered(false); layout(tree, utilities);
		check("leaving hover restores the base order utility", near(tree.getBounds(u).x, 60));
		var overlap:ashui.ui.Div = Owner.root(tree, _ -> <div width={60} height={30}>
			<div id="order-paint-a" class="absolute" bg={ashui.types.Brush.solid(0xff0000)} order={2} width={60} height={30} />
			<div id="order-paint-b" class="absolute" bg={ashui.types.Brush.solid(0x0000ff)} width={60} height={30} />
		</div>);
		layout(tree, overlap);
		var top = child(tree, overlap.node), bottom = child(tree, overlap.node, 1), list = drawn(tree, overlap);
		var boxes = [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_RECT) i];
		check("order sorts overlapping paint and pointer hits together", list.get(boxes[boxes.length-1], 8) > list.get(boxes[0], 8) && tree.hitTest(10, 10)[0].id == top.id);
		identity(bottom).setInline("z-index", "10"); layout(tree, overlap);
		check("explicit z-index still takes precedence over order", tree.hitTest(10, 10)[0].id == bottom.id && tree.order()[1] == top.id);
		Css.add(compiled);
		var fixed:ashui.ui.Div = Owner.root(tree, _ -> <div width={100} height={50}>
			<div class="fixed-compiled" width={20} height={20} />
			<div class="fixed" left={40} top={10} width={20} height={20} />
			<div position={Fixed} left={70} width={20} height={20} />
			<div width={20} height={20} />
		</div>);
		layout(tree, fixed);
		check("compiled fixed and utility aliases use parent absolute insets", near(tree.getBounds(child(tree, fixed.node)).x, 10) && near(tree.getBounds(child(tree, fixed.node,1)).x, 40) && near(tree.getBounds(child(tree, fixed.node,2)).x, 70));
		check("fixed aliases leave normal-flow children in place", near(tree.getBounds(child(tree, fixed.node,3)).x, 0));
		Css.remove(compiled); layout(tree, fixed);
		check("fixed CSS removal restores normal flow", near(tree.getBounds(child(tree, fixed.node,3)).x, 20));
		for (value in ["1.5", "2147483648", "-2147483649", "1px", "NaN"]) {
			var rejected = false;
			try ashui.css.Properties.apply(r, "order", value, context) catch (_:String) rejected = true;
			check("invalid order reports " + value, rejected);
		}
		tree.dispose();
	}

	static function backgroundImages(context:ashui.css.Properties.ApplyContext) {
		var file = haxe.io.Path.join([Sys.getCwd(), "css-background.png"]);
		sys.io.File.saveBytes(file, haxe.crypto.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="));
		var bitmap = ashui.types.Bitmap.load(file);
		var sheet = Css.load('#background-first, #background-owned, #background-img { background: url("$file") right bottom / contain no-repeat; } #background-first { background-size: contain; background-position: right bottom; background-repeat: no-repeat; }');
		var tree = new LayoutTree();
		var root:ashui.ui.Div = Owner.root(tree, _ -> <div width={100} height={24}>
			<div id="background-first" width={24} height={24} />
			<div class="bg-no-repeat bg-right hover:bg-left" width={24} height={24} />
			<div id="background-owned" bg={ashui.types.Brush.bitmap(bitmap, Fill)} width={24} height={24} />
			<img id="background-img" class="object-none object-left" src={bitmap} width={24} height={24} />
		</div>);
		var box = child(tree, root.node), utility = child(tree, root.node, 1);
		identity(utility).setInline("background-image", 'url("$file")');
		function records():Array<Int> { layout(tree, root); var l = drawn(tree, root); return [for (r in 0...l.count) if (l.kind(r) == DisplayList.PRIM_IMAGE) r]; }
		layout(tree, root);
		var l = drawn(tree, root), rows = records();
		check("background shorthand preserves native fit, position and repeat flags", l.get(rows[0], 14) == 1 && l.get(rows[0], 4) == 1 && l.get(rows[0], 5) == 1 && l.get(rows[0], 12) == 0 && l.get(rows[0], 45) == 3);
		check("background utilities reach the existing native image record", l.get(rows[1], 4) == 1 && l.get(rows[1], 5) == 0.5 && l.get(rows[1], 12) == 0);
		check("authored background brushes keep ownership over CSS mapping", l.get(rows[2], 45) != 3 && Std.int(l.get(rows[2], 40)) == bitmap.slotFor(Fill));
		check("background and img content retain separate mappings", l.get(rows[3], 4) == 1 && l.get(rows[3], 14) == 1 && l.get(rows[4], 4) == 0 && l.get(rows[4], 14) == 4);
		var interaction = ashui.input.Interaction.of(utility);
		interaction.setHovered(true);
		layout(tree, root); l = drawn(tree, root);
		check("hover background position overrides the base utility", l.get(rows[1], 4) == 0);
		interaction.setHovered(false);
		identity(box).setInline("background-position", "12.5% -0.375px").setInline("background-repeat", "no-repeat repeat");
		layout(tree, root); l = drawn(tree, root);
		check("background longhands override shorthand without rounding", l.get(rows[0], 4) == 0.125 && l.get(rows[0], 7) == -0.375 && l.get(rows[0], 12) == 2);
		identity(box).setInline("background-position", null).setInline("background-repeat", null).setInline("background", 'url("$file")');
		layout(tree, root); l = drawn(tree, root);
		check("stronger background shorthand resets position size and repeat longhands", l.get(rows[0], 4) == 0 && l.get(rows[0], 5) == 0 && l.get(rows[0], 12) == 3 && l.get(rows[0], 14) == 3);
		identity(box).setInline("background", "red");
		layout(tree, root);
		check("replacing an image with a solid removes its image record", imageSlots(drawn(tree, root)).length == 4);
		identity(box).setInline("background", null).setInline("background-position", null).setInline("background-repeat", null);
		Css.remove(sheet);
		layout(tree, root);
		check("removing background CSS drops unowned images and keeps authored brushes", imageSlots(drawn(tree, root)).length == 3);
		var compiled = ashui.css.CompiledCss.file("layout-bindings.css");
		Css.add(compiled);
		identity(box).setId(null).setClasses(["background-compiled"]).setInline("background-image", 'url("$file")');
		layout(tree, root); l = drawn(tree, root);
		check("compiled background properties preserve repeat and fractional position", l.get(0, 4) == 0.125 && l.get(0, 7) == -0.375 && l.get(0, 12) == 2 && l.get(0, 14) == 1);
		Css.remove(compiled);
		for (v in ["space", "round", "repeat-x no-repeat"]) {
			var rejected = false;
			try ashui.css.Properties.imageRepeat(v) catch (_:String) rejected = true;
			check("unsupported background repeat is diagnosed: " + v, rejected);
		}
		root.remove(); tree.dispose(); bitmap.dispose(); sys.FileSystem.deleteFile(file);
	}

	static function imagePositioning(bitmap:ashui.types.Bitmap, context:ashui.css.Properties.ApplyContext) {
		var compiled = ashui.css.CompiledCss.file("layout-bindings.css");
		Css.add(compiled);
		var tree = new LayoutTree();
		var images:ashui.ui.Div = Owner.root(tree, _ -> <div width={160} height={24}>
			<img src={bitmap} class="position-compiled" width={24} height={24} />
			<img src={bitmap} class="position-compiled object-none object-left-top" width={24} height={24} />
			<img src={bitmap} class="object-scale-down object-right-bottom" width={24} height={24} />
			<img src={bitmap} fit={ashui.types.ObjectFit.None} objectPosition={{x: 0.125, y: 0.875, offsetX: -0.375, offsetY: 1.625}} class="object-scale-down object-left" width={24} height={24} />
			<img src={bitmap} class="object-contain object-left hover:object-cover hover:object-right" width={24} height={24} />
		</div>);
		layout(tree, images);
		var list = drawn(tree, images);
		var rows = [for (r in 0...list.count) if (list.kind(r) == DisplayList.PRIM_IMAGE) r];
		var first = rows[0], explicit = rows[3];
		check("compiled scale-down carries numeric mode while reusing the decoded fill slot", list.get(first, 14) == 5 && Std.int(list.get(first, 40)) == bitmap.slotFor(Fill));
		check("fractional object-position crosses the native ABI without integer conversion", list.get(first, 4) == 0.125 && list.get(first, 5) == 0.875);
		check("object fit and position utilities keep their local settings", list.get(rows[1], 14) == 4 && list.get(rows[1], 4) == 0 && list.get(rows[1], 5) == 0 && list.get(rows[2], 4) == 1 && list.get(rows[2], 5) == 1);
		check("authored object attributes win over utility order and retain subpixel offsets", list.get(explicit, 14) == 4 && list.get(explicit, 4) == 0.125 && list.get(explicit, 6) == -0.375 && list.get(explicit, 7) == 1.625);
		var hoverNode = child(tree, images.node, 4);
		ashui.input.Interaction.of(hoverNode).setHovered(true);
		layout(tree, images); list = drawn(tree, images);
		check("object fit and position state variants override their base utilities", list.get(rows[4], 14) == 0 && list.get(rows[4], 4) == 1);
		ashui.input.Interaction.of(hoverNode).setHovered(false);
		layout(tree, images); list = drawn(tree, images);
		check("leaving hover restores base object utilities", list.get(rows[4], 14) == 1 && list.get(rows[4], 4) == 0);
		var image = child(tree, images.node);
		identity(image).setInline("object-fit", "cover").setInline("object-position", "right 0.375px bottom 1.625px");
		layout(tree, images); list = drawn(tree, images);
		check("edge offsets use negative right/bottom lengths without rounding", list.get(first, 14) == 0 && list.get(first, 4) == 1 && list.get(first, 5) == 1 && list.get(first, 6) == -0.375 && list.get(first, 7) == -1.625);
		identity(image).setInline("object-fit", null).setInline("object-position", null);
		Css.remove(compiled); layout(tree, images); list = drawn(tree, images);
		check("removing image CSS returns to legacy centered fill records", list.get(first, 45) != 3 && Std.int(list.get(first, 40)) == bitmap.slotFor(Fill));
		check("CSS reset preserves independently authored object positioning", list.get(explicit, 4) == 0.125 && list.get(explicit, 6) == -0.375);
		identity(images.node).setInline("object-position", "12.5% 87.5%");
		layout(tree, images); list = drawn(tree, images);
		check("object-position inherits through ordinary container hosts", list.get(first, 45) == 3 && list.get(first, 4) == 0.125 && list.get(first, 5) == 0.875);
		identity(images.node).setInline("object-position", null);
		layout(tree, images); list = drawn(tree, images);
		check("removing inherited position restores legacy centered image records", list.get(first, 45) != 3);
		var p = ashui.css.Properties.imagePosition("bottom left", context);
		check("reordered axis keywords resolve to the correct pair", p.x == 0 && p.y == 1);
		p = ashui.css.Properties.imagePosition("12.5% -0.375px", context);
		check("percentage and subpixel length pairs remain distinct", p.x == 0.125 && p.y == 0 && p.offsetY == -0.375);
		for (value in ["left right", "top bottom", "auto", "left 10% bottom 2px", "calc(20% + 2px) center"]) {
			var rejected = false;
			try ashui.css.Properties.imagePosition(value, context) catch (_:String) rejected = true;
			check("invalid or unsupported object-position reports " + value, rejected);
		}
		images.remove(); tree.dispose();
	}

	static function listAndCursor() {
		var compiled = ashui.css.CompiledCss.file("layout-bindings.css");
		var sheet = Css.load('#letters { list-style-type: lower-alpha; } #bullets { list-style-type: square; }');
		var tree = new LayoutTree();
		var page:ashui.ui.Div = Owner.root(tree, _ -> <div class="flex-col" width={300} height={400}>
			<ol id="letters" start={26} type="I"><li>Twenty six</li><li value={3}>Three</li><li>Four</li></ol>
			<ul id="bullets"><li>First<ul><li>Nested</li></ul></li><li>Second</li></ul>
			<ol reversed={true} type="a"><li>Three</li><li value={8}>Eight</li><li>Seven</li></ol>
			<ol class="list-decimal-leading-zero"><li>One</li><li>Two</li></ol>
		</div>);
		layout(tree, page, 300, 400);
		var letters = child(tree, page.node), bullets = child(tree, page.node, 1), reversed = child(tree, page.node, 2), zeros = child(tree, page.node, 3);
		function item(list:Node, index:Int):ashui.ui.Li return ashui.ui.Li.at(child(tree, list, index).id);
		check("CSS markers preserve start, li value and subsequent ordinals", item(letters, 0).marker.get() == "z." && item(letters, 1).marker.get() == "c." && item(letters, 2).marker.get() == "d.");
		var nested = Css.query(tree, bullets.id, "#bullets ul > li");
		check("list-style-type reaches nested list items through the cascade", item(bullets, 0).bullet.get() == "square" && ashui.ui.Li.at(nested[nested.length - 1]).bullet.get() == "square");
		check("leading-zero utilities reuse decimal counters", item(zeros, 0).marker.get() == "01." && item(zeros, 1).marker.get() == "02.");
		check("ordered list defaults keep reversed and value behavior", item(reversed, 0).marker.get() == "c." && item(reversed, 1).marker.get() == "h." && item(reversed, 2).marker.get() == "g.");
		var first = item(letters, 0);
		identity(first.node).setInline("list-style-type", "none");
		layout(tree, page, 300, 400);
		check("an item can hide its marker and remove the gutter", first.marker.get() == "" && first.bullet.get() == "none" && near(tree.getBounds(child(tree, first.node)).width, 0));
		identity(first.node).setInline("list-style-type", "upper-roman");
		layout(tree, page, 300, 400);
		check("an individual item can override the inherited marker type", first.marker.get() == "XXVI." && item(letters, 1).marker.get() == "c.");
		identity(first.node).setInline("list-style-type", null);
		Css.remove(sheet);
		layout(tree, page, 300, 400);
		check("removing marker CSS restores the authored HTML type", first.marker.get() == "XXVI." && item(letters, 1).marker.get() == "III.");
		check("removing inherited bullet CSS restores nesting defaults", item(bullets, 0).bullet.get() == "disc" && ashui.ui.Li.at(nested[nested.length - 1]).bullet.get() == "circle");
		var extra = Owner.root(tree, _ -> <li>Six</li>);
		tree.addChild(reversed.id, extra.node.id);
		layout(tree, page, 300, 400);
		check("added items retain reversed counting and explicit value overrides", item(reversed, 0).marker.get() == "d." && item(reversed, 3).marker.get() == "f.");
		Css.add(compiled);
		identity(letters).setClasses(["markers-compiled"]);
		layout(tree, page, 300, 400);
		check("compiled list-style-type applies through the same inherited marker path", first.marker.get() == "xxvi." && item(letters, 1).marker.get() == "iii.");
		var removedId = first.node.id;
		first.remove();
		check("removed items leave the marker lookup", ashui.ui.Li.at(removedId) == null);

		var cursorTree = new LayoutTree();
		var cursors:ashui.ui.Div = Owner.root(cursorTree, _ -> <div width={200} height={80} class="cursor-pointer">
			<div width={80} height={80} class="cursor-auto"><div width={40} height={40} /></div>
			<div width={80} height={80} class="cursor-grab hover:cursor-grabbing"><div width={40} height={40} /></div>
		</div>);
		layout(cursorTree, cursors, 200, 80);
		var writes:Array<Int> = [];
		ashui.input.Cursor.bind(cursorTree, code -> writes.push(code));
		check("cursor binding initializes the platform default", writes.length == 1 && writes[0] == window.CursorIcon.Default);
		var hooks = ashui.input.Pointer.hooks.length;
		ashui.input.Pointer.move(cursorTree, 10, 10);
		check("explicit auto cursor overrides the parent's pointer cursor", writes.length == 1);
		ashui.input.Pointer.move(cursorTree, 90, 10);
		cursorTree.flush();
		check("hover cursor utilities apply through descendants", writes[writes.length - 1] == window.CursorIcon.Grabbing);
		var before = writes.length;
		ashui.input.Pointer.move(cursorTree, 92, 12);
		check("cursor handling preserves quiet hit regions and avoids repeated native writes", writes.length == before && ashui.input.Pointer.hooks.length == hooks && ashui.input.Pointer.quietRegion(cursorTree) != null);
		var target = child(cursorTree, child(cursorTree, cursors.node, 1));
		identity(target).setClasses(["cursor-compiled"]);
		cursorTree.flush();
		check("compiled CSS changes a cursor under a stationary pointer", writes[writes.length - 1] == window.CursorIcon.Crosshair);
		identity(target).setInline("cursor", "none");
		cursorTree.flush();
		check("cursor none hides the platform cursor", writes[writes.length - 1] == ashui.input.Cursor.HIDDEN);
		identity(target).setInline("cursor", null).setClasses([]);
		cursorTree.flush();
		check("removing child cursor CSS restores its inherited hover cursor", writes[writes.length - 1] == window.CursorIcon.Grabbing);
		ashui.input.Pointer.leave(cursorTree);
		check("leaving the window restores a visible default cursor", writes[writes.length - 1] == window.CursorIcon.Default);
		Css.remove(compiled);
		cursorTree.dispose();
		check("disposed cursor trees release both pointer cache and window callback", (@:privateAccess ashui.input.Cursor.sinks.get(cursorTree)) == null && !ashui.input.Pointer.at(cursorTree).inside);
		var context:ashui.css.Properties.ApplyContext = {viewportWidth: 200, viewportHeight: 100, fontSize: 16, rootFontSize: 16, currentColor: Rgba(0, 1)};
		for (entry in [{name: "cursor", value: "made-up"}, {name: "list-style-type", value: "triangle"}]) {
			var rejected = false;
			try ashui.css.Properties.apply(page.node, entry.name, entry.value, context) catch (_:String) rejected = true;
			check("invalid " + entry.name + " reports a diagnostic", rejected);
		}
	}
}
