package ashui.debug;

import ashui.debug.MotionTrack.MotionKind;
import ashui.debug.MotionTrack.MotionEnd;

/** What `MotionCheck` measured of a track, and what it found wrong. **/
typedef MotionVerdict = {
	track:MotionTrack,
	/** Frames it drew. **/
	frames:Int,
	/** Seconds from when it was due to start (asked, plus its delay) to its first frame. **/
	startLag:Float,
	/** Seconds it ran, from when it was due to start to its last frame; null while it runs. **/
	ran:Null<Float>,
	/** The furthest it was from where its curve put it at that time, as a fraction of the whole move, and the time fraction there. **/
	maxError:Float,
	errorAt:Float,
	/** How far past its end it went, as a fraction of the move; 0 when it did not. **/
	overshoot:Float,
	/** The median seconds between its frames. **/
	frameTime:Float,
	/** Where its last frame put it. **/
	lastProgress:Float,
	/** Problems, each a short phrase; empty when it behaved as declared. **/
	issues:Array<String>,
	/** Things worth knowing that are not wrong: it was interrupted, it is still running. **/
	notes:Array<String>
}

/**
	Judges a track against what it was declared to do. Every animation
	advances on the scheduler's clock, so where a track should be at a frame
	is its curve at the time since it was due to start: a track that starts
	a frame late, runs on a clamped step while the clock runs on, restarts,
	jumps, or never moves at all shows as a distance from its curve or as
	time it ran past its duration.
**/
class MotionCheck {
	/** A fraction of the move a frame may be off its curve. **/
	public static var tolerance = 0.02;
	/**
		Seconds within which a move undone by the next on the same property is
		a bounce rather than two intended moves: a few frames, as a flicker in
		layout or styles is; a person moving focus on undoes a ring later.
	**/
	public static var bounceWindow = 0.05;

	public static function check(track:MotionTrack, ?trace:MotionTrace):MotionVerdict {
		var s = track.samples;
		var issues = [], notes = [];
		var due = track.began + track.delay;
		var gaps = [for (i in 1...s.length) s[i].clock - s[i - 1].clock].filter(g -> g > 0);
		gaps.sort(Reflect.compare);
		var frameTime = gaps.length == 0 ? 1 / 60 : gaps[gaps.length >> 1];
		// The first frame that moved it, after its delay: the frame drawn as it starts is at progress 0 by right.
		var firstMoving = Lambda.find(s, x -> x.clock > due + 1e-9);
		var startLag = firstMoving == null ? 0.0 : Math.max(0, firstMoving.clock - due - frameTime);
		var last = s.length == 0 ? null : s[s.length - 1];
		var ran = track.running || last == null ? null : last.clock - due;

		var maxError = 0.0, errorAt = 0.0, overshoot = 0.0;
		var biggestJump = 0.0;
		for (i in 0...s.length) {
			var x = s[i];
			var e = track.expected(x.clock);
			if (e != null) {
				var d = Math.abs(x.progress - e);
				if (d > maxError) {
					maxError = d;
					errorAt = track.duration <= 0 ? 1 : (x.clock - due) / track.duration;
				}
				if (i > 0) {
					var was = track.expected(s[i - 1].clock);
					if (was != null)
						biggestJump = Math.max(biggestJump, Math.abs((x.progress - s[i - 1].progress) - (e - was)));
				}
			}
			if (track.kind != Keyframes)
				overshoot = Math.max(overshoot, x.progress - 1);
		}

		if (track.from == track.to && track.kind != Keyframes && track.duration > 0 && track.end != Snapped)
			issues.push('moved nowhere: from equals to, yet it ran ${ms(ran == null ? 0 : ran)}');
		// An animation is there to be seen: one spent out of sight is an entrance or exit that never showed. A transition
		// finishing on an element taken away (a closed menu's hovered item) is only work for nothing.
		if (track.node != null && track.rects.length == 0 && s.length > 2 && trace != null && trace.observed) {
			if (track.kind == Keyframes)
				issues.push("ran where it is not drawn: its element was detached the whole time, so the motion was never seen");
			else
				notes.push("ran where it is not drawn");
		}
		if (track.duration > 0 && track.kind != Spring && track.end == Completed && s.length <= 1)
			issues.push("snapped: no frames between its start and end");
		if (startLag > 0.0005)
			issues.push('started ${ms(startLag)} late');
		if (maxError > tolerance && s.length > 1)
			issues.push('off its curve by ${pct(maxError)} at t=${fixed(errorAt, 2)}');
		if (biggestJump > 0.25)
			issues.push('jumped ${pct(biggestJump)} more than its curve in one frame');
		if (ran != null && track.end == Completed && track.kind != Spring && track.kind != Keyframes) {
			var off = ran - track.duration;
			if (Math.abs(off) > frameTime + 0.0005)
				issues.push('ran ${ms(ran)}, declared ${ms(track.duration)}');
		}
		if (track.end == Completed && last != null && track.kind != Keyframes && Math.abs(last.progress - 1) > 0.01)
			issues.push('ended at ${pct(last.progress)}, short of its end');
		if (track.kind == Spring && track.end == Running && trace != null && trace.stopped != null)
			issues.push("never settled");
		if (trace != null) {
			// The same move again with nothing between taking it back: a restyle that started it twice. Taken back first, it is a second change.
			var repeated:Null<MotionTrack> = null;
			for (other in trace.tracks) {
				if (other == track)
					break;
				if (other.key() != track.key())
					continue;
				if (other.end == Completed && other.from == track.from && other.to == track.to && track.from != track.to)
					repeated = other;
				else if (repeated != null && other.to == track.from)
					repeated = null;
			}
			if (repeated != null)
				issues.push('ran again from ${track.from} to ${track.to}, as track #${repeated.id} already had');
		}
		if (trace != null) {
			// A move cut short and then undone soon after: something changed and changed back, a flicker in the layout or the styles.
			var previous:Null<MotionTrack> = null;
			for (other in trace.tracks) {
				if (other == track)
					break;
				if (other.key() == track.key())
					previous = other;
			}
			if (previous != null && previous.end == Interrupted && track.to == previous.from && track.from != track.to
				&& track.began - previous.began < bounceWindow)
				issues.push('undid track #${previous.id} ${ms(track.began - previous.began)} after it began: a change and its reverse');
		}
		if (track.end == Interrupted)
			notes.push('interrupted at ${pct(last == null ? 0 : last.progress)}');
		if (track.end == Running)
			notes.push("still running");
		if (overshoot > 0.001)
			notes.push('overshot by ${pct(overshoot)}');
		return {
			track: track,
			frames: s.length,
			startLag: startLag,
			ran: ran,
			maxError: maxError,
			errorAt: errorAt,
			overshoot: overshoot,
			frameTime: frameTime,
			lastProgress: last == null ? 0 : last.progress,
			issues: issues,
			notes: notes
		};
	}

