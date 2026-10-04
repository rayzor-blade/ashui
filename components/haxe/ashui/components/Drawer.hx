package ashui.components;

import ashui.animation.AnimatedValue;
import ashui.animation.AnimationScheduler;
import ashui.components.Dialog;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.Prop;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.types.Transform;

/**
	A drawer: a panel pulled in from an edge of the window, the bottom by
	default, that a drag takes away again. It follows the pointer from its
	handle or anywhere on it but its controls; let go past a third of its
	size, or flicked toward its edge, it closes from where it is, and short
	of that it springs back. Escape and a press on the page behind close it
	too. From the bottom or top it is as tall as what it holds, its handle
	a bar across its inner edge; from the left or right, a floating panel
	for navigation, dragged by anywhere on it. Its parts are the dialog's:
	a `DrawerTrigger`, a `DrawerContent` holding a `DrawerHeader`
	(`DrawerTitle`, `DrawerDescription`), what it shows and a
	`DrawerFooter`; `DrawerClose` closes it. CSS: `.ui-drawer`
	(`[data-side]`, `[data-size]`, `[data-dragging]`, `[open]`,
	`[closing]`), `.ui-drawer-handle` and its `.ui-drawer-handle-bar`, and
	the dialog's header, title, description and footer classes inside it.
**/
class Drawer extends Dialog {}

/** A button that opens the drawer it is in. **/
class DrawerTrigger extends DialogTrigger {}

/** A button that closes the drawer it is in. **/
class DrawerClose extends DialogClose {}

class DrawerHeader extends DialogHeader {}
class DrawerTitle extends DialogTitle {}
class DrawerDescription extends DialogDescription {}
class DrawerFooter extends DialogFooter {}

/** The drawer's panel, along its edge in the top layer while open; `side` is the edge, "bottom" by default. **/
class DrawerContent extends DialogContent {
	/** How far past which, as a share of its size, a drag closes it. **/
	public static inline var DISMISS_SHARE = 1 / 3;

	/** How fast toward its edge, in layout units a second, a flick closes it however far it went. **/
	public static inline var FLICK_SPEED = 600.0;

	function side():String
		return props.side == null ? "bottom" : props.side;

	override function panelClass():String
		return "ui-drawer";

	override function placement():ashui.ui.TopLayer.Placement
		return Edge(side());

	override function backdrop():ashui.types.Brush
		return ashui.types.Brush.blur(6, 0x000000, 0.4);

	override function contents():Array<Element> {
		var handle = Library.part("ui-drawer-handle", null, null, [Library.part("ui-drawer-handle-bar", null, null, [])]);
		// On the inner edge: last from the top, first otherwise.
		return side() == "top" ? children.concat([handle]) : ([handle] : Array<Element>).concat(children);
	}

	override function render():Element {
		var el = super.render();
		var p = panel, tree = panel.tree;
		var edge = side();
		var vertical = edge == "bottom" || edge == "top";
		// Toward its edge is positive: down for the bottom, left for the left.
		var sign = edge == "bottom" || edge == "right" ? 1.0 : -1.0;
		var identity = ashui.css.Identity.of(tree, p.node.id);
		identity.setAttribute("data-side", edge);
		var dragging = Signal.make(false);
		identity.bindAttribute("data-dragging", Computed.make(() -> (dragging.get() ? "" : null : Null<String>)));
		// How far it is pulled toward its edge; it moves the layer that holds the panel, so its closing animation plays on from there.
		var offset = Signal.make(0.0);
		var moved = Computed.make(() -> {
			var o = offset.get() * sign;
			vertical ? Transform.translation(0, o) : Transform.translation(o, 0);
		});
		var held:Null<haxe.Int64> = null;
		function hold() {
			var up = tree.ancestors(p.node.id);
			if (up.length == 0 || held == up[0])
				return;
			held = up[0];
			new ashui.layout.Node(up[0]).set(Prop.Transform, moved);
		}
		var springing:Null<AnimatedValue> = null;
		var o = open;
		new Watch(() -> o.get(), v -> if (v) {
			springing = null;
			offset.set(0);
		});
		inline function along(x:Float, y:Float)
			return vertical ? y : x;
		function extent():Float {
			var r = tree.getBounds(p.node);
			return r == null ? 0.0 : vertical ? r.height : r.width;
		}
		var drag:Null<ashui.layout.LayoutTree->Void> = null;
		function stopDrag() {
			if (drag != null)
				Pointer.hooks.remove(drag);
			drag = null;
			dragging.set(false);
		}
		Interaction.of(p.node).onPointerDown(e -> {
			// Its controls keep their presses.
			var target = Interaction.byId(tree, e.target.id);
			if (target != null && target.focusable && e.target.id != p.node.id)
				return;
			stopDrag();
			hold();
			springing = null;
			var from = along(e.x, e.y), start = offset.get();
			var clock = AnimationScheduler.main;
			// The last two samples, for the speed it is let go at.
			var last = {t: clock.clock, at: start}, before = last;
			dragging.set(true);
			drag = t -> if (t == tree) {
				var at = Pointer.at(tree);
				if (at.pressed) {
					var pulled = start + (along(at.x, at.y) - from) * sign;
					// Away from its edge it gives a little, harder the further it goes.
					offset.set(pulled >= 0 ? pulled : pulled / (1 - pulled / 40));
					if (clock.clock > last.t) {
						before = last;
						last = {t: clock.clock, at: offset.get()};
					}
					return;
				}
				stopDrag();
				var speed = last.t > before.t ? (last.at - before.at) / (last.t - before.t) : 0.0;
				if (offset.get() > extent() * DISMISS_SHARE || (speed > FLICK_SPEED && offset.get() > 0)) {
					o.set(false);
					return;
				}
				var back = new AnimatedValue(clock, offset.get(), ashui.animation.SpringConfig.snappy());
				back.setTarget(0);
				springing = back;
				clock.addTicker(_ -> {
					if (springing != back)
						return false;
					offset.set(back.isAnimating() ? back.get() : 0);
					return back.isAnimating();
				});
			}
			Pointer.hooks.push(drag);
		});
		Owner.onCleanup(stopDrag);
		return el;
	}
}
