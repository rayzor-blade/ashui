package ashui.canvaskit;

import ashui.animation.AnimationScheduler;
import ashui.draw.DrawContext;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Brush;
import ashui.ui.Canvas;
import ashui.ui.Component;

/** Action for left-dragging empty canvas space. **/
enum CanvasTool {
	/** Pans the viewport. **/
	Pan;

	/** Draws a box to select regions. **/
	Select;
}

typedef CanvasKitProps = {
	/** GPU drawing callback at the canvas position in paint order, respecting clipping and opacity. **/
	?paint:ashui.ui.Canvas.CanvasPaint,

	/** Enables pan, zoom, and selection input. Defaults to true. **/
	?interactive:Bool,

	/**
		Draws in content coordinates with pan and zoom already applied.
		Register interactive bounds with `kit.region(id, x, y, width, height)`.
		Later regions appear above earlier regions for hit testing.
	**/
	?draw:(ctx:DrawContext, kit:CanvasKit) -> Void,

	/** Pan and zoom state. Defaults to a new viewport with no pan and zoom 1. **/
	?viewport:Viewport2D,

	/** Canvas background. Defaults to dots. **/
	?background:IntoReactive<Background2D>,

	/** Selected region IDs. Defaults to a new selection model. **/
	?selection:Selection2D,

	/** Left-drag action on empty space. Defaults to `Pan`; Shift-drag always selects a box. **/
	?tool:IntoReactive<CanvasTool>,

	/** Snap-grid spacing in content units. Zero or omitted disables snapping. **/
	?snap:IntoReactive<Float>,

	/**
		Receives selected IDs and incremental drag distances in content units,
		snapped when `snap` is set. The application updates its own item positions.
	**/
	?onDrag:(ids:Array<String>, dx:Float, dy:Float) -> Void,

	/** Receives selected IDs when a region drag ends. **/
	?onDragEnd:(ids:Array<String>) -> Void,

	/** Receives the region ID and pointer event for a click without dragging. **/
	?onClick:(id:String, event:ashui.input.Events.PointerEvent) -> Void,

	/** Receives the hovered region ID, or null when the pointer leaves all regions. **/
	?onHover:Null<String>->Void,

	/** Requests continuous frames while true, for animated content. **/
	?animate:IntoReactive<Bool>,

	?id:String
}

/**
	An interactive 2D canvas for whiteboards, diagrams and node editors.
	Draw in content coordinates and register clickable regions with `region`.
	A `SpatialIndex` handles hit testing.

	Controls:

	- Left-drag empty space to pan, or box-select with `Select` or Shift.
	- Middle/right-drag always pans. Released pans decelerate to a stop.
	- Wheel zooms around the cursor. Shift-wheel or horizontal scrolling pans.
	- Click selects; Shift adds; Command/Control toggles selection.
	- A selection box selects every region it touches.

	The kit reports selection drags so the application can update its content.

	```haxe
	var items = [{id: "a", x: 0.0, y: 0.0}];
	<canvas-kit tool={Select} snap={8.0} widthPercent={1} heightPercent={1}
	    draw={(ctx, kit) -> for (it in items) {
	        ctx.fillRect(it.x, it.y, 80, 50,
	            Brush.solid(kit.selection.has(it.id) ? 0x3b82f6 : 0x64748b), 6);
	        kit.region(it.id, it.x, it.y, 80, 50);
	    }}
	    onDrag={(ids, dx, dy) -> for (it in items) if (ids.contains(it.id)) {
	        it.x += dx;
	        it.y += dy;
	    }} />;
	```
**/
class CanvasKit extends Component<CanvasKitProps> {
	public var viewport(default, null):Viewport2D;
	public var selection(default, null):Selection2D;

	/** Spatial index of the most recently drawn regions, in content coordinates. **/
	public final index = new SpatialIndex(100);

	/** Region ID under the pointer, or null. **/
	public var hovered(default, null):Null<String> = null;

	/** Zoom sensitivity per wheel unit. **/
	public var zoomSensitivity = 0.0015;

	/** Fraction of pan velocity retained per second after release. **/
	public var momentumDecay = 0.02;

	/** Pointer travel in screen pixels required to begin a drag. **/
	public var dragThreshold = 3.0;

	var canvas:Null<Canvas> = null;
	var width = 0.0;
	var height = 0.0;

	/** Active selection box in content coordinates and the selection to extend. **/
	var marquee:Null<{
		x0:Float,
		y0:Float,
		x1:Float,
		y1:Float,
		base:Array<String>
	}> = null;

	/** Registers interactive bounds in content coordinates. Call from `draw`; later regions take precedence. **/
	public function region(id:String, x:Float, y:Float, width:Float, height:Float):Void
		index.set(id, x, y, width, height);

	/** Requests a frame after custom `paint` data changes. **/
	public function repaint():Void {
		if (canvas != null)
			canvas.repaint();
	}

