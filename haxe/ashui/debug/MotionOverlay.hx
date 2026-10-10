package ashui.debug;

import ashui.core.render.FrameOverlay;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Text;

/**
	Draws a motion trace over each frame: every element moving now, and for
	a moment after it stops, gets its box outlined in a colour of its own; a
	trail through where it was drawn each frame, a dot a frame, so the dots'
	spacing shows its easing; under it a bar for each property moving, filled
	as far as the property has got, with a tick where its curve says it
	should be by now; and above it a label per property, its time against
	its duration, `!` when `MotionCheck` finds a problem. A panel in the
	corner plots each recent track's curve as declared, in grey, and as it
	ran, a dot a frame.

	Add it to `Offscreen.overlays` (a window's renderer, or a recorder's):

	```haxe
	offscreen.overlays.push(new MotionOverlay(MotionTrace.start()));
	```
**/
@:allow(ashui.debug.HitOverlay)
@:allow(ashui.debug.InspectorOverlay)
class MotionOverlay implements FrameOverlay {
	/** A colour per track, by id. **/
	public static final PALETTE = [0xff4d6d, 0x3ddc97, 0x4cc9f0, 0xffb703, 0xb388ff, 0xff8fab, 0x80ed99, 0x00bbf9];

	/** The trace drawn; a live stream gives it a fresh one after each burst it writes out. **/
	public var trace:MotionTrace;
	/** Seconds an ended track stays drawn, fading. **/
	public var linger = 0.75;
	/** Whether the corner panel of curves is drawn, and of how many tracks at most. **/
	public var curves = true;
	public var maxCurves = 3;

	public function new(trace:MotionTrace) {
		this.trace = trace;
	}

	public function draw(tree:LayoutTree, root:Node, width:Int, height:Int, paint:Element->Void):Void {
		trace.observe(tree);
		var own = new LayoutTree();
		Owner.root(own, dispose -> {
			paint(new Div({width: width, height: height}, build(tree, width, height, own), own));
			dispose();
		});
		own.dispose();
	}

	/** The tracks drawn now: those running, and those that ended within `linger`. **/
	public function shown():Array<MotionTrack> {
		var now = MotionTrace.clock();
		return [for (t in trace.tracks) if (t.running || (t.ended != null && now - t.ended <= linger)) t];
	}

	function build(tree:LayoutTree, width:Int, height:Int, own:LayoutTree):Array<Element> {
		var out:Array<Element> = [];
		var now = MotionTrace.clock();
		var tracks = shown();
		// One outline per element, its tracks' bars stacked under it and labels over it.
		var byNode = new Map<String, Array<MotionTrack>>();
		var order = [];
		for (t in tracks) {
			if (t.tree != tree || t.node == null || t.lastRect() == null)
				continue;
			var key = haxe.Int64.toStr(t.node);
			if (!byNode.exists(key)) {
				byNode.set(key, []);
				order.push(key);
			}
			byNode.get(key).push(t);
		}
		// Labels placed so far, so one over a nested element's moves up clear of its parent's.
		var placed:Array<{x:Float, y:Float, w:Float}> = [];
		for (key in order) {
			var group = byNode.get(key);
			var lead = group[0];
			var r = lead.lastRect();
			var colour = PALETTE[(lead.id - 1) % PALETTE.length];
			var fade = fadeOf(lead, now);
			out.push(box(own, r.x, r.y, r.w, r.h, null, 0, colour, 0.9 * fade));
			for (t in group)
				trail(own, t, out, now);
			// A bar per property, four at most; one label for the element, its first property and how many more.
			var barWidth = Math.max(40.0, Math.min(r.w, 120.0));
			for (i in 0...Std.int(Math.min(group.length, 4))) {
				var t = group[i];
				bar(own, t, r.x, r.y + r.h + 3 + i * 5, barWidth, PALETTE[(t.id - 1) % PALETTE.length], fadeOf(t, now), now, out);
			}
			var flagged = Lambda.exists(group, t -> MotionCheck.check(t, trace).issues.length > 0);
			var elapsed = Math.max(0, (lead.running ? now : lead.ended) - lead.began - lead.delay);
			var time = lead.kind == Spring ? MotionCheck.ms(elapsed) : '${MotionCheck.ms(Math.min(elapsed, lead.duration))}/${MotionCheck.ms(lead.duration)}';
			var more = group.length > 1 ? ' +${group.length - 1}' : "";
			var text = '#${lead.id} ${lead.property}$more $time${flagged ? " !" : ""}';
			// About the width ten-unit text takes.
			var lw = text.length * 5.6 + 6;
			// Above it, higher and higher, then under its bars when the top of the frame is reached.
			var spots = [for (k in 0...6) r.y - 16 - 15 * k].filter(y -> y >= 0).concat([for (k in 0...6) r.y + r.h + 26 + 15 * k]);
			var ly = spots[0];
			for (y in spots)
				if (!Lambda.exists(placed, p -> Math.abs(p.y - y) < 15 && r.x < p.x + p.w && p.x < r.x + lw)) {
					ly = y;
					break;
				}
			placed.push({x: r.x, y: ly, w: lw});
			out.push(label(own, r.x, ly, text, colour, fade));
		}
		if (curves) {
			var plotted = tracks.copy();
			plotted.sort((a, b) -> a.running == b.running ? b.id - a.id : (a.running ? -1 : 1));
			var w = 150.0, h = 92.0, gap = 6.0;
			var count = Std.int(Math.min(plotted.length, maxCurves));
			for (i in 0...count)
				chart(own, plotted[i], width - (w + gap) * (i + 1), height - h - gap, w, h, fadeOf(plotted[i], now), out);
		}
		return out;
	}

