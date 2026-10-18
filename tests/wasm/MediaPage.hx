import media.MediaPlayer;
import media.PlaybackState;

/**
	What a program in a page needs of hlavi: a media player that opens a file beside the page, plays it, pauses, seeks and
	plays to its end, and says that the rest of xavi is not in a page. `tone.wav`, two seconds, is beside it.
**/
class MediaPage {
	static var checks = 0;
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (ok) {
			checks++;
			Sys.println('ok   $name');
		} else {
			failures++;
			Sys.println('FAIL $name' + (detail == null ? "" : ": " + Std.string(detail)));
		}
	}

	static function near(a:Float, b:Float, within = 0.05)
		return Math.abs(a - b) < within;

	/** Waits, up to `seconds`, for `ok`; true when it came. **/
	static function until(ok:Void->Bool, seconds = 15.0):Bool {
		var begin = Sys.time();
		while (!ok()) {
			if (Sys.time() - begin > seconds)
				return false;
			Sys.sleep(0.02);
		}
		return true;
	}

	static function main() {
		var player = MediaPlayer.open("tone.wav");
		check("a file beside the page opens", true);
		check("it is opening, or paused once its metadata is in", player.state() == Opening || player.state() == Paused, player.state());
		check("its duration is known", until(() -> player.duration() > 0), player.duration());
		check("it is two seconds", near(player.duration(), 2.0), player.duration());
		player.setVolume(0.25);
		check("its volume is as set", near(player.volume(), 0.25, 0.001), player.volume());
		player.setVolume(7);
		check("a volume is kept to one", near(player.volume(), 1.0, 0.001), player.volume());

		player.play();
		check("it plays", until(() -> player.state() == Playing), player.state());
		check("its position moves", until(() -> player.position() > 0.4), player.position());
		player.pause();
		check("it pauses", until(() -> player.state() == Paused), player.state());
		var at = player.position();
		Sys.sleep(0.3);
		check("a paused player stays where it was", near(player.position(), at, 0.02), [at, player.position()]);

		player.seek(1.5);
		check("a seek reads back at once", near(player.position(), 1.5, 0.001), player.position());
		player.play();
		check("it plays to its end", until(() -> player.state() == Ended), player.state());
		check("and its position is its duration", near(player.position(), player.duration(), 0.1), player.position());
		check("a video frame is never ready", !player.pollFrame());

		player.close();
		var raised = false;
		try
			player.state()
		catch (e:Dynamic)
			raised = true;
		check("a closed player raises", raised);

		var missing = MediaPlayer.open("there-is-no-such-file.wav");
		var failed = false;
		until(() -> {
			try
				missing.state()
			catch (e:Dynamic)
				failed = true;
			failed;
		});
		check("a file that is not there raises, saying so", failed);

		var absent = false;
		try
			media.AudioEqualizer.create(1)
		catch (e:Dynamic)
			absent = Std.string(e).indexOf("not available on the web") >= 0;
		check("the rest of xavi says it is not available on the web", absent);

		Sys.println(failures == 0 ? 'ALL PASSED ($checks checks)' : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