	/** Returns whether a content rectangle intersects the viewport. Use to skip offscreen work in large scenes. **/
	public function visible(x:Float, y:Float, w:Float, h:Float):Bool {
		var a = viewport.screenToContent(0, 0),
			b = viewport.screenToContent(width, height);
		return x <= b.x && x + w >= a.x && y <= b.y && y + h >= a.y;
	}

	/** Snaps a value to the grid, or returns it unchanged when snapping is disabled. **/
	public function snap(v:Float):Float {
		var s = read(props.snap, 0.0);
		return s > 0 ? Math.round(v / s) * s : v;
	}

	/** Animates the viewport to fit all registered regions, or only selected regions when `selected` is true. **/
	public function fitContent(selected = false, seconds = 0.26):Void {
		var ids = selected ? selection.ids.get() : null;
		var x0 = Math.POSITIVE_INFINITY,
			y0 = Math.POSITIVE_INFINITY,
			x1 = Math.NEGATIVE_INFINITY,
			y1 = Math.NEGATIVE_INFINITY;
		for (id in (ids != null ? ids : index.query(-1e12, -1e12, 2e12, 2e12))) {
			var r = index.get(id);
			if (r == null)
				continue;
			x0 = Math.min(x0, r.x);
			y0 = Math.min(y0, r.y);
			x1 = Math.max(x1, r.x + r.width);
			y1 = Math.max(y1, r.y + r.height);
		}
		if (x0 <= x1 && width > 0)
			viewport.fit(x0, y0, x1 - x0, y1 - y0, width, height, seconds);
	}

	/** Lazily created default background. **/
	static var defaultBackground:Null<Background2D> = null;

	function render():Element {
		viewport = props.viewport != null ? props.viewport : new Viewport2D();
		selection = props.selection != null ? props.selection : new Selection2D();
		var c = new Canvas({
			id: props.id,
			paint: props.paint,
			animate: props.animate,
			draw: ctx -> {
				width = ctx.width;
				height = ctx.height;
				var z = viewport.zoom.get();
				var a = viewport.screenToContent(0, 0), b = viewport.screenToContent(ctx.width, ctx.height);
				ctx.pushClipRect(0, 0, ctx.width, ctx.height);
				ctx.pushTransform(viewport.transform());
				var bg = read(props.background, defaultBackground != null ? defaultBackground : (defaultBackground = Background2D.dots()));
				if (bg != null)
					bg.draw(ctx, a.x, a.y, b.x, b.y, z);
				// Regions are registered afresh as the content draws.
				index.clear();
				selection.ids.get();
				if (props.draw != null)
					props.draw(ctx, this);
				drawMarquee(ctx, z);
				ctx.popTransform();
				ctx.popClip();
			}
		});
		canvas = c;
		if (props.interactive != false)
			attachInput(c.node);
		return c;
	}

	/** Draws a translucent selection box with a one-screen-pixel dashed outline. **/
	function drawMarquee(ctx:DrawContext, zoom:Float):Void {
		marqueeDrawn.get();
		var m = marquee;
		if (m == null)
			return;
		var x = Math.min(m.x0, m.x1),
			y = Math.min(m.y0, m.y1),
			w = Math.abs(m.x1 - m.x0),
			h = Math.abs(m.y1 - m.y0);
		ctx.fillRect(x, y, w, h, Brush.solid(0x3380ff, 0.12));
		ctx.strokeRect(x, y, w, h, new ashui.draw.Stroke(1 / zoom, null, null, 4, [4 / zoom, 3 / zoom]), Brush.solid(0x3380ff, 0.85));
	}

	/** Revision used to redraw changes to the selection box. **/
	final marqueeDrawn = ashui.reactive.Signal.make(0);

