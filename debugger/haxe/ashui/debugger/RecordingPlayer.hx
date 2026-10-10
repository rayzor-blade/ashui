package ashui.debugger;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Computed;
import ashui.reactive.Signal;

/**
	Plays a `Recording` back: where its playhead is, whether it is playing,
	and the frame shown there. The views take one as a prop, as
	`ashui.media`'s controls take a `Player`, so a frame view, its controls
	and the timeline stay in step. Position and duration are seconds from
	the recording's start.
**/
class RecordingPlayer {
	public final recording:Signal<Null<Recording>>;
	public final position = Signal.make(0.0);
	public final playing = Signal.make(false);
	public final looping = Signal.make(false);
	/** How fast it plays: 1 in real time, 0.25 at a quarter of it. **/
	public final rate = Signal.make(1.0);
	/** Whether frames show their gizmos: the motion overlay's outlines, trails, labels and bars, and the selected track's outline. **/
	public final gizmos = Signal.make(true);
	/** The track picked in the timeline, by id; -1 for none. **/
	public final selected = Signal.make(-1);
	/** The frame at the playhead. **/
	public final frame:Computed<Int>;
	public final duration:Computed<Float>;

	final scheduler:AnimationScheduler;
	var ticking = false;

	public function new(?recording:Recording, ?scheduler:AnimationScheduler) {
		this.recording = Signal.make(recording);
		this.scheduler = scheduler != null ? scheduler : AnimationScheduler.main;
		frame = Computed.make(() -> {
			var r = this.recording.get();
			return r == null ? 0 : r.frameAt(position.get());
		});
		duration = Computed.make(() -> {
			var r = this.recording.get();
			return r == null ? 0.0 : r.span;
		});
	}

	/** Shows `recording` from its start, paused. **/
	public function open(recording:Recording):Void {
		pause();
		selected.set(-1);
		position.set(0);
		this.recording.set(recording);
	}

	public function play():Void {
		if (recording.get() == null || playing.get())
			return;
		if (position.get() >= duration.get())
			position.set(0);
		playing.set(true);
		if (!ticking) {
			ticking = true;
			scheduler.addTicker(tick);
		}
	}

	public function pause():Void
		playing.set(false);

	public function toggle():Void
		playing.get() ? pause() : play();

	/** Moves the playhead to `t`, kept within the recording. **/
	public function seek(t:Float):Void
		position.set(Math.max(0, Math.min(duration.get(), t)));

	/** Moves to the frame `by` frames on from the one shown, pausing. **/
	public function step(by:Int):Void {
		var r = recording.get();
		if (r == null || r.times.length == 0)
			return;
		pause();
		var i = Std.int(Math.max(0, Math.min(r.times.length - 1, frame.get() + by)));
		position.set(r.times[i]);
	}

	function tick(dt:Float):Bool {
		if (!playing.get()) {
			ticking = false;
			return false;
		}
		var next = position.get() + dt * rate.get();
		if (next >= duration.get()) {
			if (looping.get())
				next = next % Math.max(duration.get(), 1e-6);
			else {
				position.set(duration.get());
				playing.set(false);
				ticking = false;
				return false;
			}
		}
		position.set(next);
		return true;
	}
}