	function fadeOf(t:MotionTrack, now:Float):Float
		return t.running || t.ended == null ? 1.0 : Math.max(0.15, 1 - (now - t.ended) / linger);

	/** Its path, centre to centre, with a dot each frame, when it moved. **/
	function trail(own:LayoutTree, t:MotionTrack, out:Array<Element>, now:Float):Void {
		var rects = t.rects;
		if (rects.length < 2)
			return;
		var travelled = 0.0;
		for (i in 1...rects.length)
			travelled += Math.abs(cx(rects[i]) - cx(rects[i - 1])) + Math.abs(cy(rects[i]) - cy(rects[i - 1]));
		if (travelled < 1)
			return;
		var c = PALETTE[(t.id - 1) % PALETTE.length];
		var a = fadeOf(t, now);
		for (i in 1...rects.length)
			out.push(segment(own, cx(rects[i - 1]), cy(rects[i - 1]), cx(rects[i]), cy(rects[i]), c, 0.6 * a, 1.5));
		for (q in rects)
			out.push(box(own, cx(q) - 2.5, cy(q) - 2.5, 5, 5, c, a, null, 0, 2.5));
	}

	static inline function cx(r:MotionTrack.MotionRect):Float
		return r.x + r.w / 2;

	static inline function cy(r:MotionTrack.MotionRect):Float
		return r.y + r.h / 2;

	/** How far it has got, filled, and a tick where its curve puts it now. **/
	function bar(own:LayoutTree, t:MotionTrack, x:Float, y:Float, w:Float, c:Int, a:Float, now:Float, out:Array<Element>):Void {
		out.push(box(own, x, y, w, 3, 0x000000, 0.4 * a, null, 0, 1.5));
		var s = t.samples.length == 0 ? null : t.samples[t.samples.length - 1];
		var p = s == null ? 0.0 : Math.max(0, Math.min(1, s.progress));
		if (p > 0)
			out.push(box(own, x, y, w * p, 3, c, a, null, 0, 1.5));
		var e = t.expected(t.running ? now : t.ended);
		if (e != null)
			out.push(box(own, x + w * Math.max(0, Math.min(1, e)) - 0.5, y - 2, 1, 7, 0xffffff, a));
	}

