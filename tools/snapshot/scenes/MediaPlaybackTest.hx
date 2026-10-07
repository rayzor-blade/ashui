import ashui.animation.AnimationScheduler;
import ashui.components.Button;
import ashui.core.render.Snapshot;
import ashui.css.Identity;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.media.Audio;
import ashui.media.Player;
import ashui.media.Video;
import ashui.media.VideoFit;
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
import media.EncodedVideoChunk;
import media.EncodedVideoChunkInit;
import media.VideoFrame;
import media.VideoFrameBufferInit;
import media.VideoFrameCopyToOptions;
import media.VideoPixelFormat;
import window.Window;
import window.WindowAttributes;

/** Real native playback/lifecycle tests and offscreen video fit captures. No visible window. **/
class MediaPlaybackTest {
	static var pump:Window;
	static var last = 0.0;
	static var checks = 0;

	static function check(label:String, ok:Bool):Void {
		if (!ok) throw 'FAIL $label';
		checks++;
		Sys.println('ok $label');
	}

	static function tick(?tree:LayoutTree):Void {
		pump.wait(0.01);
		var now = Sys.time();
		AnimationScheduler.main.tick(now - last);
		last = now;
		if (tree != null) tree.flush();
	}

	static function waitFor(label:String, condition:Void->Bool, seconds = 8.0, ?tree:LayoutTree):Void {
		var deadline = Sys.time() + seconds;
		while (!condition() && Sys.time() < deadline) tick(tree);
		check(label, condition());
	}

	static function wave():String {
		var count = 48000;
		var bytes = Bytes.alloc(44 + count * 2);
		bytes.blit(0, Bytes.ofString("RIFF"), 0, 4); bytes.setInt32(4, bytes.length - 8);
		bytes.blit(8, Bytes.ofString("WAVEfmt "), 0, 8); bytes.setInt32(16, 16);
		bytes.setUInt16(20, 1); bytes.setUInt16(22, 1); bytes.setInt32(24, 48000);
		bytes.setInt32(28, 96000); bytes.setUInt16(32, 2); bytes.setUInt16(34, 16);
		bytes.blit(36, Bytes.ofString("data"), 0, 4); bytes.setInt32(40, count * 2);
		// Silence keeps the automated test quiet even if a backend ignores mute during opening.
		var path = haxe.io.Path.join([Snapshot.dir(), "media-test.wav"]);
		sys.FileSystem.createDirectory(Snapshot.dir());
		sys.io.File.saveBytes(path, bytes);
		return sys.FileSystem.absolutePath(path);
	}

	static function buffers():Void {
		var pcm = Bytes.alloc(8);
		pcm.setUInt16(0, 16384); pcm.setUInt16(2, 0); pcm.setUInt16(4, 49152); pcm.setUInt16(6, 32767);
		var audio = AudioData.create(new AudioDataInit(S16, 48000, Int64.ofInt(4), Int64.ofInt(1), Int64.ofInt(0), pcm));
		var options = new AudioDataCopyToOptions(Int64.ofInt(0)); options.format(F32);
		var floats = Bytes.alloc(Int64.toInt(audio.allocationSize(options))); audio.copyTo(floats, options);
		check("PCM format conversion remains available through hlavi", floats.length == 16 && Math.abs(floats.getFloat(0) - 0.5) < 0.0001);
		var audioClone = audio.clone(); audio.close();
		check("independent audio ownership", Int64.toInt(audioClone.numberOfFrames()) == 4); audioClone.close();
		var pixels = Bytes.alloc(16);
		for (i in 0...4) { pixels.set(i * 4, 255); pixels.set(i * 4 + 3, 255); }
		var video = VideoFrame.create(pixels, new VideoFrameBufferInit(RGBA, Int64.ofInt(2), Int64.ofInt(2), Int64.ofInt(123)));
		var copy = Bytes.alloc(16); var layouts = video.copyTo(copy, new VideoFrameCopyToOptions()).await();
		check("raw video frame copying and timing", copy.compare(pixels) == 0 && Int64.toInt(video.timestamp()) == 123 && layouts.count() == 1);
		layouts.close(); video.close();
		var chunk = EncodedVideoChunk.create(new EncodedVideoChunkInit(Key, Int64.ofInt(456), Bytes.ofString("encoded")));
		var payload = Bytes.alloc(Int64.toInt(chunk.byteLength())); chunk.copyTo(payload);
		check("encoded chunk bytes remain available without codec wrappers", payload.toString() == "encoded"); chunk.close();
	}

