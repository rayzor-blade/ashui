package ashui.animation;

import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.Easing;
import ashui.types.Transform;

/**
	Tailwind's looping animations, as signals a node's properties bind to,
	advanced by `AnimationScheduler.main` until the owner they were made
	under is disposed. Each loops forever, so a window keeps drawing while
	one is on screen.
**/
class Keyframes {
	/** `animate-spin`: a full turn a second, at an even pace. **/
	public static function spin():Signal<Transform> {
		var out = Signal.make(Transform.identity());
		loop(1, t -> out.set(Transform.rotation(360 * t)));
		return out;
	}

	/** `animate-ping`'s transform: grows to twice its size over the first three quarters of a second. **/
	public static function pingScale():Signal<Transform> {
		var out = Signal.make(Transform.identity());
		loop(1, t -> {
			var p = EasingTools.evaluate(CubicBezier(0, 0, 0.2, 1), Math.min(1, t / 0.75));
			out.set(Transform.scaling(1 + p));
		});
		return out;
	}

	/** `animate-ping`'s opacity: fades out as it grows. **/
	public static function pingOpacity():Signal<Single> {
		var out = Signal.make((1 : Single));
		loop(1, t -> out.set(1 - EasingTools.evaluate(CubicBezier(0, 0, 0.2, 1), Math.min(1, t / 0.75))));
		return out;
	}

	/** `animate-pulse`: half faded halfway through each two seconds. **/
	public static function pulse():Signal<Single> {
		var out = Signal.make((1 : Single));
		loop(2, t -> {
			var half = t < 0.5 ? t * 2 : (1 - t) * 2;
			out.set(1 - 0.5 * EasingTools.evaluate(CubicBezier(0.4, 0, 0.6, 1), half));
		});
		return out;
	}

	/** `animate-bounce`: up a quarter of its height and back each second, falling fast and landing soft. **/
	public static function bounce(node:Node):Signal<Transform> {
		var out = Signal.make(Transform.identity());
		loop(1, t -> {
			var bounds = node.tree != null ? node.tree.getBounds(node) : null;
			var rise = bounds != null ? bounds.height * 0.25 : 0;
			var y = t < 0.5 ? -rise * (1 - EasingTools.evaluate(CubicBezier(0.8, 0, 1, 1), t * 2)) : -rise * EasingTools.evaluate(CubicBezier(0, 0, 0.2,
				1), (t - 0.5) * 2);
			out.set(Transform.translation(0, y));
		});
		return out;
	}

	/** Calls `frame` with the progress through each `seconds`-long loop, 0 to 1, until the owner is disposed. **/
	static function loop(seconds:Float, frame:Float->Void):Void {
		var elapsed = 0.0;
		var stopped = false;
		Owner.onCleanup(() -> stopped = true);
		AnimationScheduler.main.addTicker(dt -> {
			if (stopped)
				return false;
			elapsed = (elapsed + dt) % seconds;
			frame(elapsed / seconds);
			return true;
		});
	}
}
