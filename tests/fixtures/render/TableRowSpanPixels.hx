import ashui.components.Table;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Style;
import ashui.ui.Div;
import gpu.GpuTextureViewDescriptor;

/** Themed HXX tables: spans paint above row backgrounds and retain hover/click ancestry (471d54e / 8780d6b). **/
class TableRowSpanPixels {
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}
	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load('#paint {border:0; border-radius:0; overflow:hidden;}'
			+ '#paint td {padding:0; min-height:40px;}'
			+ '#paint tr {border:0; background:#00ff00;}'
			+ '#paint #span {background:#ff0000; min-height:100px;}'
			+ '#paint #first:hover #span {background:#ffff00;}'
			+ '#paint #upper, #paint #lower {background:#0000ff;}'
			+ '#paint #fill {background:#ffffff;}');
		var offscreen = Offscreen.create();
		for (scale in [1, 2]) {
			var tree = new LayoutTree(), clicked = 0, wrongRow = 0, dispose:Void->Void = null;
			var root:Div = Owner.root(tree, stop -> {
				dispose = stop;
				return <div width={160} height={280}>
					<table id="paint" width={160}>
						<table-header>
							<table-row id="headerFirst"><table-head id="heading" rowspan={2}>Group</table-head><table-head>Item</table-head></table-row>
							<table-row id="headerLast"><table-head>Detail</table-head></table-row>
						</table-header>
						<table-body>
							<table-row id="first" onClick={_ -> clicked++}><table-cell id="span" rowspan={2} /><table-cell id="upper" /></table-row>
							<table-row id="second" selected={true} onClick={_ -> wrongRow++}><table-cell id="lower" /></table-row>
							<table-row><table-cell id="fill" colspan={2} /></table-row>
						</table-body>
					</table>
				</div>;
			});
			offscreen.scale = scale;
			var texture = offscreen.createTexture(160 * scale, 280 * scale), view = texture.createView(new GpuTextureViewDescriptor());
			offscreen.render(root, view, 160, 280);
			function node(id:String) return Identity.of(tree, Css.query(tree, root.node.id, "#" + id)[0]).node;
			var heading = tree.getBounds(node("heading")), headerFirst = tree.getBounds(node("headerFirst")), headerLast = tree.getBounds(node("headerLast"));
			check('themed heading spans retain the minimum row height at ${scale}x', Math.abs(heading.height - headerFirst.height - headerLast.height) < 1
				&& headerFirst.height >= 40 && headerLast.height >= 40);
			var span = tree.getBounds(node("span")), lower = tree.getBounds(node("lower"));
			var x = Std.int(span.x + span.width / 2), y = Std.int(lower.y + lower.height / 2);
			function color(px:Int, py:Int):Int {
				var data = offscreen.readRgba8(texture, 160 * scale, 280 * scale);
				var i = (py * scale * 160 * scale + px * scale) * 4;
				return (data.get(i) << 16) | (data.get(i + 1) << 8) | data.get(i + 2);
			}
			check('themed spanning cell covers later selected-row backgrounds at ${scale}x', color(x, y) == 0xff0000);
			check('themed later cell skips the occupied column at ${scale}x', color(Std.int(lower.x + lower.width / 2), y) == 0x0000ff);
			var fill = tree.getBounds(node("fill"));
			check('a following colspan releases the row span at ${scale}x', color(x, Std.int(fill.y + fill.height / 2)) == 0xffffff);
			var hits = tree.hitTest(x, y);
			check('themed span hit retains its original row at ${scale}x', hits[0].id == node("span").id && hits[1].id == node("first").id);
			Pointer.move(tree, x, y); Pointer.press(tree); Pointer.release(tree);
			offscreen.render(root, view, 160, 280);
			check('the original row hover paints the entire span at ${scale}x', color(x, y) == 0xffff00 && clicked == 1 && wrongRow == 0);
			Identity.of(tree, node("span").id).setInline("display", "none");
			offscreen.render(root, view, 160, 280);
			lower = tree.getBounds(node("lower"));
			check('hidden themed spans release their columns at ${scale}x', Math.abs(lower.x - span.x) < 1);
			Pointer.leave(tree);
			dispose(); tree.dispose(); view.destroy(); texture.destroy();
		}
		Css.remove(sheet);
		check("themed rowspan CSS produces no diagnostics", Css.problems.length == 0);
	}
}
