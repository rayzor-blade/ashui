package ashui.media;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Signal;
import ashui.state.Machine;
import media.MediaPlayer;
import media.PlaybackState;
import media.VideoFrame;

/** Playback lifecycle, including empty, error, and disposed states. **/
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
	/** Shared equalizer settings. The player does not own or close the equalizer. **/
	?equalizer:Equalizer,
	/** Scheduler used to poll playback, normally the UI frame scheduler. Native playback keeps its own real-time clock. **/
	?scheduler:AnimationScheduler
}

/**
	Controls reactive audio/video playback using hlavi's native media clock.
	Create and use players on the UI thread. Read signals for state and call
	methods to change playback. Position and duration are measured in seconds.

	A component disposes players it creates. Callers must close players they
	supply. The controller can also be used without an `Owner`.
	Only one decoded frame is retained. `currentFrame` returns an independent
	handle that the caller must close.
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
	public final equalizer = Signal.make((null : Null<Equalizer>));
	public final videoWidth = Signal.make(0);
	public final videoHeight = Signal.make(0);

	/** Changes on each new frame and whenever the retained frame is cleared. **/
	public final frameVersion = Signal.make(0);

	public var disposed(default, null) = false;

	final scheduler:AnimationScheduler;
	final machine:Machine<PlayerState, PlayerEvent>;
	var native:Null<MediaPlayer> = null;
	var frame:Null<VideoFrame> = null;
	/** Scheduler ticker that polls native playback while attached. **/
	var ticker:Null<ashui.animation.AnimationScheduler.Ticker> = null;
	var generation = 0;
	var nativeState = PlayerState.Empty;
	var updateAt = 0.0;
	var autoplay = false;
	final playIntent = Signal.make(false);
	var detachEqualizer:Null<Void->Void> = null;

	public function new(?source:String, ?options:PlayerOptions) {
		if (options == null)
			options = {};
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
			if (error.get() == null)
				error.set("Timed out opening media");
			release();
		});
		machine.onEnter(Closed, _ -> release());
		autoplay = options.autoplay == true;
		looping.set(options.loop == true);
		if (options.volume != null)
			volume.set(level(options.volume));
		muted.set(options.muted == true);
		if (options.equalizer != null)
			setEqualizer(options.equalizer);
		if (source != null && source != "")
			load(source);
	}

	/**
		Replaces the source and releases retained frames. Opens paused unless
		autoplay is enabled. An empty path unloads the source.
	**/
	public function load(path:String, ?autoplay:Bool):Void {
		checkOpen();
		release();
		if (autoplay != null)
			this.autoplay = autoplay;
		source.set(path == null ? "" : path);
		error.set(null);
		position.set(0);
		duration.set(0);
		machine.send(Unload);
		if (path == null || path == "")
			return;
		playIntent.set(this.autoplay);
		try {
			native = MediaPlayer.open(path);
			native.setVolume(muted.get() ? 0 : volume.get());
			var eq = equalizer.get();
			if (eq != null)
				native.setEqualizer(eq.handle());
			machine.send(Open);
			if (this.autoplay)
				native.play();
			wake();
		} catch (e:Dynamic)
			fail(e);
	}

	public function play():Void {
		checkOpen();
		if (native == null)
			return;
		try {
			playIntent.set(true);
			if (state.get() == Ended)
				native.seek(0);
			native.play();
			refresh();
			wake();
		} catch (e:Dynamic)
			fail(e);
	}

	public function pause():Void {
		checkOpen();
		if (native == null)
			return;
		try {
			playIntent.set(false);
			native.pause();
			refresh();
		} catch (e:Dynamic)
			fail(e);
	}

	public function toggle():Void {
		if (isPlaying())
			pause();
		else
			play();
	}

	/** Returns playback intent, including buffering or seeking during playback. A paused seek remains paused. **/
	public function isPlaying():Bool {
		var current = state.get();
		return playIntent.get() && current != Ended && current != Failed && current != Empty && current != Closed;
	}

	/** Seeks within the media duration. Also updates the displayed frame while paused. **/
	public function seek(seconds:Float):Void {
		checkOpen();
		if (native == null)
			return;
		if (!Math.isFinite(seconds))
			throw "Media seek must be finite";
		try {
			var end = native.duration();
			var target = Math.max(0, end > 0 ? Math.min(end, seconds) : seconds);
			native.seek(target);
			// Restart the FSM's seek timer on a second seek before the first completes.
			if (state.get() == Seeking)
				machine.send(FrameReady);
			machine.send(StartSeek);
			position.set(target);
			wake();
		} catch (e:Dynamic)
			fail(e);
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

	/** Attaches shared equalizer settings, applied immediately even while paused. Null restores flat playback. **/
	public function setEqualizer(value:Null<Equalizer>):Void {
		checkOpen();
		if (value != null)
			value.handle(); // Validate before replacing a working equalizer.
		if (detachEqualizer != null) {
			detachEqualizer();
			detachEqualizer = null;
		}
		equalizer.set(value);
		if (value != null)
			detachEqualizer = value.listen(() -> {
				if (value.disposed)
					clearEqualizer();
				else
					applyEqualizer();
			});
		applyEqualizer();
	}

	public inline function clearEqualizer():Void
		setEqualizer(null);

	/**
		Returns an independent handle to the latest frame, or null for audio
		or before the first video frame. The caller must close the returned handle.
	**/
	public function currentFrame():Null<VideoFrame>
		return frame == null ? null : frame.clone();

	/** Polls playback on the thread that opened it. Normally called by the scheduler. **/
	public function update():Void {
		if (disposed || native == null)
			return;
		try {
			var received = native.pollFrame();
			if (received) {
				var next = native.takeFrame();
				if (frame != null)
					frame.close();
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
		} catch (e:Dynamic)
			fail(e);
	}

	/** Releases native playback and the retained frame. Repeated calls are safe; the player cannot be reused after closing. **/
	public function close():Void {
		if (disposed)
			return;
		if (detachEqualizer != null) {
			detachEqualizer();
			detachEqualizer = null;
		}
		equalizer.set(null);
		disposed = true;
		machine.send(Dispose);
		machine.dispose();
	}

	public inline function dispose():Void
		close();

	function wake():Void {
		if ((ticker != null && ticker.running) || native == null || disposed)
			return;
		var ticket = generation;
		ticker = scheduler.addTicker(_ -> {
			if (disposed || ticket != generation)
				return false;
			update();
			var s = state.get();
			// Playing is intended but the native player may not have started yet: it is followed until it says so, or stops.
			var waiting = playIntent.get() && s != Ended && s != Failed && s != Closed && s != Empty;
			return native != null && (waiting || s == Seeking || s == Opening || s == Playing || s == Buffering);
		});
	}

	function refresh():Void {
		if (native == null)
			return;
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
		if (native != null)
			try
				native.setVolume(muted.get() ? 0 : volume.get())
			catch (e:Dynamic)
				fail(e);
	}

	function applyEqualizer():Void {
		if (native == null)
			return;
		try {
			var eq = equalizer.get();
			if (eq == null)
				native.clearEqualizer();
			else
				native.setEqualizer(eq.handle());
		} catch (e:Dynamic)
			fail(e);
	}

	function release():Void {
		generation++;
		ticker = null;
		nativeState = Empty;
		playIntent.set(false);
		if (native != null) {
			native.close();
			native = null;
		}
		if (frame != null) {
			frame.close();
			frame = null;
		}
		videoWidth.set(0);
		videoHeight.set(0);
		frameVersion.set(frameVersion.get() + 1);
		updateAt = 0;
	}

	function fail(e:Dynamic):Void {
		error.set(Std.string(e));
		machine.send(Failure);
	}

	/** Returns the current state as a CSS-compatible name. **/
	public function stateName():String
		return Type.enumConstructor(state.get()).toLowerCase();

	function checkOpen():Void {
		if (disposed)
			throw "Media player is closed";
	}

	static function level(value:Float):Float {
		if (!Math.isFinite(value))
			throw "Media volume must be finite";
		return Math.max(0, Math.min(1, value));
	}
}
