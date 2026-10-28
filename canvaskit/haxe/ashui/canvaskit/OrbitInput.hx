package ashui.canvaskit;

import ashui.animation.AnimationScheduler;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

/**
	Adds orbit-camera controls to an element. Used by `<scene-kit>`.

	Drag to rotate around the target. Shift-drag, middle-drag or right-drag
	pans the target. Scrolling zooms in or out. Rotation continues with
	inertia after release and decelerates on the animation scheduler.
	Drags remain active outside the element until the button is released.
**/
class OrbitInput {
	public final camera:OrbitCamera;

	/** Rotation in radians for a drag covering the full element height. **/
	public var dragSensitivity = Math.PI;

	/** Zoom sensitivity per wheel unit. **/
	public var zoomSensitivity = 0.0015;

	/** Fraction of rotation velocity retained per second after release. **/
	public var momentumDecay = 0.02;

	public function new(camera:OrbitCamera)
		this.camera = camera;

	/** Attaches drag and scroll controls to a node. Detaches when the current owner is disposed. **/
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
			// SceneKit's gizmos consume a press before camera input (c16e24c).
			if (p.defaultPrevented)
				return;
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
				var now = haxe.Timer.stamp(),
					dt = Math.max(now - lastAt, 1 / 240);
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
			if (p.defaultPrevented)
				return;
			camera.zoom(Math.exp(p.deltaY * zoomSensitivity));
			p.preventDefault();
		});
		Owner.onCleanup(() -> {
			stopDrag();
			spinning = false;
		});
	}
}
