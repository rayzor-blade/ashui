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

/** Checks the actual HashLink layout, drawing and hits, including resets through the cascade. **/
class CssLayoutEffects {
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}

	static function layout(tree:LayoutTree, root:Element, width = 160, height = 240) {
		tree.flush();
		tree.computeLayout(root.node, width, height);
	}

	static function records(tree:LayoutTree, root:Element):DisplayList {
		var list = new DisplayList();
		list.update(tree, root.node);
		return list;
	}

	static function glyphs(list:DisplayList):Array<Int>
		return [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_TEXT) i];

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load('
			#front { z-index: 3; }
			#front.auto { z-index: auto; }
			#header { position: sticky; top: 5px; }
			#header.relative { position: relative; top: 9px; }
			#cut { white-space: nowrap; text-overflow: ellipsis; }
			#cut.clip { text-overflow: clip; }
			#clamp { line-clamp: 2; }
			#clamp.none { line-clamp: none; }
			#alias { -webkit-line-clamp: 1; }
			#rich { line-clamp: 2; }
			#rich.none { line-clamp: none; }
			#nowrap { white-space: nowrap; text-overflow: ellipsis; }
		');
		var tree = new LayoutTree();
		var root:ashui.ui.Div = Owner.root(tree, _ -> <div width={100} height={80}>
			<div id="front" position={Absolute} width={60} height={60} class="bg-error" />
			<div position={Absolute} width={60} height={60} class="bg-primary" />
		</div>);
		layout(tree, root);
		var front = tree.children(root.node.id)[0], back = tree.children(root.node.id)[1];
		var list = records(tree, root);
		check("CSS z-index changes both paint and hit order", tree.hitTest(10, 10)[0].id == front && list.get(list.count - 1, 8) > list.get(list.count - 1, 10));
		Identity.of(tree, front).setClasses(["auto"]);
		layout(tree, root);
		check("z-index auto restores document order", tree.hitTest(10, 10)[0].id == back);
		var z = Signal.make(-2);
		new Node(back).set(Prop.ZIndex, z);
		layout(tree, root);
		check("negative z-index is behind an auto sibling", tree.hitTest(10, 10)[0].id == front);
		z.set(2147483647);
		layout(tree, root);
		check("reactive z-index keeps the full signed integer", tree.hitTest(10, 10)[0].id == back);
		Css.remove(sheet);
		layout(tree, root);
		check("removing CSS leaves owned reactive z-index alone", tree.hitTest(10, 10)[0].id == back);
		Css.add(sheet);

		var scrollTree = new LayoutTree();
		var scroll:ashui.ui.Div = Owner.root(scrollTree, _ -> <div class="overflow-y-auto" width={120} height={80} flexDirection={Column}>
			<div height={30} flexShrink={0} />
			<div id="header" height={20} flexShrink={0} class="bg-primary" />
			<div height={170} flexShrink={0} class="bg-surface" />
		</div>);
		layout(scrollTree, scroll);
		var header = scrollTree.children(scroll.node.id)[1];
		check("sticky insets do not offset normal flow", scrollTree.getBounds(new Node(header)).y == 30);
		ashui.input.Scroll.of(scroll.node).scrollTo(0, 65);
		layout(scrollTree, scroll);
		check("sticky header receives hits at its held scroll position", scrollTree.hitTest(10, 10)[0].id == header);
		list = records(scrollTree, scroll);
		var blue = [for (i in 0...list.count) if (list.kind(i) == DisplayList.PRIM_RECT && list.get(i, 10) > list.get(i, 8) && list.get(i, 2) == 120) i];
		check("sticky paint follows its 5px inset", blue.length > 0 && Math.abs(list.get(blue[blue.length - 1], 1) + list.get(blue[blue.length - 1], 65) - 5) < 0.01);
		Identity.of(scrollTree, header).setClasses(["relative"]);
		layout(scrollTree, scroll);
		check("relative position removes sticking and applies the new inset", scrollTree.hitTest(10, 10)[0].id != header && scrollTree.getBounds(new Node(header)).y == 39);

		var textTree = new LayoutTree();
		var text:ashui.ui.Text = Owner.root(textTree, _ -> <text id="cut" width={100} fontSize={16}>WWWWWWWWWWWWWWWW</text>);
		layout(textTree, text);
		var cut = records(textTree, text), shown = glyphs(cut);
		check("ellipsis draws fewer glyphs inside a text node's width", shown.length < 16 && shown.length > 1 && cut.get(shown[shown.length - 1], 0) + cut.get(shown[shown.length - 1], 2) <= 102);
		Identity.of(textTree, text.node.id).setClasses(["clip"]);
		layout(textTree, text);
		check("text-overflow clip restores the complete glyph run", glyphs(records(textTree, text)).length == 16);

		var clampTree = new LayoutTree();
		var clamped:ashui.ui.Text = Owner.root(clampTree, _ -> <text id="clamp" width={100} fontSize={16} lineHeight={1.2}>
			one two three four five six seven eight nine ten eleven twelve
		</text>);
		layout(clampTree, clamped);
		var held = clampTree.getBounds(clamped.node).height;
		var shortRun = glyphs(records(clampTree, clamped)).length;
		check("CSS line-clamp sizes text to two lines", Math.abs(held - 38.4) < 1.5);
		Identity.of(clampTree, clamped.node.id).setClasses(["none"]);
		layout(clampTree, clamped);
		var natural = clampTree.getBounds(clamped.node).height;
		check("line-clamp none restores height and glyphs", natural > held * 2 && glyphs(records(clampTree, clamped)).length > shortRun);
		Identity.of(clampTree, clamped.node.id).setClasses([]);
		layout(clampTree, clamped);
		Css.remove(sheet);
		layout(clampTree, clamped);
		check("removing the rule restores the natural text height", clampTree.getBounds(clamped.node).height == natural);
		Css.add(sheet);
		var lines = Signal.make(1);
		clamped.node.set(Prop.LineClamp, lines);
		layout(clampTree, clamped);
		check("typed reactive clamp limits one line", clampTree.getBounds(clamped.node).height < 21);
		lines.set(0);
		layout(clampTree, clamped);
		check("typed zero removes the clamp", clampTree.getBounds(clamped.node).height == natural);

		var flowTree = new LayoutTree();
		var paragraph:ashui.ui.Div = Owner.root(flowTree, _ -> <p id="rich" width={140}>
			one two <strong>three four five</strong> six seven eight nine ten eleven twelve thirteen fourteen
		</p>);
		layout(flowTree, paragraph);
		var flowHeight = flowTree.getBounds(paragraph.node).height;
		var flowGlyphs = glyphs(records(flowTree, paragraph)).length;
		Identity.of(flowTree, paragraph.node.id).setClasses(["none"]);
		layout(flowTree, paragraph);
		check("rich paragraph clamp hides later lines and restores them", flowTree.getBounds(paragraph.node).height > flowHeight * 1.5 && glyphs(records(flowTree, paragraph)).length > flowGlyphs);
		var single:ashui.ui.Div = Owner.root(flowTree, _ -> <p id="nowrap" width={100}>WWWWWWWWWWWWWWWW</p>);
		layout(flowTree, single);
		check("paragraph nowrap ellipsis uses native shaping", glyphs(records(flowTree, single)).length < 16);
		var narrowGlyphs = glyphs(records(flowTree, single)).length;
		single.node.set(Prop.Width, (160 : Single));
		layout(flowTree, single);
		check("paragraph ellipsis updates when only its width grows", glyphs(records(flowTree, single)).length > narrowGlyphs);
		single.node.set(Prop.Width, (70 : Single));
		layout(flowTree, single);
		check("paragraph ellipsis updates when only its width shrinks", glyphs(records(flowTree, single)).length < narrowGlyphs);

		var aliasTree = new LayoutTree();
		var alias:ashui.ui.Text = Owner.root(aliasTree, _ -> <text id="alias" width={100} fontSize={16}>one two three four five six</text>);
		layout(aliasTree, alias);
		check("webkit line-clamp alias works", aliasTree.getBounds(alias.node).height < 21);
		var tw:ashui.ui.Text = Owner.root(aliasTree, _ -> <text class="truncate line-clamp-none" width={100}>WWWWWWWWWWWWWWWW</text>);
		layout(aliasTree, tw);
		check("truncate utility composes nowrap, ellipsis and clipping", glyphs(records(aliasTree, tw)).length < 16);
		var twParagraph:ashui.ui.Div = Owner.root(aliasTree, _ -> <p class="truncate" width={100}>WWWWWWWWWWWWWWWW</p>);
		layout(aliasTree, twParagraph);
		check("truncate utility also works on paragraph flow", glyphs(records(aliasTree, twParagraph)).length < 16);
		var typed:ashui.ui.Text = Owner.root(aliasTree, _ -> <text lineClamp={1} width={100} fontSize={16}>one two three four five six seven</text>);
		layout(aliasTree, typed);
		check("lineClamp is a first-class HXX attribute", aliasTree.getBounds(typed.node).height < 21);
		var compiled = ashui.css.CompiledCss.file("layout-effects.css");
		Css.add(compiled);
		var note:ashui.ui.Text = Owner.root(aliasTree, _ -> <text id="compiled-note" width={100}>one two three four five six seven</text>);
		layout(aliasTree, note);
		check("compiled CSS applies text limits", aliasTree.getBounds(note.node).height < 21);
		Css.remove(compiled);
		layout(aliasTree, note);
		check("compiled CSS removal restores text", aliasTree.getBounds(note.node).height > 38);

		var context:ashui.css.Properties.ApplyContext = {viewportWidth: 160, viewportHeight: 240, fontSize: 16, rootFontSize: 16, currentColor: Rgba(0x000000, 1)};
		for (bad in [
			{name: "z-index", value: "1.5"}, {name: "z-index", value: "2147483648"}, {name: "z-index", value: "-2147483649"},
			{name: "line-clamp", value: "0"}, {name: "line-clamp", value: "-1"}, {name: "line-clamp", value: "2px"},
			{name: "text-overflow", value: "fade"}
		]) {
			var rejected = false;
			try ashui.css.Properties.apply(alias.node, bad.name, bad.value, context) catch (_:Dynamic) rejected = true;
			check('${bad.name} rejects ${bad.value}', rejected);
		}
		Css.remove(sheet);
	}
}
