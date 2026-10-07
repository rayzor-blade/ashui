import ashui.animation.AnimationScheduler;
import ashui.core.render.Snapshot;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.media.Audio;
import ashui.media.Equalizer;
import ashui.media.Video;
import ashui.media.Player;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;
import haxe.Int64;
import haxe.io.Bytes;
import media.AudioData;
import media.AudioDataCopyToOptions;
import media.AudioDataInit;
import media.AudioSampleFormat;
import window.Window;
import window.WindowAttributes;

/** Real native DSP, controller ownership and reactive HXX playback bindings. **/
class MediaEqualizerTest {
	static var checks = 0;
	static var pump:Window;
	static var last:Float;
	static function check(label:String, ok:Bool):Void {
		if (!ok) throw 'FAIL $label';
		checks++; Sys.println('ok $label');
	}
	static function rejects(fn:Void->Void):Bool {
		try fn() catch (_:Dynamic) return true;
		return false;
	}
	static function tick(?tree:LayoutTree):Void {
		pump.wait(0.01);
		var now = Sys.time(); AnimationScheduler.main.tick(now - last); last = now;
		if (tree != null) tree.flush();
	}
	static function waitFor(label:String, condition:Void->Bool, seconds = 8.0, ?tree:LayoutTree):Void {
		var deadline = Sys.time() + seconds;
		while (!condition() && Sys.time() < deadline) tick(tree);
		check(label, condition());
	}
	static function gain(source:Bytes, output:Bytes):Float {
		var a = 0.0, b = 0.0;
		for (i in 2400...4800) { a += Math.pow(source.getFloat(i * 4), 2); b += Math.pow(output.getFloat(i * 4), 2); }
		return 10 * Math.log(b / a) / Math.log(10);
	}
	static function dsp():Void {
		var eq = new Equalizer([1000]); eq.setGain(0, 6);
		var source = Bytes.alloc(4800 * 4);
		for (i in 0...4800) source.setFloat(i * 4, 0.1 * Math.sin(2 * Math.PI * 1000 * i / 48000));
		var input = AudioData.create(new AudioDataInit(F32, 48000, Int64.ofInt(4800), Int64.ofInt(1), Int64.ofInt(123), source));
		var output = Bytes.alloc(source.length);
		var filtered = eq.process(input);
		filtered.copyTo(output, new AudioDataCopyToOptions(Int64.ofInt(0)));
		check("equalizer performs native peaking-band DSP", Math.abs(gain(source, output) - 6) < 0.02);
		check("processed PCM preserves timing, channels and input ownership", Int64.toInt(filtered.timestamp()) == 123
			&& Int64.toInt(filtered.numberOfChannels()) == 1 && Int64.toInt(input.numberOfFrames()) == 4800 && filtered.format() == F32);
		filtered.close();
		eq.setPreamp(-6); eq.reset(); filtered = eq.process(input);
		filtered.copyTo(output, new AudioDataCopyToOptions(Int64.ofInt(0))); filtered.close();
		check("preamp provides headroom for boosted bands", Math.abs(gain(source, output)) < 0.02);
		var revision = eq.revision.get();
		check("invalid settings preserve the current equalizer", rejects(() -> eq.setGain(0, 25))
			&& rejects(() -> eq.setPreamp(1)) && rejects(() -> eq.setBand(0, Math.NaN, 0, 1))
			&& rejects(() -> eq.disableBand(1)) && eq.bands[0].get().gainDb == 6 && eq.preamp.get() == -6 && eq.revision.get() == revision);
		eq.setBypass(true); eq.reset(); filtered = eq.process(input); input.close();
		eq.close(); eq.close(); filtered.copyTo(output, new AudioDataCopyToOptions(Int64.ofInt(0))); filtered.close();
		check("bypass is exact and returned PCM survives closing its input and equalizer", output.compare(source) == 0 && eq.disposed);
		check("closed equalizers reject changes and processing", rejects(() -> eq.setBypass(false)) && rejects(() -> eq.reset()));
		check("invalid band counts and frequencies are rejected", rejects(() -> { new Equalizer([]); }) && rejects(() -> { new Equalizer([0]); }));
	}

