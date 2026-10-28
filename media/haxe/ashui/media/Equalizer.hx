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
	A reactive peaking-band equalizer for playback and decoded PCM.
	Attached players share its settings but keep separate DSP histories.
	Read signals for state and use methods to change settings.

	The current `Owner` closes the equalizer on cleanup. When created outside
	an owner, call `close` explicitly.
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

	/** Creates 1–16 frequency bands in Hz. Defaults to 60, 250, 1000, 4000, and 12000 Hz with zero gain and Q=1. **/
	public function new(?frequencies:Array<Float>) {
		if (frequencies == null)
			frequencies = [60, 250, 1000, 4000, 12000];
		if (frequencies.length < 1 || frequencies.length > 16)
			throw "An equalizer needs 1–16 bands";
		for (frequency in frequencies)
			if (!Math.isFinite(frequency) || frequency < 1 || frequency > 96000)
				throw "Equalizer frequency must be 1–96000 Hz";
		native = AudioEqualizer.create(frequencies.length);
		try {
			for (index in 0...frequencies.length) {
				native.setBand(index, frequencies[index], 0, 1);
				bands.push(Signal.make({
					frequency: frequencies[index],
					gainDb: 0.0,
					q: 1.0,
					enabled: true
				}));
			}
		} catch (e:Dynamic) {
			native.close();
			throw e;
		}
		Owner.onCleanup(this.close);
	}

	/** Sets and enables a band. Gain ranges from -24 to +24 dB and Q from 0.1 to 20. Invalid settings leave the band unchanged. **/
	public function setBand(index:Int, frequency:Float, gainDb:Float, q:Float):Void {
		checkBand(index);
		native.setBand(index, frequency, gainDb, q);
		bands[index].set({
			frequency: frequency,
			gainDb: gainDb,
			q: q,
			enabled: true
		});
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
		bands[index].set({
			frequency: band.frequency,
			gainDb: band.gainDb,
			q: band.q,
			enabled: false
		});
		changed();
	}

	/** Sets preamp gain from -60 to 0 dB. Negative gain reserves headroom for boosted bands. **/
	public function setPreamp(gainDb:Float):Void {
		checkOpen();
		native.setPreamp(gainDb);
		preamp.set(gainDb);
		changed();
	}

	/** Bypasses bands and preamp while preserving their settings. **/
	public function setBypass(value:Bool):Void {
		checkOpen();
		native.setBypass(value);
		bypassed.set(value);
		changed();
	}

	/** Resets band gains and preamp to zero, preserving frequencies, Q, and bypass state. **/
	public function flatten():Void {
		checkOpen();
		for (index in 0...bands.length) {
			var band = bands[index].get();
			native.setBand(index, band.frequency, 0, band.q);
			bands[index].set({
				frequency: band.frequency,
				gainDb: 0.0,
				q: band.q,
				enabled: true
			});
		}
		native.setPreamp(0);
		preamp.set(0);
		changed();
	}

	/** Processes borrowed input and returns owned interleaved F32 PCM. The caller must close the result. **/
	public function process(data:AudioData):AudioData {
		checkOpen();
		return native.process(data);
	}

	/** Clears the PCM filter history without changing settings. Playback histories remain owned by their players. **/
	public function reset():Void {
		checkOpen();
		native.reset();
	}

	/** Detaches players and restores flat playback. Repeated calls are safe; the equalizer cannot be reused after closing. **/
	public function close():Void {
		if (disposed)
			return;
		native.close();
		closed.set(true);
		changed();
		listeners.resize(0);
	}

	public inline function dispose():Void
		close();

	inline function get_disposed():Bool
		return closed.get();

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
		return () -> {
			listeners.remove(callback);
		};
	}

	function changed():Void {
		revision.set(revision.get() + 1);
		for (listener in listeners.copy())
			listener();
	}

	function checkBand(index:Int):Void {
		checkOpen();
		if (index < 0 || index >= bands.length)
			throw "Equalizer band index is out of range";
	}

	function checkOpen():Void {
		if (disposed)
			throw "Equalizer is closed";
	}
}
