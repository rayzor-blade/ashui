import ashui.debug.HitOverlay;
import ashui.css.Css;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Div;

class HitMapTest {
	static var failures = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		Sys.println((ok ? "ok   " : "FAIL ") + name);
		if (!ok) { failures++; if (detail != null) Sys.println(haxe.Json.stringify(detail)); }
	}

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var tree = new LayoutTree();
		var plain:Div = null, front:Div = null, circle:Div = null, pass:Div = null;
		var fired = 0;
		var root = Owner.root(tree, _ -> <div id="root" width={240} height={180} onPointerDown={_ -> fired++}>
			${plain = <div id="plain" position={Absolute} left={10} top={10} width={90} height={60} />}
			${front = <div id="front" position={Absolute} left={60} top={30} width={70} height={60} onClick={_ -> fired++} />}
			${pass = <div id="pass" position={Absolute} left={10} top={10} width={90} height={60} />}
			${circle = <div id="circle" class="[clip-path:circle()]" position={Absolute} left={150} top={20} width={80} height={80} />}
		</div>);
		Css.update();
		tree.flush();
		tree.computeLayout(root.node, 240, 180);
		tree.setPassThrough(pass.node.id, true);
		var overlay = new HitOverlay();
		var inputs = Interaction.inTree(tree).length;
		var path = overlay.inspect(tree, 20, 20);
		check("plain elements appear as exact native targets", path.length == 2 && path[0].id == plain.node.id && path[0].name == "div#plain", path);
		check("inspection distinguishes a hit from an application handler", !path[0].interaction && path[0].handlers.length == 0
			&& path[1].handlers.join(",") == "pointerdown");
		path = overlay.inspect(tree, 80, 50);
		check("overlap and pass-through follow native paint order", path[0].id == front.node.id && path[0].handlers.join(",") == "click", path);
		check("clipped corners do not become hit targets", overlay.inspect(tree, 152, 22)[0].id == root.node.id
			&& overlay.inspect(tree, 190, 60)[0].id == circle.node.id);
		var tiles = overlay.map(tree, 240, 180);
		var matches = true;
		for (y in 0...45) for (x in 0...60) {
			var cx = x * 4 + 2, cy = y * 4 + 2;
			var found = [for (tile in tiles) if (cx >= tile.x && cx < tile.x + tile.width && cy >= tile.y && cy < tile.y + tile.height) tile];
			var hits = tree.hitTest(cx, cy);
			if (found.length != 1 || found[0].target != hits[0].id) matches = false;
		}
		check("every mapped sample agrees with an exact hit through clipped edges", matches);
		check("stable maps reuse their tiles", overlay.map(tree, 240, 180) == tiles);
		tree.setPassThrough(front.node.id, true);
		var next = overlay.map(tree, 240, 180);
		check("pass-through changes invalidate the map", next != tiles && !Lambda.exists(next, tile -> tile.target == front.node.id));
		var resized = overlay.map(tree, 239, 179);
		check("viewport changes rebuild the map and clip partial edge cells", resized != next
			&& !Lambda.exists(resized, tile -> tile.x + tile.width > 239 || tile.y + tile.height > 179));
		overlay.map(tree, 16384, 16384);
		check("large viewports keep sampling bounded", Math.ceil(16384 / overlay.spacing) * Math.ceil(16384 / overlay.spacing) <= 65536);
		// Away from the circle's projected top edge, which needs exact testing.
		Pointer.move(tree, 20, 25);
		Css.update();
		tree.flush();
		Pointer.refresh(tree);
		var hooks = Pointer.hooks.length;
		var changed = overlay.pointerChanged(tree), stable = !overlay.pointerChanged(tree);
		var region = new hl.Bytes(16);
		tree.hitTest(20, 25, region);
		check("the marker observes consumed positions without continuous hooks", changed && stable
			&& Pointer.hooks.length == hooks && Pointer.quietRegion(tree) != null,
			{changed: changed, stable: stable, hooks: hooks, region: [for (i in 0...4) region.getF32(i * 4)]});
		var isolated = false;
		overlay.draw(tree, root.node, 240, 180, element -> {
			isolated = element.tree != tree;
			element.tree.flush();
			element.tree.computeLayout(element.node, 240, 180);
		});
		check("overlay rendering uses a separate tree and creates no source interactions", isolated && Interaction.inTree(tree).length == inputs && fired == 0);
		check("drawing the map preserves the source hit path and quiet cache", tree.hitTest(20, 20)[0].id == plain.node.id && Pointer.quietRegion(tree) != null);
		tree.dispose();
		check("disposed trees release their mapped tiles", overlay.map(tree, 240, 180).length == 0);
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
