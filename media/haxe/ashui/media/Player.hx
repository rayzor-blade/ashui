package ashui.media;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Signal;
import ashui.state.Machine;
import media.MediaPlayer;
import media.PlaybackState;
import media.VideoFrame;

/** File playback state, including the controller's empty, error and disposed states. **/
enum PlayerState {
	Empty;
	Opening;
	Seeking;
	Paused;
	Playing;
	Buffering;
	Ended;
	Failed;
	Closed;
}

private enum PlayerEvent {
	Unload;
	Open;
	Observed(state:PlayerState);
	StartSeek;
	FrameReady;
	SeekTimeout;
	OpenTimeout;
	Failure;
	Dispose;
}

typedef PlayerOptions = {
	?autoplay:Bool,
	?loop:Bool,
	?volume:Float,
	?muted:Bool,
	/** Usually the UI frame scheduler. Native playback still uses its own real-time clock. **/
	?scheduler:AnimationScheduler
}

/**
	Reactive file playback on hlavi's native audio/video clock. Create and drive
	on the UI thread. A component disposes a player it creates; callers close
	players they supply. No owner is needed to use the controller by itself.

	Signals report native state; use the methods to change playback. Position
	and duration are seconds. Only one decoded frame is retained; `currentFrame`
	returns an independent handle that its caller must close.
**/
class Player {
	public final source = Signal.make("");
	public final state:Signal<PlayerState>;
	public final error = Signal.make((null : Null<String>));
	public final position = Signal.make(0.0);
	public final duration = Signal.make(0.0);
	public final volume = Signal.make(1.0);
	public final muted = Signal.make(false);
	public final looping = Signal.make(false);
	public final videoWidth = Signal.make(0);
	public final videoHeight = Signal.make(0);
	/** Changes on each new frame and whenever the retained frame is cleared. **/
	public final frameVersion = Signal.make(0);
	public var disposed(default, null) = false;

	final scheduler:AnimationScheduler;
	final machine:Machine<PlayerState, PlayerEvent>;
	var native:Null<MediaPlayer> = null;
	var frame:Null<VideoFrame> = null;
	var running = false;
	var generation = 0;
	var nativeState = PlayerState.Empty;
	var updateAt = 0.0;
	var autoplay = false;
	final playIntent = Signal.make(false);

	public function new(?source:String, ?options:PlayerOptions) {
		if (options == null) options = {};
		scheduler = options.scheduler == null ? AnimationScheduler.main : options.scheduler;
		machine = new Machine<PlayerState, PlayerEvent>(Empty, (state, event) -> switch [state, event] {
			case [Closed, _]: null;
			case [_, Unload]: Empty;
			case [_, Open]: Opening;
			case [_, StartSeek]: Seeking;
			case [Seeking, Observed(Ended)]: Ended;
			case [Seeking, Observed(_)]: null;
			case [Opening, Observed(Paused)] if (frame == null): Seeking;
			case [_, Observed(next)]: next;
			case [Seeking, FrameReady] | [Seeking, SeekTimeout]: nativeState;
			case [Opening, OpenTimeout] | [_, Failure]: Failed;
			case [_, Dispose]: Closed;
			case _: null;
		}, scheduler);
		state = machine.state;
		machine.after(Opening, 20, OpenTimeout);
		machine.after(Seeking, 2, SeekTimeout);
		machine.onEnter(Failed, _ -> {
			if (error.get() == null) error.set("Timed out opening media");
			release();
		});
		machine.onEnter(Closed, _ -> release());
		autoplay = options.autoplay == true;
		looping.set(options.loop == true);
		if (options.volume != null) volume.set(level(options.volume));
		muted.set(options.muted == true);
		if (source != null && source != "") load(source);
	}

	/** Replaces the source, releases its frames, and opens it paused unless autoplay is true. Empty unloads it. **/
	public function load(path:String, ?autoplay:Bool):Void {
		checkOpen();
		release();
		if (autoplay != null) this.autoplay = autoplay;
		source.set(path == null ? "" : path);
		error.set(null);
		position.set(0);
		duration.set(0);
		machine.send(Unload);
		if (path == null || path == "") return;
		playIntent.set(this.autoplay);
		try {
			native = MediaPlayer.open(path);
			native.setVolume(muted.get() ? 0 : volume.get());
			machine.send(Open);
			if (this.autoplay) native.play();
			wake();
		} catch (e:Dynamic) fail(e);
	}

	public function play():Void {
		checkOpen();
		if (native == null) return;
		try {
			playIntent.set(true);
			if (state.get() == Ended) native.seek(0);
			native.play();
			refresh();
			wake();
		} catch (e:Dynamic) fail(e);
	}

