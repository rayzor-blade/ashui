package ashui.animation;

import ashui.layout.IntoReactive;
import ashui.layout.Node;
import ashui.layout.PropertyId;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.Easing;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.IValue;
import ashui.types.Shadow;

/**
	One transitioned property of a node: the node is bound to a signal of
	its own, and each change of the value set on it moves that signal from
	where it is to the new value over the transition's time, ticked by
	`AnimationScheduler.main`. A change mid-flight starts from where the
	property has got to. Values with no way between them (enums, gradients,
	strings) change at once.
**/
class Tweened<T> {
	final transition:Transition;
	final output:Signal<T>;
	final lerp:(T, T, Float) -> Null<T>;
	var current:T;
	var from:T;
	var to:T;
	var elapsed = 0.0;
	var running = false;
	var stopped = false;
	var source:Null<Watch<T>> = null;

	function new(node:Node, prop:PropertyId, transition:Transition, output:Signal<T>, lerp:(T, T, Float) -> Null<T>) {
		this.transition = transition;
		this.lerp = lerp;
		this.output = output;
		current = from = to = output.get();
		node.bind(prop, Bound(cast output));
		Owner.onCleanup(() -> stopped = true);
	}

	/** A tweened binding of `prop` on `node` following `value`, or null if `prop`'s values cannot move. **/
	public static function bind(node:Node, prop:PropertyId, transition:Transition, value:IntoReactive<Dynamic>):Null<Tweened<Dynamic>> {
		// Each signal is made at its value's own type: the node binds it natively by that type.
		var tween:Tweened<Dynamic> = switch prop.getDataType() {
			case TypeF32:
				cast new Tweened<Single>(node, prop, transition, Signal.make((read(value) : Single)), (a, b, t) -> (a + (b - a) * t : Single));
			case TypeColor:
				cast new Tweened<Color>(node, prop, transition, Signal.make((read(value) : Color)), lerpColor);
			case TypeBrush:
				cast new Tweened<Brush>(node, prop, transition, Signal.make((read(value) : Brush)), lerpBrush);
			case TypeCornerRadius:
				cast new Tweened<IValue>(node, prop, transition, Signal.make((read(value) : IValue)), lerpRadius);
			case TypeShadow:
				cast new Tweened<Shadow>(node, prop, transition, Signal.make((read(value) : Shadow)), lerpShadow);
			case TypeTransform:
				cast new Tweened<ashui.types.Transform>(node, prop, transition, Signal.make((read(value) : ashui.types.Transform)),
					(a, b, t) -> a == null || b == null ? null : ashui.types.Transform.lerp(a, b, t));
			case _:
				null;
		}
		if (tween != null)
			tween.follow(value);
		return tween;
	}

	/** Moves toward `value` from now on: to a constant, or to a signal's or computed's every change. **/
	public function follow(value:IntoReactive<T>):Void {
		if (source != null) {
			source.stop();
			source = null;
		}
		switch (value : ReactiveType<T>) {
			case Const(v):
				retarget(v);
			case Bound(_) | Derived(_):
				source = new Watch(() -> read(value), v -> retarget(v), (a, b) -> a == b);
		}
	}

	static function read<T>(value:IntoReactive<T>):T {
		return switch (value : ReactiveType<T>) {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
	}

	function retarget(value:T):Void {
		if (value == to)
			return;
		// A scheme transition already animates every themed value; tweening
		// each of its frames again would trail it, so the value follows.
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme != null && theme.isAnimating()) {
			jump(value);
			return;
		}
		from = current;
		to = value;
		elapsed = -transition.delay();
		if (lerp(from, to, 0) == null) {
			jump(value);
			return;
		}
		if (!running) {
			running = true;
			AnimationScheduler.main.addTicker(tick);
		}
	}

	function jump(value:T):Void {
		current = from = to = value;
		output.set(value);
	}

	function tick(dt:Float):Bool {
		if (stopped) {
			running = false;
			return false;
		}
		elapsed += dt;

		if (elapsed < 0)
			return true;
		var duration = transition.seconds();
		var t = duration <= 0 ? 1.0 : Math.min(1, elapsed / duration);
		var value = t >= 1 ? to : lerp(from, to, EasingTools.evaluate(transition.curve(), t));
		current = value;
		output.set(value);
		if (t >= 1) {
			running = false;
			return false;
		}
		return true;
	}

	static function mix(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;

	static function mixRgb(a:Int, b:Int, t:Float):Int {
		// Clamped: a spring curve overshoots past its end.
		inline function channel(shift:Int):Int
			return Std.int(Math.max(0, Math.min(255, Math.round(mix((a >> shift) & 0xFF, (b >> shift) & 0xFF, t))))) << shift;
		return channel(16) | channel(8) | channel(0);
	}

	static function lerpColor(a:Color, b:Color, t:Float):Null<Color> {
		if (a == null || b == null)
			return null;
		return new Color(mixRgb(a.rgb, b.rgb, t), Math.max(0, Math.min(1, mix(a.alpha, b.alpha, t))));
	}

	static function lerpBrush(a:Brush, b:Brush, t:Float):Null<Brush> {
		if (a == null || b == null || a.solidRgb < 0 || b.solidRgb < 0)
			return null;
		return Brush.solid(mixRgb(a.solidRgb, b.solidRgb, t), Math.max(0, Math.min(1, mix(a.solidAlpha, b.solidAlpha, t))));
	}

	static function lerpRadius(a:IValue, b:IValue, t:Float):Null<IValue> {
		// Qualified: PropertyId's values, which share these names, are in scope.
		if (!Std.isOfType(a, ashui.types.CornerRadius) || !Std.isOfType(b, ashui.types.CornerRadius))
			return null;
		var x:ashui.types.CornerRadius = cast a, y:ashui.types.CornerRadius = cast b;
		return new ashui.types.CornerRadius(mix(x.topLeft, y.topLeft, t), mix(x.topRight, y.topRight, t), mix(x.bottomRight, y.bottomRight, t),
			mix(x.bottomLeft, y.bottomLeft, t));
	}

	/** Layer by layer, the shorter stack padded with transparent layers. **/
	static function lerpShadow(a:Shadow, b:Shadow, t:Float):Null<Shadow> {
		if (a == null || b == null)
			return null;
		var none = [0.0, 0, 0, 0, 0, 0];
		var n = Std.int(Math.max(a.layers.length, b.layers.length));
		var out:Null<Shadow> = null;
		for (i in 0...n) {
			var x = i < a.layers.length ? a.layers[i] : none;
			var y = i < b.layers.length ? b.layers[i] : none;
			// A padded layer takes the other's colour, fading only its alpha.
			var xc = i < a.layers.length ? Std.int(x[4]) : Std.int(y[4]);
			var yc = i < b.layers.length ? Std.int(y[4]) : Std.int(x[4]);
			var l = [for (k in 0...4) mix(x[k], y[k], t)];
			var rgb = mixRgb(xc, yc, t), alpha = mix(x[5], y[5], t);
			if (out == null)
				out = new Shadow(l[0], l[1], l[2], rgb, alpha, l[3]);
			else
				out.and(l[0], l[1], l[2], rgb, alpha, l[3]);
		}
		return out;
	}
}