	function attachInput(node:ashui.layout.Node):Void {
		var interaction = Interaction.of(node);
		var follow:Null<LayoutTree->Void> = null;
		var vx = 0.0, vy = 0.0, coasting = false;
		function stopFollow() {
			if (follow != null)
				Pointer.hooks.remove(follow);
			follow = null;
		}
		function coast() {
			coasting = true;
			AnimationScheduler.main.addTicker(dt -> {
				if (!coasting)
					return false;
				var keep = Math.pow(momentumDecay, dt);
				vx *= keep;
				vy *= keep;
				viewport.panBy(vx * dt, vy * dt);
				coasting = Math.abs(vx) + Math.abs(vy) > 5;
				return coasting;
			});
		}
		// Where the pointer is in the element, from window coordinates.
		function local(tree:LayoutTree, x:Float, y:Float):{x:Float, y:Float} {
			var bounds = tree.getScrolledBounds(node);
			return bounds == null ? {x: x, y: y} : {x: x - bounds.x, y: y - bounds.y};
		}
		interaction.onPointerDown(p -> {
			var tree = node.tree;
			if (tree == null)
				return;
			stopFollow();
			coasting = false;
			viewport.stop();
			var start = {x: p.localX, y: p.localY};
			var at = viewport.screenToContent(start.x, start.y);
			var shift = p.shift, toggle = p.control || p.superKey;
			var hit = p.button == Left || p.button == null ? index.hitTest(at.x, at.y) : null;
			var tool = read(props.tool, Pan);
			var mode = if (p.button == Middle || p.button == Right) "pan" else if (hit != null) "drag" else if (shift || tool == Select) "marquee" else "pan";
			var pendingNarrow = false;
			if (mode == "drag") {
				var id = hit.id;
				if (toggle)
					selection.toggle(id);
				else if (shift)
					selection.add(id);
				else if (!selection.has(id))
					selection.select(id);
				else
					// A plain press on a selected region narrows the selection to it, if it does not become a drag.
					pendingNarrow = true;
			} else if (mode == "marquee") {
				marquee = {
					x0: at.x,
					y0: at.y,
					x1: at.x,
					y1: at.y,
					base: shift ? selection.ids.get().copy() : []
				};
				marqueeDrawn.set(marqueeDrawn.get() + 1);
			} else if (mode == "pan" && p.button == Left && tool == Pan && !shift)
				selection.clear();
			var last = start, lastAt = haxe.Timer.stamp(), moved = false;
			// Content units dragged so far and not yet reported, so snapping does not lose the remainder.
			var heldX = 0.0, heldY = 0.0, sentX = 0.0, sentY = 0.0;
			vx = vy = 0;
			follow = t -> if (t == tree) {
				var s = Pointer.at(tree);
				var now = local(tree, s.x, s.y);
				if (!s.pressed) {
					stopFollow();
					if (mode == "pan" && moved && Math.abs(vx) + Math.abs(vy) > 50 && haxe.Timer.stamp() - lastAt < 0.1)
						coast();
					if (mode == "marquee") {
						marquee = null;
						marqueeDrawn.set(marqueeDrawn.get() + 1);
					}
					if (mode == "drag") {
						if (moved && props.onDragEnd != null)
							props.onDragEnd(selection.ids.get());
						if (!moved) {
							if (pendingNarrow)
								selection.select(hit.id);
							if (props.onClick != null)
								props.onClick(hit.id, p);
						}
					}
					return;
				}
				if (!moved && Math.abs(now.x - start.x) + Math.abs(now.y - start.y) < dragThreshold)
					return;
				moved = true;
				var dx = now.x - last.x, dy = now.y - last.y;
				var t1 = haxe.Timer.stamp(),
					dt = Math.max(t1 - lastAt, 1 / 240);
				switch mode {
					case "pan":
						viewport.panBy(dx, dy);
						vx = vx * 0.5 + dx / dt * 0.5;
						vy = vy * 0.5 + dy / dt * 0.5;
					case "drag":
						var z = viewport.zoom.get();
						heldX += dx / z;
						heldY += dy / z;
						// Reported as the snapped total less what was sent, so items land on the grid however the pointer moves.
						var toX = snap(heldX) - sentX,
							toY = snap(heldY) - sentY;
						if ((toX != 0 || toY != 0) && props.onDrag != null) {
							props.onDrag(selection.ids.get(), toX, toY);
							sentX += toX;
							sentY += toY;
						}
					case "marquee":
						var c = viewport.screenToContent(now.x, now.y);
						var m = marquee;
						m.x1 = c.x;
						m.y1 = c.y;
						var inside = index.query(Math.min(m.x0, m.x1), Math.min(m.y0, m.y1), Math.abs(m.x1 - m.x0), Math.abs(m.y1 - m.y0));
						var next = m.base.copy();
						for (id in inside)
							if (next.indexOf(id) < 0)
								next.push(id);
						selection.set(next);
						marqueeDrawn.set(marqueeDrawn.get() + 1);
				}
				last = now;
				lastAt = t1;
			};
			Pointer.hooks.push(follow);
		});
		interaction.onPointerMove(p -> {
			if (follow != null)
				return;
			var at = viewport.screenToContent(p.localX, p.localY);
			var hit = index.hitTest(at.x, at.y);
			var id = hit != null ? hit.id : null;
			if (id != hovered) {
				hovered = id;
				if (props.onHover != null)
					props.onHover(id);
			}
		});
		interaction.onWheel(p -> {
			coasting = false;
			viewport.stop();
			// A sideways scroll, or Shift with the wheel, pans; the wheel alone zooms about the pointer.
			if (p.shift)
				viewport.panBy(-p.deltaY, 0);
			else if (Math.abs(p.deltaX) > Math.abs(p.deltaY))
				viewport.panBy(-p.deltaX, -p.deltaY);
			else
				viewport.zoomAt(p.localX, p.localY, Math.exp(-p.deltaY * zoomSensitivity));
			p.preventDefault();
			p.stopPropagation();
		});
		Owner.onCleanup(() -> {
			stopFollow();
			coasting = false;
		});
	}

	/** Reads a reactive prop or returns the fallback when omitted. **/
	static function read<T>(prop:Null<IntoReactive<T>>, fallback:T):T
		return prop == null ? fallback : switch (prop : ashui.layout.IntoReactive.ReactiveType<T>) {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
}