	static function audio(path:String):Void {
		var player = new Player(path, {muted: true});
		waitFor("audio opens paused", () -> player.duration.get() > 0.9 && player.state.get() == Paused);
		player.setVolume(0.35); player.setMuted(false);
		check("volume and mute are independent", player.volume.get() == 0.35 && !player.muted.get());
		player.setMuted(true); player.play();
		waitFor("native audio clock advances", () -> player.position.get() > 0.15);
		player.pause(); var stopped = player.position.get();
		var deadline = Sys.time() + 0.15; while (Sys.time() < deadline) tick();
		player.update(); check("pause holds native position", Math.abs(player.position.get() - stopped) < 0.04);
		player.seek(0.6);
		check("seek enters the FSM transient state", player.state.get() == Seeking);
		waitFor("paused audio seek settles", () -> player.state.get() == Paused && Math.abs(player.position.get() - 0.6) < 0.05);
		player.setLoop(true); player.seek(0.85); player.play();
		var wrapped = false; deadline = Sys.time() + 4;
		while (!wrapped && Sys.time() < deadline) { tick(); wrapped = player.state.get() == Playing && player.position.get() < 0.5; }
		check("audio loops at EOF", wrapped);
		player.setLoop(false); player.seek(0.85); player.play();
		waitFor("EOF is reported", () -> player.state.get() == Ended);
		player.play(); waitFor("play restarts ended media", () -> player.position.get() < 0.5 && player.state.get() == Playing);
		player.close(); player.close();
		check("close is terminal and idempotent", player.disposed && player.state.get() == Closed && player.currentFrame() == null);
		var rejected = false; try player.play() catch (_:Dynamic) rejected = true;
		check("closed controller rejects commands", rejected);
		var bad = new Player(path + ".missing");
		check("open failures become reactive errors", bad.state.get() == Failed && bad.error.get() != null);
		bad.load(path); waitFor("a failed player can load a new source", () -> bad.state.get() == Paused);
		bad.close();
	}

	static function classCount(tree:LayoutTree, node:haxe.Int64, name:String):Int {
		var identity = Identity.of(tree, node);
		var count = identity != null && identity.classes().contains(name) ? 1 : 0;
		for (child in tree.children(node)) count += classCount(tree, child, name);
		return count;
	}

	static function findClass(tree:LayoutTree, name:String):Node {
		for (id in tree.order()) {
			var identity = Identity.of(tree, id);
			if (identity != null && identity.hasClass(name)) return identity.node;
		}
		throw 'Missing .$name';
	}

	static function frameTime(player:Player):Float {
		var frame = player.currentFrame();
		if (frame == null) return -1;
		var seconds = Int64.toInt(frame.timestamp()) / 1000000.0;
		frame.close();
		return seconds;
	}