	/** A panel of `t`'s curve: as declared, in grey, and as it ran, a dot a frame, from 0 to 1 and a little past either. **/
	public static function chart(own:LayoutTree, t:MotionTrack, x:Float, y:Float, w:Float, h:Float, a:Float, out:Array<Element>):Void {
		var c = PALETTE[(t.id - 1) % PALETTE.length];
		out.push(box(own, x, y, w, h, 0x0b0d14, 0.85 * a, c, 0.6 * a, 6));
		out.push(text(own, x + 6, y + 4, '#${t.id} ${t.label} ${t.property}', 0xffffff, a, 9));
		out.push(text(own, x + 6, y + h - 14, t.kind == Spring ? t.curve : '${MotionCheck.ms(t.duration)} ${t.curve}', 0xaab0c0, a, 8));
		var px = x + 8, py = y + 18, pw = w - 16, ph = h - 36;
		inline function sy(v:Float):Float
			return py + ph * (1 - (v + 0.15) / 1.4);
		var due = t.began + t.delay;
		var last = t.samples.length == 0 ? null : t.samples[t.samples.length - 1];
		var span = t.kind == Spring ? Math.max(0.3, last == null ? 0.3 : last.clock - t.began) : Math.max(t.duration, 0.0001);
		out.push(box(own, px, sy(0), pw, 1, 0xffffff, 0.15 * a));
		out.push(box(own, px, sy(1), pw, 1, 0xffffff, 0.15 * a));
		var steps = 32;
		var prev:Null<Float> = null;
		for (k in 0...steps + 1) {
			var f = k / steps;
			var e = t.expected(due + f * span);
			if (e == null)
				break;
			if (prev != null)
				out.push(segment(own, px + pw * (f - 1 / steps), sy(prev), px + pw * f, sy(e), 0x9aa0b0, 0.8 * a, 1.25));
			prev = e;
		}
		for (s in t.samples) {
			var f = (s.clock - due) / span;
			if (f < -0.05 || f > 1.05)
				continue;
			out.push(box(own, px + pw * f - 2, sy(s.progress) - 2, 4, 4, c, a, null, 0, 2));
		}
	}

	/** A rectangle, filled and outlined as given, rounded by `radius`. **/
	static function box(own:LayoutTree, x:Float, y:Float, w:Float, h:Float, ?fill:Int, fillAlpha = 1.0, ?edge:Int, edgeAlpha = 1.0,
			radius = 0.0):Div {
		var d = new Div({position: Position.Absolute, left: x, top: y, width: Math.max(w, 0), height: Math.max(h, 0)}, own);
		if (fill != null)
			d.node.set(Prop.Background, Brush.solid(fill, fillAlpha));
		if (edge != null) {
			d.node.set(Prop.BorderColor, new Color(edge, edgeAlpha));
			d.node.set(Prop.BorderWidth, 1);
		}
		if (radius > 0)
			d.node.set(Prop.CornerRadius, CornerRadius.all(radius));
		return d;
	}

	/** A line from one point to another: a thin box turned about its middle. **/
	static function segment(own:LayoutTree, x1:Float, y1:Float, x2:Float, y2:Float, c:Int, a:Float, thick:Float):Div {
		var dx = x2 - x1, dy = y2 - y1;
		var length = Math.sqrt(dx * dx + dy * dy);
		var d = box(own, (x1 + x2) / 2 - length / 2, (y1 + y2) / 2 - thick / 2, length, thick, c, a, null, 0);
		d.node.set(Prop.Transform, ashui.types.Transform.rotation(Math.atan2(dy, dx) * 180 / Math.PI));
		return d;
	}

	static function text(own:LayoutTree, x:Float, y:Float, s:String, c:Int, a:Float, size:Float):Div {
		var t = new Text(s, {color: new Color(c, a), fontSize: size, wrap: false}, own);
		return new Div({position: Position.Absolute, left: x, top: y}, [t], own);
	}

	static function label(own:LayoutTree, x:Float, y:Float, s:String, c:Int, a:Float):Div {
		var t = new Text(s, {color: new Color(0xffffff, a), fontSize: 10, wrap: false}, own);
		var d = new Div({position: Position.Absolute, left: x, top: y, padding: 2}, [t], own);
		d.node.set(Prop.Background, Brush.solid(c, 0.85 * a));
		d.node.set(Prop.CornerRadius, CornerRadius.all(3));
		return d;
	}
}
