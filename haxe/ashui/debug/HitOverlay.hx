package ashui.debug;

import ashui.core.render.FrameOverlay;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.ui.Div;

/** A sampled region whose topmost native hit is `target`. **/
typedef HitTile = {
	var x:Float;
	var y:Float;
	var width:Float;
	var height:Float;
	var target:haxe.Int64;
}

/** A node in the exact native hit path, deepest first. No interaction is created to inspect it. **/
typedef HitInfo = {
	var id:haxe.Int64;
	var name:String;
	var x:Float;
	var y:Float;
	var handlers:Array<String>;
	var interaction:Bool;
	var focusable:Bool;
	var disabled:Bool;
}

/**
	Native hit testing shown over the UI: a colour per topmost target,
	including plain boxes and text, and an exact pointer path with handlers.
	The spatial map samples a bounded grid; the pointer panel is exact.
	Clips, transforms, paint order and pass-through use the native hit tester.

	Set `ASHUI_HIT_MAP=1`, or add `new HitOverlay()` to `Offscreen.overlays`.
	Like the motion overlay, its elements live in a separate tree. No move
	hook or ticker is installed: quiet native movement still coalesces, and
	the marker updates when the UI consumes a pointer position.
**/
class HitOverlay implements FrameOverlay {
	/** Requested map spacing in layout units; large frames increase it to bound work. **/
	public var sampleSize = 4;
	public var opacity = 0.14;
	public var maxAncestors = 7;
	/** The actual spacing used by the last map. **/
	public var spacing(default, null) = 4;

	static inline var MAX_SAMPLES = 65536;
	final region = new hl.Bytes(16);
	var mapped:Null<LayoutTree>;
	var revision = -1;
	var mapWidth = 0;
	var mapHeight = 0;
	var requestedSpacing = 0;
	var tiles:Array<HitTile> = [];
	var pointerX = Math.NaN;
	var pointerY = Math.NaN;
	var inside = false;
	var pressed = false;

	public function new() {}

	/** The standard overlay for this process, or null when disabled. **/
	public static function fromEnvironment():Null<HitOverlay> {
		return switch Sys.getEnv("ASHUI_HIT_MAP") {
			case "1" | "overlay": new HitOverlay();
			case _: null;
		}
	}

	/** Whether the position consumed by the dispatcher changed, without observing every native move. **/
	public function pointerChanged(tree:LayoutTree):Bool {
		var at = Pointer.at(tree);
		var changed = at.inside != inside || at.pressed != pressed || (at.inside && (at.x != pointerX || at.y != pointerY));
		pointerX = at.x;
		pointerY = at.y;
		inside = at.inside;
		pressed = at.pressed;
		return changed;
	}

	/** The exact hit path at a point, including nodes with no handlers or input state. **/
	public function inspect(tree:LayoutTree, x:Float, y:Float):Array<HitInfo> {
		return describe(tree, tree.hitTest(x, y));
	}

	function describe(tree:LayoutTree, path:Array<ashui.layout.LayoutTree.Hit>):Array<HitInfo> {
		return [for (hit in path) {
			var input = Interaction.byId(tree, hit.id);
			{
				id: hit.id,
				name: nameOf(tree, hit.id),
				x: hit.x,
				y: hit.y,
				handlers: input == null ? [] : input.handlerKinds(),
				interaction: input != null,
				focusable: input != null && input.focusable,
				disabled: input != null && input.disabled.get()
			};
		}];
	}

	/**
		A map of sample-centre hits, coalesced into rectangles. Cached until
		hitRevision or the viewport changes. Native quiet regions skip repeated
		walks between samples; curved edges retain the declared grid spacing.
	**/
	public function map(tree:LayoutTree, width:Int, height:Int):Array<HitTile> {
		if (mapped == tree && revision == tree.hitRevision && mapWidth == width && mapHeight == height && requestedSpacing == sampleSize)
			return tiles;
		mapped = tree;
		revision = tree.hitRevision;
		mapWidth = width;
		mapHeight = height;
		requestedSpacing = sampleSize;
		tiles = [];
		if (tree.root == null || width <= 0 || height <= 0)
			return tiles;
		spacing = Std.int(Math.max(1, Math.max(sampleSize, Math.ceil(Math.sqrt(width * (height : Float) / MAX_SAMPLES)))));
		while ((Math.ceil(width / spacing) : Float) * Math.ceil(height / spacing) > MAX_SAMPLES)
			spacing++;
		var columns = Math.ceil(width / spacing), rows = Math.ceil(height / spacing);
		var previous = new Map<String, HitTile>();
		var left = 0.0, top = 0.0, right = 0.0, bottom = 0.0;
		var target:Null<haxe.Int64> = null;
		var key = "";
		for (row in 0...rows) {
			var y = row * spacing, endY = Math.min(height, y + spacing);
			var cy = (y + endY) / 2;
			var runs:Array<{key:String, tile:HitTile}> = [];
			for (column in 0...columns) {
				var x = column * spacing, endX = Math.min(width, x + spacing);
				var cx = (x + endX) / 2;
				if (!(cx >= left && cx < right && cy >= top && cy < bottom)) {
					var path = tree.hitTest(cx, cy, region);
					target = path.length == 0 ? null : path[0].id;
					key = target == null ? "" : haxe.Int64.toStr(target);
					left = region.getF32(0);
					top = region.getF32(4);
					right = region.getF32(8);
					bottom = region.getF32(12);
				}
				if (target == null)
					continue;
				var last = runs.length == 0 ? null : runs[runs.length - 1];
				if (last != null && last.key == key && last.tile.x + last.tile.width == x)
					last.tile.width = endX - last.tile.x;
				else
					runs.push({key: key, tile: {x: x, y: y, width: endX - x, height: endY - y, target: target}});
			}
			var current = new Map<String, HitTile>();
			for (run in runs) {
				var k = '${run.key}:${run.tile.x}:${run.tile.width}';
				var before = previous.get(k);
				if (before != null && before.y + before.height == y) {
					before.height += run.tile.height;
					current.set(k, before);
				} else {
					tiles.push(run.tile);
					current.set(k, run.tile);
				}
			}
			previous = current;
		}
		return tiles;
	}