	static function interactions(path:String):Void {
		var player = new Player(path, {muted: true});
		var tree = new LayoutTree(); var cleanup:Void->Void = null;
		var video = new Ref<Video>();
		var autoHide = Signal.make(true);
		var root:Element = Owner.root(tree, dispose -> {
			cleanup = dispose;
			return <div width={640} height={400} class="p-4 bg-surface">
				<video ref={video} player={player} autoHideControls={autoHide} controlsHideDelay={0.35} width={608} height={368} />
			</div>;
		});
		function layout() {
			tree.flush(); tree.computeLayout(root.node, 640, 400);
			tree.flush(); tree.computeLayout(root.node, 640, 400);
		}
		function click(node:Node) {
			layout(); var b = tree.getBounds(node);
			Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
			Pointer.press(tree); Pointer.release(tree); layout();
		}
		function key(k:window.Key, code:window.KeyCode, pressed = true):Void
			ashui.input.Keyboard.input(tree, Input(Code(code), k, None, Standard, pressed ? Pressed : Released, false, Unavailable));
		function elapse(seconds:Float) {
			var until = Sys.time() + seconds;
			while (Sys.time() < until) tick(tree);
			layout();
		}
		waitFor("interactive video opens", () -> player.videoWidth.get() > 0 && player.duration.get() > 0, 8, tree);
		layout();
		var slider = findClass(tree, "ui-media-timeline");
		var bounds = tree.getBounds(slider);
		var playBounds = tree.getBounds(findClass(tree, "ui-media-play"));
		var volumeBounds = tree.getBounds(findClass(tree, "ui-media-volume-control"));
		var timeBounds = tree.getBounds(findClass(tree, "ui-media-time"));
		var middle = playBounds.y + playBounds.height / 2;
		check("timeline, time and speaker align with transport icons",
			Math.abs(bounds.y + bounds.height / 2 - middle) < 0.5
			&& Math.abs(volumeBounds.y + volumeBounds.height / 2 - middle) < 0.5
			&& Math.abs(timeBounds.y + timeBounds.height / 2 - middle) < 0.5);
		var target = player.duration.get() * 0.5;
		check("timeline enables when asynchronous metadata arrives", !ashui.input.Interaction.of(slider).disabled.get());
		Pointer.move(tree, bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
		Pointer.press(tree); Pointer.release(tree); tree.flush();
		waitFor("a timeline click seeks the actual paused video", () -> player.state.get() == Paused && Math.abs(frameTime(player) - target) < 0.1, 8, tree);
		check("paused seeking preserves play intent", !player.isPlaying());
		var thumb = tree.getBounds(new Node(tree.children(slider.id)[1]));
		function dragTo(fraction:Float) {
			Pointer.move(tree, bounds.x + thumb.width / 2 + (bounds.width - thumb.width) * fraction, bounds.y + bounds.height / 2);
			tree.flush();
		}
		dragTo(0.2); Pointer.press(tree);
		for (fraction in [0.65, 0.4, 0.75, 0.35]) { tick(tree); dragTo(fraction); }
		Pointer.release(tree); tree.flush(); target = player.duration.get() * 0.35;
		waitFor("rapid drag seeks decode the final requested frame", () -> player.state.get() == Paused && Math.abs(frameTime(player) - target) < 0.1, 8, tree);
		key(Named(PageUp), PageUp); key(Named(PageUp), PageUp, false); tree.flush();
		target = player.duration.get() * 0.45;
		waitFor("keyboard timeline edits seek video", () -> player.state.get() == Paused && Math.abs(frameTime(player) - target) < 0.1, 8, tree);
		ashui.input.Focus.clear(tree); tree.flush();
		click(findClass(tree, "ui-media-play"));
		waitFor("play icon starts playback", () -> player.isPlaying() && player.position.get() > target + 0.1, 8, tree);
		dragTo(0.15); Pointer.press(tree); Pointer.release(tree); tree.flush(); target = player.duration.get() * 0.15;
		waitFor("seeking during playback resumes at the requested frame", () -> player.state.get() == Playing && Math.abs(frameTime(player) - target) < 0.3, 8, tree);
		waitFor("playing controls auto-hide after inactivity", () -> !video.get().controlsVisible.get(), 2, tree);
		var hiddenHits = tree.hitTest(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
		check("hidden controls do not intercept pointer input", !Lambda.exists(hiddenHits, hit -> hit.id == slider.id));
		layout(); Snapshot.capture("media-controls-hidden", tree, root.node, 640, 400);
		Pointer.leave(tree); Pointer.move(tree, 320, 160); tree.flush();
		check("returning the pointer to video reveals controls", video.get().controlsVisible.get());
		autoHide.set(false); tree.flush(); elapse(0.5);
		check("auto-hide can be disabled reactively", video.get().controlsVisible.get());
		autoHide.set(true); tree.flush();
		click(findClass(tree, "ui-media-volume-trigger"));
		check("speaker icon opens the volume popover", ashui.ui.TopLayer.openEntries().length == 1);
		elapse(0.5);
		check("an open volume popover keeps playing controls visible", video.get().controlsVisible.get());
		var panel = ashui.ui.TopLayer.openEntries()[0].content;
		var panelBounds = tree.getBounds(panel.node);
		check("volume panel stays compact", panelBounds.width <= 225 && panelBounds.height <= 60);
		click(findClass(tree, "ui-media-mute"));
		check("mute icon restores the retained volume", !player.muted.get() && player.volume.get() == 1);
		var volumeSlider:Node = null;
		for (id in tree.order()) {
			var identity = Identity.of(tree, id);
			if (identity != null && identity.hasClass("ui-slider") && tree.ancestors(id).contains(panel.node.id)) volumeSlider = identity.node;
		}
		click(volumeSlider);
		check("volume slider changes native volume", Math.abs(player.volume.get() - 0.5) < 0.01 && !player.muted.get());
		layout(); Snapshot.capture("media-volume", tree, root.node, 640, 400, 0x0e1420, 1, 2);
		key(Named(Escape), Escape); key(Named(Escape), Escape, false); tree.flush();
		Pointer.move(tree, 320, 160); Pointer.press(tree); Pointer.release(tree); tree.flush();
		waitFor("dismissed volume popover lets controls hide again", () -> !video.get().controlsVisible.get(), 2, tree);
		player.pause(); tree.flush(); elapse(0.5);
		check("pausing restores controls and keeps them visible", video.get().controlsVisible.get());
		click(slider);
		ashui.input.Focus.set(ashui.input.Interaction.of(slider), true); tree.flush();
		player.play(); tree.flush(); elapse(0.5);
		check("keyboard focus keeps controls visible", video.get().controlsVisible.get());
		player.pause(); tree.flush();
		layout(); Snapshot.capture("media-controls", tree, root.node, 640, 400, 0x0e1420, 1, 2);
		cleanup(); player.close(); tick();
		check("auto-hide timers and playback tickers clean up", !AnimationScheduler.main.hasActive());
	}

	static function video(path:String, audioPath:String):Void {
		var player = new Player(path, {muted: true});
		waitFor("video decodes a paused preview frame", () -> player.videoWidth.get() > 0);
		var retained = player.currentFrame();
		check("native video dimensions", player.videoWidth.get() == 1920 && player.videoHeight.get() == 1080);
		var controls = Signal.make(true);
		var source = Signal.make(path);
		var owned = new Ref<Video>(); var hidden = new Ref<Video>();
		var customAudio = new Ref<Audio>();
		var tree = new LayoutTree(); var cleanup:Void->Void = null;
		var root:Element = Owner.root(tree, dispose -> {
			cleanup = dispose;
			return <div width={880} height={450} class="flex flex-col gap-4 p-4 bg-surface">
				<div class="flex flex-row gap-4">
					<video ref={hidden} player={player} controls={false} fit={VideoFit.Contain} width={272} height={240} />
					<video player={player} controls={false} fit={VideoFit.Cover} width={272} height={240} />
					<video player={player} controls={false} fit={VideoFit.Fill} width={272} height={240} />
				</div>
				<audio ref={customAudio} controls={controls} src={audioPath} muted={true}>
					<button type="button" variant={Outline} size={Sm}>Custom HXX child</button>
				</audio>
				<video ref={owned} src={source} muted={true} controls={false} width={200} height={60} />
			</div>;
		});
		var ownPlayer = owned.get().player;
		waitFor("component source opens", () -> ownPlayer.videoWidth.get() > 0, 8, tree);
		tree.flush(); tree.computeLayout(root.node, 880, 450);
		check("default controls exist once", classCount(tree, root.node.id, "ui-media-controls") == 1);
		Snapshot.capture("media-fits", tree, root.node, 880, 450);
		controls.set(false); tree.flush(); tree.computeLayout(root.node, 880, 450);
		check("controls can be removed reactively", classCount(tree, root.node.id, "ui-media-controls") == 0);
		check("custom HXX children remain", classCount(tree, customAudio.get().node.id, "ui-button") == 1);
		Snapshot.capture("media-custom-controls", tree, root.node, 880, 450);
		player.play(); waitFor("video produces subsequent frames", () -> player.position.get() > 0.15, 8, tree);
		player.pause(); var before = player.frameVersion.get(); player.seek(3);
		var deadline = Sys.time() + 8;
		while (!(player.frameVersion.get() > before && player.state.get() == Paused) && Sys.time() < deadline) tick(tree);
		check("paused seek replaces video frame", player.frameVersion.get() > before && player.state.get() == Paused && Math.abs(frameTime(player) - 3) < 0.1);
		tree.flush(); tree.computeLayout(root.node, 880, 450); Snapshot.capture("media-seek", tree, root.node, 880, 450);
		check("caller-held frame survives later frames", Int64.toInt(retained.codedWidth()) == 1920); retained.close();
		hidden.get().remove(); check("removing a shared video leaves its player alive", !player.disposed);
		source.set(""); tree.flush();
		check("empty reactive source releases its frame", ownPlayer.state.get() == Empty && ownPlayer.currentFrame() == null);
		source.set(path); tree.flush(); waitFor("reactive source can reopen", () -> ownPlayer.videoWidth.get() > 0, 8, tree);
		cleanup(); check("component-owned player closes on unmount", ownPlayer.disposed && customAudio.get() == null);
		check("shared controller survives component cleanup", !player.disposed);
		player.close(); tick();
		check("no playback ticker remains after closing", !AnimationScheduler.main.hasActive());
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		Snapshot.renderer(); // GPU futures are resolved before the native event loop opens.
		var attrs = new WindowAttributes(); attrs.visible(false); attrs.active(false); attrs.width(1); attrs.height(1);
		pump = Window.open(attrs); last = Sys.time();
		try {
			buffers(); var audioPath = wave(); audio(audioPath);
			var path = Sys.getEnv("ASHUI_VIDEO");
			if (path == null || path == "") path = Sys.getCwd() + "../../demo/assets/MediaPlayback.mp4";
			video(path, audioPath); interactions(path); pump.close();
			Snapshot.event('media-tests $checks checks passed');
			Sys.println('$checks media checks passed');
		} catch (e:Dynamic) { pump.close(); throw e; }
	}
}