	/**
		How far a spring of `config` released from rest has gone toward its
		target after `t` seconds, as a fraction of the move: the damped
		oscillator's own solution, against which the integrated one is checked.
		`v0` is its speed at release, in moves per second.
	**/
	public static function springProgress(config:ashui.animation.SpringConfig, t:Float, v0 = 0.0):Float {
		if (t <= 0)
			return 0;
		var k = config.stiffness, c = config.damping, m = config.mass;
		var w0 = Math.sqrt(k / m);
		var zeta = c / (2 * Math.sqrt(k * m));
		// x is what is left of the move, 1 at release; its speed is -v0.
		var x0 = 1.0, v = -v0;
		var x:Float;
		if (zeta < 0.999) {
			var wd = w0 * Math.sqrt(1 - zeta * zeta);
			x = Math.exp(-zeta * w0 * t) * (x0 * Math.cos(wd * t) + (v + zeta * w0 * x0) / wd * Math.sin(wd * t));
		} else if (zeta <= 1.001) {
			x = (x0 + (v + w0 * x0) * t) * Math.exp(-w0 * t);
		} else {
			var root = Math.sqrt(zeta * zeta - 1);
			var r1 = -w0 * (zeta - root), r2 = -w0 * (zeta + root);
			var c1 = (v - r2 * x0) / (r1 - r2);
			x = c1 * Math.exp(r1 * t) + (x0 - c1) * Math.exp(r2 * t);
		}
		return 1 - x;
	}

	/** A verdict on one line: the track, what it did, and ok or its issues. **/
	public static function line(v:MotionVerdict):String {
		var t = v.track;
		var head = '#${t.id} ${t.kind} ${t.label} ${t.property}: ${t.from} -> ${t.to}';
		var declared = t.kind == Spring ? t.curve : '${ms(t.duration)} ${t.curve}${t.delay > 0 ? ' after ${ms(t.delay)}' : ""}';
		var did = '${v.frames} frames' + (v.ran != null ? ', ran ${ms(v.ran)}' : "") + ', max off-curve ${pct(v.maxError)}';
		var verdict = v.issues.length == 0 ? "ok" : "WARN " + v.issues.join("; ");
		var notes = v.notes.length == 0 ? "" : ' (${v.notes.join("; ")})';
		return '$head\n    declared $declared\n    $did, ${t.end}$notes\n    $verdict';
	}

	/** Every track of `trace` judged, as a report: a summary line, then a verdict for each. **/
	public static function report(trace:MotionTrace):String {
		var verdicts = [for (t in trace.tracks) check(t, trace)];
		var warned = verdicts.filter(v -> v.issues.length > 0).length;
		var span = (trace.stopped != null ? trace.stopped : MotionTrace.clock()) - trace.started;
		var out = ['motion trace: ${trace.tracks.length} tracks over ${ms(span)}, ${warned == 0 ? "all ok" : '$warned with issues'}', ""];
		for (v in verdicts)
			out.push(line(v));
		return out.join("\n") + "\n";
	}

	/** The trace as JSON, every track with its samples and drawn rects, for a debugger or a script to read. **/
	public static function json(trace:MotionTrace):String {
		return haxe.Json.stringify({
			started: trace.started,
			stopped: trace.stopped,
			tracks: [
				for (t in trace.tracks) {
					var v = check(t, trace);
					{
						id: t.id,
						kind: (t.kind : String),
						label: t.label,
						property: t.property,
						from: t.from,
						to: t.to,
						delay: t.delay,
						duration: t.duration,
						curve: t.curve,
						began: t.began,
						ended: t.ended,
						end: (t.end : String),
						issues: v.issues,
						notes: v.notes,
						maxError: v.maxError,
						samples: [for (s in t.samples) {clock: s.clock, progress: s.progress, expected: t.expected(s.clock), value: s.value}],
						rects: t.rects
					}
				}
			]
		}, null, " ");
	}

	public static function ms(seconds:Float):String
		return '${Math.round(seconds * 1000)}ms';

	public static function pct(f:Float):String
		return '${fixed(f * 100, 1)}%';

	public static function fixed(v:Float, places:Int):String {
		var f = Math.pow(10, places);
		return Std.string(Math.round(v * f) / f);
	}
}