	public function draw(tree:LayoutTree, root:Node, width:Int, height:Int, paint:Element->Void):Void {
		var at = Pointer.at(tree);
		var path = at.inside ? describe(tree, tree.hitTest(at.x, at.y, region)) : [];
		var target = path.length == 0 ? null : path[0].id;
		// Layout is already current, while the dispatcher refreshes after the
		// frame. Read the same native region without mutating pointer/hover state.
		var quiet = at.inside && !at.pressed && Pointer.hooks.length == 0 && !Lambda.exists(path, h -> h.handlers.indexOf("pointermove") >= 0)
			&& region.getF32(0) < region.getF32(8) && region.getF32(4) < region.getF32(12)
			? {left: region.getF32(0), top: region.getF32(4), right: region.getF32(8), bottom: region.getF32(12)} : null;
		var own = new LayoutTree();
		Owner.root(own, dispose -> {
			var out:Array<Element> = [];
			for (tile in map(tree, width, height)) {
				var alpha = tile.target == root.id ? opacity * 0.3 : opacity;
				if (target != null && tile.target == target) alpha *= 2;
				out.push(MotionOverlay.box(own, tile.x, tile.y, tile.width, tile.height, colour(tile.target), alpha));
			}
			if (quiet != null) {
				var x = Math.max(0, quiet.left), y = Math.max(0, quiet.top);
				var right = Math.min(width, quiet.right), bottom = Math.min(height, quiet.bottom);
				out.push(MotionOverlay.box(own, x, y, right - x, bottom - y, null, 0, 0xffb703, 0.9));
			}
			if (at.inside) {
				out.push(MotionOverlay.box(own, at.x - 5, at.y - 0.5, 10, 1, 0xffffff));
				out.push(MotionOverlay.box(own, at.x - 0.5, at.y - 5, 1, 10, 0xffffff));
			}
			panel(own, path, quiet != null, width, out);
			paint(new Div({width: width, height: height}, out, own));
			dispose();
		});
		own.dispose();
	}

	function panel(own:LayoutTree, path:Array<HitInfo>, quiet:Bool, width:Int, out:Array<Element>):Void {
		var w = Math.min(390, Math.max(0, width - 16));
		var count = Std.int(Math.min(path.length, Math.max(1, maxAncestors)));
		var h = (count == 0 ? 90 : 75) + count * 34 + (path.length > count ? 15 : 0);
		var x = width - w - 8.0, y = 8.0;
		out.push(MotionOverlay.box(own, x, y, w, h, 0x0b0d14, 0.95, 0x4cc9f0, 0.8, 6));
		out.push(MotionOverlay.text(own, x + 10, y + 8, 'Native hit map · ${spacing}px samples', 0xffffff, 1, 12));
		out.push(MotionOverlay.text(own, x + 10, y + 26, 'Pointer path: exact · target, then ancestors', 0xaab0c0, 1, 10));
		if (path.length == 0)
			out.push(MotionOverlay.text(own, x + 10, y + 46, "No pointer target", 0xaab0c0, 1, 11));
		for (i in 0...count) {
			var hit = path[i];
			var colour = colour(hit.id);
			var label = '${i == 0 ? "target" : "ancestor"} ${hit.name} [${haxe.Int64.toStr(hit.id)}]';
			var detail = hit.handlers.length == 0 ? "no handlers" : hit.handlers.join(", ");
			if (hit.focusable) detail += " · focusable";
			if (hit.disabled) detail += " · disabled";
			detail += hit.interaction ? " · input state" : " · no input state";
			out.push(MotionOverlay.box(own, x + 10, y + 48 + i * 34, 5, 5, colour, 1, null, 0, 2.5));
			out.push(MotionOverlay.text(own, x + 23, y + 42 + i * 34, shorten(label, w - 33, 11), colour, 1, 11));
			out.push(MotionOverlay.text(own, x + 23, y + 57 + i * 34, shorten(detail, w - 33, 10), 0xd0d5e0, 1, 10));
		}
		if (path.length > count)
			out.push(MotionOverlay.text(own, x + 10, y + 44 + count * 34, '+${path.length - count} ancestors', 0xaab0c0, 1, 10));
		out.push(MotionOverlay.text(own, x + 10, y + h - 18,
			quiet ? "Amber box: cacheable quiet hit region" : "Quiet region inactive: input or exact edge testing", 0xffb703, 1, 10));
	}

	static function nameOf(tree:LayoutTree, id:haxe.Int64):String {
		var identity = Identity.of(tree, id);
		if (identity == null) return "native node";
		var name = identity.types.length == 0 ? "node" : identity.types[identity.types.length - 1];
		if (identity.id != null) name += "#" + identity.id;
		return name;
	}

	static function colour(id:haxe.Int64):Int
		return MotionOverlay.PALETTE[((id.low ^ id.high) & 0x7fffffff) % MotionOverlay.PALETTE.length];

	static function shorten(s:String, width:Float, size:Float):String {
		var length = Std.int(Math.max(0, width / (size * 0.6)));
		return s.length <= length ? s : s.substr(0, Std.int(Math.max(0, length - 1))) + "…";
	}
}
