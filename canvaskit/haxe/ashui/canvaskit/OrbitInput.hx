package ashui.canvaskit;

import ashui.animation.AnimationScheduler;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

/**
	Moves an `OrbitCamera` as an element is used, as `<scene-kit>` does
	for its canvas. Dragging turns the camera round its target; dragging
	with Shift, or with the right or middle button, moves the target
	across the view; scrolling comes nearer or goes further. A turn let go
	of while moving carries on, slowing to a stop on the animation
	scheduler's clock. A drag follows the pointer outside the element
	until the button comes up.
**/
class OrbitInput {
	public final camera:OrbitCamera;

	/** Radians a drag across the whole height of the element turns the camera. **/
	public var dragSensitivity = Math.PI;

	/** How much one unit of the wheel comes nearer. **/
	public var zoomSensitivity = 0.0015;

	/** What a turn's speed is kept of each second after it is let go. **/
	public var momentumDecay = 0.02;

	public function new(camera:OrbitCamera)
		this.camera = camera;

	/** Moves `camera` as `node` is dragged and scrolled, until the owner it was attached under is disposed. **/
	public function attach(node:ashui.layout.Node):Void {
		var interaction = Interaction.of(node);
		var drag:Null<LayoutTree->Void> = null;
		// Radians a second of the turn when let go, measured over the last moves.
		var spinX = 0.0, spinY = 0.0, spinning = false;
		function stopDrag() {
			if (drag != null)
				Pointer.hooks.remove(drag);
			drag = null;
		}
		function coast() {
			spinning = true;
			AnimationScheduler.main.addTicker(dt -> {
				if (!spinning)
					return false;
				var keep = Math.pow(momentumDecay, dt);
				spinX *= keep;
				spinY *= keep;
				camera.orbit(spinX * dt, spinY * dt);
				spinning = Math.abs(spinX) + Math.abs(spinY) > 0.01;
				return spinning;
			});
		}
		interaction.onPointerDown(p -> {
			var tree = node.tree;
			if (tree == null)
				return;
			stopDrag();
			spinning = false;
			var panning = p.button == Right || p.button == Middle || switch p.modifiers {
				case State(shift, _): shift;
			};
			var lastX = p.x, lastY = p.y, lastAt = haxe.Timer.stamp();
			spinX = spinY = 0;
			drag = t -> if (t == tree) {
				var at = Pointer.at(tree);
				if (!at.pressed) {
					stopDrag();
					// A turn still moving when let go carries on.
					if (!panning && Math.abs(spinX) + Math.abs(spinY) > 0.05 && haxe.Timer.stamp() - lastAt < 0.1)
						coast();
					return;
				}
				var b = tree.getBounds(node);
				var size = b != null && b.height > 0 ? b.height : 1.0;
				var dx = (at.x - lastX) / size, dy = (at.y - lastY) / size;
				if (dx == 0 && dy == 0)
					return;
				var now = haxe.Timer.stamp(), dt = Math.max(now - lastAt, 1 / 240);
				if (panning)
					camera.pan(-dx, dy);
				else {
					camera.orbit(-dx * dragSensitivity, dy * dragSensitivity);
					// Smoothed, so one uneven move does not set the coast.
					spinX = spinX * 0.5 + (-dx * dragSensitivity / dt) * 0.5;
					spinY = spinY * 0.5 + (dy * dragSensitivity / dt) * 0.5;
				}
				lastX = at.x;
				lastY = at.y;
				lastAt = now;
			}
			Pointer.hooks.push(drag);
		});
		interaction.onWheel(p -> {
			spinning = false;
			camera.zoom(Math.exp(p.deltaY * zoomSensitivity));
			p.preventDefault();
		});
		Owner.onCleanup(() -> {
			stopDrag();
			spinning = false;
		});
	}
}
