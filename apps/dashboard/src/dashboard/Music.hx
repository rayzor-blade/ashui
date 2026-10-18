package dashboard;

import ashui.animation.AnimationScheduler;
import ashui.media.Player;
import ashui.media.Player.PlayerState;
import ashui.reactive.Signal;
import haxe.io.Bytes;

typedef Track = {file:String, title:String, artist:String, album:String, hue:Int, genre:String, seconds:Float};

/**
	The soundtrack: an original instrumental (`tools/compose.py`) and two CC0 recordings (`tools/prepare.py`), played by an `ashui.media.Player`, which on a desktop
	is hlavi's native player and in a page is hlavi's, on an audio element. This keeps what a player does not: the playlist, the
	track that is current, going on to the next when one ends, and the loudness of each band of the sound, which the visualiser
	reads from the track's `.bands` file by how far the track has played.
**/
class Music {
	public static final TRACKS:Array<Track> = [
		{file: "night-drive", title: "Night Drive", artist: "Ash Drive", album: "Original Soundtrack", hue: 265, genre: "Electronic", seconds: 65.6},
		{file: "lofi-fusion", title: "Lofi Fusion", artist: "Seth Makes Sounds", album: "Freesound", hue: 195, genre: "Lo-fi", seconds: 131.2},
		{file: "cosmic-dark-synthwave", title: "Cosmic Dark Synthwave", artist: "Projecteur", album: "Freesound", hue: 320, genre: "Synthwave", seconds: 104.4}
	];

	/** Bands the visualiser has, and how many sets of them a second. **/
	public static inline var BANDS = 16;

	static inline var RATE = 30;

	/** Where the files are, beside the page or where a desktop build runs. **/
	static inline var DIRECTORY = "audio/";

	public final player:Player;
	public final index = Signal.make(0);
	public final shuffle = Signal.make(false);
	public final repeat = Signal.make(false);
	public final volume = Signal.make(0.8);

	final levels = new Map<Int, Bytes>();
	var started = false;
	var reportedAt = 0.0;

	public function new() {
		player = new Player(null, {volume: 0.8});
		select(0, false);
		// The player reports its position about ten times a second; the time since it did is how far on it is now.
		new ashui.reactive.Watch(() -> player.position.get(), _ -> reportedAt = haxe.Timer.stamp());
		// A track that has played to its end is followed by the next, unless one is to go round again.
		AnimationScheduler.main.addTicker(_ -> {
			if (started && player.state.get() == PlayerState.Ended)
				advance(1, true);
			true;
		});
	}

	public function current():Track
		return TRACKS[index.get()];

	/** Makes track `i` the current one, playing it from the start if `play`. **/
	public function select(i:Int, play:Bool):Void {
		var n = TRACKS.length;
		i = ((i % n) + n) % n;
		index.set(i);
		if (play)
			started = true;
		player.load(DIRECTORY + TRACKS[i].file + ".m4a", play);
	}

	/** The next track, or the one before: shuffled, a random other one. **/
	public function advance(by:Int, play:Bool):Void {
		if (repeat.get() && by == 1 && play && player.state.get() == PlayerState.Ended) {
			select(index.get(), true);
			return;
		}
		var n = TRACKS.length;
		var next = shuffle.get() && n > 1 ? (index.get() + 1 + Std.random(n - 1)) % n : index.get() + by;
		select(next, play);
	}

	public function toggle():Void {
		started = true;
		player.toggle();
	}

	public function playing():Bool
		return player.isPlaying();

	public function seekFraction(f:Float):Void {
		var d = player.duration.get();
		if (d > 0)
			player.seek(Math.max(0, Math.min(1, f)) * d);
	}

	public function setVolume(v:Float):Void {
		volume.set(v);
		player.setVolume(v);
	}

	function frames(i:Int):Bytes {
		var known = levels.get(i);
		if (known == null) {
			known = try ashui.core.Assets.bytes("assets/levels/" + TRACKS[i].file + ".bands") catch (e:Dynamic) Bytes.alloc(0);
			levels.set(i, known);
		}
		return known;
	}

	/** Where the track is now, between the player's reports of it. **/
	public function livePosition():Float {
		var p = player.position.get();
		if (!player.isPlaying())
			return p;
		var d = player.duration.get();
		var now = p + Math.max(0, Math.min(0.25, haxe.Timer.stamp() - reportedAt));
		return d > 0 ? Math.min(d, now) : now;
	}

	/** How loud band `band` is at `position`, 0 to 1. **/
	public function level(band:Int, position:Float):Float {
		var data = frames(index.get());
		var frame = Std.int(position * RATE);
		var at = frame * BANDS + band;
		if (data.length == 0 || at < 0 || at >= data.length)
			return 0;
		return data.get(at) / 255;
	}

	/** `seconds` as the player shows them: 3:07. **/
	public static function clockText(seconds:Float):String {
		var s = Std.int(Math.max(0, seconds));
		return Std.int(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
	}
}
