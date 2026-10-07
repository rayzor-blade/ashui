package ashui.media;

import ashui.reactive.Owner;
import ashui.reactive.Signal;
import media.AudioData;
import media.AudioEqualizer;

typedef EqualizerBand = {
	frequency:Float,
	gainDb:Float,
	q:Float,
	enabled:Bool
}

/**
	Reactive peaking-band equalizer for playback and decoded PCM. Settings are
	shared with attached Players; each native player keeps its own DSP history.
	Created under an Owner, it closes on cleanup. Otherwise call close yourself.
	Read the signals for UI and change settings through the methods.
**/
class Equalizer {
	public final bands:Array<Signal<EqualizerBand>> = [];
	public final preamp = Signal.make(0.0);
	public final bypassed = Signal.make(false);
	public final revision = Signal.make(0);
	public var disposed(get, never):Bool;

	final native:AudioEqualizer;
	final closed = Signal.make(false);
	final listeners:Array<Void->Void> = [];

	/** 1–16 center frequencies in Hz. Defaults to 60, 250, 1000, 4000 and 12000 Hz, flat at Q=1. **/
	public function new(?frequencies:Array<Float>) {
		if (frequencies == null) frequencies = [60, 250, 1000, 4000, 12000];
		if (frequencies.length < 1 || frequencies.length > 16) throw "An equalizer needs 1–16 bands";
		for (frequency in frequencies)
			if (!Math.isFinite(frequency) || frequency < 1 || frequency > 96000) throw "Equalizer frequency must be 1–96000 Hz";
		native = AudioEqualizer.create(frequencies.length);
		try {
			for (index in 0...frequencies.length) {
				native.setBand(index, frequencies[index], 0, 1);
				bands.push(Signal.make({frequency: frequencies[index], gainDb: 0.0, q: 1.0, enabled: true}));
			}
		} catch (e:Dynamic) { native.close(); throw e; }
		Owner.onCleanup(this.close);
	}

	/** Gain −24…+24 dB, Q 0.1–20. Also enables the band. Invalid settings leave it unchanged. **/
	public function setBand(index:Int, frequency:Float, gainDb:Float, q:Float):Void {
		checkBand(index);
		native.setBand(index, frequency, gainDb, q);
		bands[index].set({frequency: frequency, gainDb: gainDb, q: q, enabled: true});
		changed();
	}

	public function setGain(index:Int, gainDb:Float):Void {
		checkBand(index);
		var band = bands[index].get();
		setBand(index, band.frequency, gainDb, band.q);
	}

	public function disableBand(index:Int):Void {
		checkBand(index);
		native.disableBand(index);
		var band = bands[index].get();
		bands[index].set({frequency: band.frequency, gainDb: band.gainDb, q: band.q, enabled: false});
		changed();
	}

	/** −60…0 dB. Negative preamp gives boosted bands headroom. **/
	public function setPreamp(gainDb:Float):Void {
		checkOpen();
		native.setPreamp(gainDb);
		preamp.set(gainDb);
		changed();
	}

	/** Bypasses both the bands and preamp; retains their settings. **/
	public function setBypass(value:Bool):Void {
		checkOpen();
		native.setBypass(value);
		bypassed.set(value);
		changed();
	}

	/** Restore zero gain and preamp, preserving center frequencies, Q and bypass. **/
	public function flatten():Void {
		checkOpen();
		for (index in 0...bands.length) {
			var band = bands[index].get();
			native.setBand(index, band.frequency, 0, band.q);
			bands[index].set({frequency: band.frequency, gainDb: 0.0, q: band.q, enabled: true});
		}
		native.setPreamp(0);
		preamp.set(0);
		changed();
	}

	/** Borrow the input; return owned interleaved F32 PCM. The caller must close the result. **/
	public function process(data:AudioData):AudioData {
		checkOpen();
		return native.process(data);
	}

	/** Clear PCM filter history without changing settings. Playback histories belong to their players. **/
	public function reset():Void {
		checkOpen();
		native.reset();
	}

	/** Detaches attached players, restoring flat playback. Terminal and idempotent. **/
	public function close():Void {
		if (disposed) return;
		native.close();
		closed.set(true);
		changed();
		listeners.resize(0);
	}

	public inline function dispose():Void close();
	inline function get_disposed():Bool return closed.get();

	@:allow(ashui.media.Player)
	function handle():AudioEqualizer {
		checkOpen();
		return native;
	}

	// Explicit subscriptions also update standalone or paused players, without
	// depending on a UI flush or assigning a caller-owned player to a UI Owner.
	@:allow(ashui.media.Player)
	function listen(callback:Void->Void):Void->Void {
		checkOpen();
		listeners.push(callback);
		return () -> { listeners.remove(callback); };
	}

	function changed():Void {
		revision.set(revision.get() + 1);
		for (listener in listeners.copy()) listener();
	}

	function checkBand(index:Int):Void {
		checkOpen();
		if (index < 0 || index >= bands.length) throw "Equalizer band index is out of range";
	}

	function checkOpen():Void {
		if (disposed) throw "Equalizer is closed";
	}
}
