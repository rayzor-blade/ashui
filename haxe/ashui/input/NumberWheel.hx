package ashui.input;

import ashui.layout.Node;

/** Numeric wheel stepping, shared by NumberInput and gauges (git-bug 095fab4). **/
class NumberWheel {
	/**
		One wheel line is 40 layout units, as WindowedApp normalizes it.
		Trackpad deltas accumulate until a step; reversing or leaving clears
		the remainder. Enabled controls consume vertical scrolling, including
		at their limits; disabled controls and horizontal gestures pass it on.
		An active parent scroll is captured by Pointer before it reaches
		these handlers (095fab4). No timer or frame hook is kept.
	**/
	public static function bind(node:Node, disabled:Void->Bool, step:Int->Void):Void {
		var remainder = 0.0;
		var sequence = -1;
		Interaction.of(node).onPointerLeave(_ -> remainder = 0).onWheel(e -> {
			if (sequence != e.wheelSequence) {
				sequence = e.wheelSequence;
				remainder = 0;
			}
			if (disabled()) {
				remainder = 0;
				return;
			}
			if (e.deltaY == 0 || Math.abs(e.deltaX) > Math.abs(e.deltaY))
				return;
			if (remainder * e.deltaY < 0)
				remainder = 0;
			remainder += e.deltaY;
			var steps = Std.int(remainder / 40);
			remainder -= steps * 40;
			if (steps != 0)
				step(steps);
			e.preventDefault();
			e.stopPropagation();
		});
	}
}