	static function playback(path:String):Void {
		var eq = new Equalizer();
		var replacement = new Equalizer([125, 1000, 8000]);
		var selected = Signal.make((eq : Null<Equalizer>));
		var video = new Ref<Video>(); var audio = new Ref<Audio>();
		var tree = new LayoutTree(); var cleanup:Void->Void = null;
		Owner.root(tree, dispose -> {
			cleanup = dispose;
			return <div width={640} height={440} class="p-4 bg-surface gap-4">
				<video ref={video} src={path} muted={true} equalizer={selected} controls={false} width={608} height={360} />
				<audio ref={audio} equalizer={selected} controls={false} />
			</div>;
		});
		var player = video.get().player, audioPlayer = audio.get().player;
		waitFor("video opens with an HXX equalizer", () -> player.state.get() == Paused && player.videoWidth.get() > 0, 8, tree);
		check("both playback tags attach the shared controller", player.equalizer.get() == eq && audioPlayer.equalizer.get() == eq);
		player.play();
		waitFor("equalized native playback advances", () -> player.state.get() == Playing && player.position.get() > 0.15, 8, tree);
		eq.setBand(0, 80, 4, 0.7); eq.setPreamp(-6);
		check("live settings edits preserve playback, mute and volume", player.isPlaying() && player.muted.get() && player.volume.get() == 1
			&& player.error.get() == null && audioPlayer.error.get() == null);
		eq.setBypass(true);
		check("bypass retains configured settings", eq.bypassed.get() && eq.bands[0].get().gainDb == 4 && eq.preamp.get() == -6);
		eq.setBypass(false); eq.disableBand(0);
		check("individual bands can be disabled while retaining gain", !eq.bands[0].get().enabled && eq.bands[0].get().gainDb == 4 && player.isPlaying());
		eq.setGain(0, 3);
		check("gain edits re-enable a disabled band", eq.bands[0].get().enabled && eq.bands[0].get().gainDb == 3);
		eq.flatten();
		check("reset restores flat settings with the chosen frequencies", eq.preamp.get() == 0 && eq.bands[0].get().gainDb == 0 && eq.bands[0].get().frequency == 80);
		selected.set(replacement); tree.flush();
		check("reactive replacement updates both players", player.equalizer.get() == replacement && audioPlayer.equalizer.get() == replacement);
		selected.set(null); tree.flush();
		check("a null HXX equalizer restores flat playback", player.equalizer.get() == null && audioPlayer.equalizer.get() == null);
		selected.set(replacement); tree.flush();
		player.pause(); player.load(path);
		waitFor("equalizer persists across source reloads", () -> player.state.get() == Paused && player.videoWidth.get() > 0, 8, tree);
		check("reload keeps attached equalizer settings", player.equalizer.get() == replacement);
		replacement.close(); tree.flush();
		check("closing a shared equalizer detaches every player", player.equalizer.get() == null && audioPlayer.equalizer.get() == null);
		check("a closed replacement is rejected before detaching a working equalizer", {
			player.setEqualizer(eq);
			var rejected = rejects(() -> player.setEqualizer(replacement));
			rejected && player.equalizer.get() == eq;
		});
		cleanup(); tick();
		check("component cleanup releases players while preserving caller-owned equalizers", player.disposed && audioPlayer.disposed && !eq.disposed);
		eq.setGain(0, 3); eq.close();
		var owned:Equalizer = null; var detach:Void->Void = null;
		var independent = new Player();
		Owner.root(new LayoutTree(), dispose -> { detach = dispose; owned = new Equalizer(); independent.setEqualizer(owned); return 0; });
		detach();
		check("owner cleanup closes the equalizer and restores flat standalone playback", owned.disposed && independent.equalizer.get() == null);
		independent.close(); tick();
		check("equalizer disposal leaves no playback or auto-hide tickers", !AnimationScheduler.main.hasActive());
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Dark); Snapshot.renderer();
		var attrs = new WindowAttributes(); attrs.visible(false); attrs.active(false); attrs.width(1); attrs.height(1);
		pump = Window.open(attrs); last = Sys.time();
		try {
			dsp();
			var path = Sys.getEnv("ASHUI_VIDEO");
			if (path == null || path == "") path = Sys.getCwd() + "../../demo/assets/MediaPlayback.mp4";
			playback(path); pump.close();
			Snapshot.event('media-equalizer-tests $checks checks passed'); Sys.println('$checks equalizer checks passed');
		} catch (e:Dynamic) { pump.close(); throw e; }
	}
}
