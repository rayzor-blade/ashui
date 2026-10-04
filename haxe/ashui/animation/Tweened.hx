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
	var transition:Transition;
	final output:Signal<T>;
	final lerp:(T, T, Float) -> Null<T>;
	var current:T;
	var from:T;
	var to:T;
	var elapsed = 0.0;
	var running = false;
	var stopped = false;
	var source:Null<Watch<T>> = null;
	final node:Node;
	final prop:PropertyId;
	/** The move being recorded, while a motion trace records. **/
	var track:Null<ashui.debug.MotionTrack> = null;

	function new(node:Node, prop:PropertyId, transition:Transition, output:Signal<T>, lerp:(T, T, Float) -> Null<T>) {
		this.node = node;
		this.prop = prop;
		this.transition = transition;
		this.lerp = lerp;
		this.output = output;
		current = from = to = output.get();
		node.bind(prop, Bound(cast output));
		Owner.onCleanup(() -> {
			stopped = true;
			if (track != null)
				track.finish(Interrupted);
		});
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
			traceJump(value);
			jump(value);
			return;
		}
		if (ashui.debug.MotionTrace.current != null)
			track = ashui.debug.MotionTrace.begin(Transition, node.tree, node.id, ashui.debug.PropertyNames.name(prop), text(from), text(to),
				transition.delay(), transition.seconds(), transition.curve());
		if (!running) {
			running = true;
			AnimationScheduler.main.addTicker(tick);
		}
	}

	/** Moves by `next` from the next change on, as when a stylesheet gives the property other timing. **/
	public function retime(next:Transition):Void
		transition = next;

	/** A change with no way between its values, recorded as a track that snapped: a transition declared that did not animate. **/
	function traceJump(value:T):Void {
		if (ashui.debug.MotionTrace.current == null)
			return;
		var t = ashui.debug.MotionTrace.begin(Transition, node.tree, node.id, ashui.debug.PropertyNames.name(prop), text(from), text(value),
			transition.delay(), transition.seconds(), transition.curve());
		if (t != null)
			t.finish(Snapped);
		track = null;
	}

	/** A value as the motion report writes it, read by the property's type. **/
	function text(v:T):String {
		if (v == null)
			return "none";
		var d:Dynamic = v;
		return switch prop.getDataType() {
			case TypeF32:
				Std.string(Math.round((d : Single) * 1000) / 1000);
			case TypeColor:
				var c:Color = d;
				'#${StringTools.hex(c.rgb, 6).toLowerCase()}' + (c.alpha < 1 ? '/${Math.round(c.alpha * 100) / 100}' : "");
			case TypeBrush:
				var b:Brush = d;
				b.solidRgb >= 0 ? '#${StringTools.hex(b.solidRgb, 6).toLowerCase()}' + (b.solidAlpha < 1 ? '/${Math.round(b.solidAlpha * 100) / 100}' : "") : "gradient";
			case TypeTransform:
				var t:ashui.types.Transform = d;
				var parts = [];
				if (t.translateX != 0 || t.translateY != 0)
					parts.push('translate(${Math.round(t.translateX * 10) / 10}, ${Math.round(t.translateY * 10) / 10})');
				if (t.rotate != 0)
					parts.push('rotate(${Math.round(t.rotate * 10) / 10}deg)');
				if (t.scaleX != 1 || t.scaleY != 1)
					parts.push('scale(${Math.round(t.scaleX * 1000) / 1000}, ${Math.round(t.scaleY * 1000) / 1000})');
				parts.length == 0 ? "none" : parts.join(" ");
			case TypeShadow:
				var sh:Shadow = d;
				[
					for (l in sh.layers)
						'${l[6] > 0.5 ? "inset " : ""}${l[0]} ${l[1]} ${l[2]} ${l[3]} #${StringTools.hex(Std.int(l[4]), 6).toLowerCase()}/${Math.round(l[5] * 100) / 100}'
				].join(", ");
			case _:
				Std.string(d);
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
		var eased = t >= 1 ? 1.0 : EasingTools.evaluate(transition.curve(), t);
		var value = t >= 1 ? to : lerp(from, to, eased);
		current = value;
		output.set(value);
		if (track != null) {
			track.sample(eased, t, text(value));
			if (t >= 1)
				track.finish(Completed);
		}
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
		var none = [0.0, 0, 0, 0, 0, 0, 0];
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
			// Inside or out is the target's, as CSS jumps it rather than blending.
			var inset = (i < b.layers.length ? y[6] : x[6]) > 0.5;
			if (out == null)
				out = new Shadow(l[0], l[1], l[2], rgb, alpha, l[3], inset);
			else
				out.and(l[0], l[1], l[2], rgb, alpha, l[3], inset);
		}
		return out;
	}
}