	public function pause():Void {
		checkOpen();
		if (native == null) return;
		try {
			playIntent.set(false);
			native.pause();
			refresh();
		} catch (e:Dynamic) fail(e);
	}

	public function toggle():Void {
		if (isPlaying()) pause(); else play();
	}

	/** Playback intent, including a seek or buffering while playing. Paused seeking stays paused. **/
	public function isPlaying():Bool {
		var current = state.get();
		return playIntent.get() && current != Ended && current != Failed && current != Empty && current != Closed;
	}

	/** Seeks to a bounded position; a paused seek also updates the displayed frame. **/
	public function seek(seconds:Float):Void {
		checkOpen();
		if (native == null) return;
		if (!Math.isFinite(seconds)) throw "Media seek must be finite";
		try {
			var end = native.duration();
			var target = Math.max(0, end > 0 ? Math.min(end, seconds) : seconds);
			native.seek(target);
			// Restart the FSM's seek timer on a second seek before the first completes.
			if (state.get() == Seeking) machine.send(FrameReady);
			machine.send(StartSeek);
			position.set(target);
			wake();
		} catch (e:Dynamic) fail(e);
	}

	public function setVolume(value:Float):Void {
		checkOpen();
		volume.set(level(value));
		applyVolume();
	}

	public function setMuted(value:Bool):Void {
		checkOpen();
		muted.set(value);
		applyVolume();
	}

	public function setLoop(value:Bool):Void {
		checkOpen();
		looping.set(value);
	}

	/** A clone of the latest frame; null for audio or before the first video frame. **/
	public function currentFrame():Null<VideoFrame>
		return frame == null ? null : frame.clone();

	/** Poll once on the same thread that opened it. Normally the scheduler does this. **/
	public function update():Void {
		if (disposed || native == null) return;
		try {
			var received = native.pollFrame();
			if (received) {
				var next = native.takeFrame();
				if (frame != null) frame.close();
				frame = next;
				videoWidth.set(haxe.Int64.toInt(next.displayWidth()));
				videoHeight.set(haxe.Int64.toInt(next.displayHeight()));
				frameVersion.set(frameVersion.get() + 1);
			}
			var now = Sys.time();
			// Time labels need not repaint at the video's frame rate.
			if (now >= updateAt || state.get() == Opening) {
				refresh();
				updateAt = now + 0.1;
			}
			if (received) {
				refresh();
				machine.send(FrameReady);
			}
			if (state.get() == Ended && looping.get()) {
				playIntent.set(true);
				native.seek(0);
				native.play();
				refresh();
			}
		} catch (e:Dynamic) fail(e);
	}

	/** Releases the native player and retained frame. Terminal and idempotent. **/
	public function close():Void {
		if (disposed) return;
		disposed = true;
		machine.send(Dispose);
		machine.dispose();
	}

	public inline function dispose():Void close();

	function wake():Void {
		if (running || native == null || disposed) return;
		running = true;
		var ticket = generation;
		scheduler.addTicker(_ -> {
			if (disposed || ticket != generation) return false;
			update();
			var s = state.get();
			var keep = native != null && (s == Seeking || s == Opening || s == Playing || s == Buffering);
			if (ticket == generation) running = keep;
			return ticket == generation && keep;
		});
	}

	function refresh():Void {
		if (native == null) return;
		nativeState = switch native.state() {
			case PlaybackState.Opening: Opening;
			case PlaybackState.Paused: Paused;
			case PlaybackState.Playing: Playing;
			case PlaybackState.Buffering: Buffering;
			case PlaybackState.Ended: Ended;
			case _: throw "Unknown native playback state";
		};
		machine.send(Observed(nativeState));
		duration.set(native.duration());
		position.set(native.position());
	}

	function applyVolume():Void {
		if (native != null) try native.setVolume(muted.get() ? 0 : volume.get()) catch (e:Dynamic) fail(e);
	}

	function release():Void {
		generation++;
		running = false;
		nativeState = Empty;
		playIntent.set(false);
		if (native != null) { native.close(); native = null; }
		if (frame != null) { frame.close(); frame = null; }
		videoWidth.set(0);
		videoHeight.set(0);
		frameVersion.set(frameVersion.get() + 1);
		updateAt = 0;
	}

	function fail(e:Dynamic):Void {
		error.set(Std.string(e));
		machine.send(Failure);
	}

	/** The state as a CSS-friendly name. **/
	public function stateName():String
		return Type.enumConstructor(state.get()).toLowerCase();

	function checkOpen():Void {
		if (disposed) throw "Media player is closed";
	}

	static function level(value:Float):Float {
		if (!Math.isFinite(value)) throw "Media volume must be finite";
		return Math.max(0, Math.min(1, value));
	}
}
