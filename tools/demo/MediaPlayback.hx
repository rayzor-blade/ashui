import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.ToggleSwitch;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.media.Audio;
import ashui.media.Player;
import ashui.media.Video;
import ashui.media.VideoFit;
import ashui.media.VolumeControl;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.themes.DefaultTheme;
#if ashui_window
import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
#else
import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
#end

/**
	Native video with optional controls, plus a custom HXX audio player.
	Set ASHUI_VIDEO/ASHUI_AUDIO to other local files. assets/MediaPlayback.mp4
	is included with this example; the audio card can play its soundtrack too.

	    tools/demo/run.sh tools/demo/MediaPlayback.hx
	    tools/snapshot/run.sh tools/demo/MediaPlayback.hx
**/
class MediaPlayback {
	public static inline var WIDTH = 920;
	public static inline var HEIGHT = 820;
	static var styled = false;
	static var previewVideo:Player;
	static var previewAudio:Player;

	public static function videoPath():String {
		var custom = Sys.getEnv("ASHUI_VIDEO");
		if (custom != null && custom != "") return custom;
		for (path in ["../assets/MediaPlayback.mp4", "../../demo/assets/MediaPlayback.mp4", "tools/demo/assets/MediaPlayback.mp4"])
			if (sys.FileSystem.exists(path)) return sys.FileSystem.fullPath(path);
		throw "assets/MediaPlayback.mp4 was not found; set ASHUI_VIDEO to a local video file";
	}

	public static function page():Element {
		if (!styled) {
			ashui.media.Library.use();
			Css.add(CompiledCss.file("MediaPlayback.css"));
			styled = true;
		}
		var controls = Signal.make(true);
		var video = new Player(videoPath(), {muted: true, volume: 0.7});
		var audioPath = Sys.getEnv("ASHUI_AUDIO");
		var audio = new Player(audioPath == null || audioPath == "" ? videoPath() : audioPath);
		previewVideo = video;
		previewAudio = audio;
		Owner.onCleanup(video.close);
		Owner.onCleanup(audio.close);
		return <div class="mp-page" width={WIDTH} height={HEIGHT}>
			<div class="mp-header">
				<div class="flex flex-col gap-2">
					<text class="mp-eyebrow">ASHUI SESSIONS</text>
					<text class="mp-heading">A moment of sound.</text>
				</div>
				<badge variant={Secondary} appearance={Outline}>1920 × 1080</badge>
			</div>
			<video id="media-video" player={video} controls={controls} fit={VideoFit.Cover} class="mp-video" />
			<div class="mp-caption">
				<div class="flex flex-col gap-2">
					<text class="mp-title">Handpan in the open air</text>
					<text class="mp-subtitle">An outdoor session · Original recording</text>
				</div>
				<div class="mp-control-toggle">
					<text class="mp-subtitle">Playback controls</text>
					<toggle-switch checked={controls} size={Sm} />
				</div>
			</div>
			<audio id="media-audio" player={audio} controls={false} class="mp-audio">
				<div class="mp-art">
					<svg viewBox="0 0 48 48" width={40} height={40} fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
						<circle cx="24" cy="24" r="18" /><circle cx="24" cy="24" r="5" />
						<path d="M24 9v4M24 35v4M9 24h4M35 24h4M13.4 13.4l2.8 2.8M31.8 31.8l2.8 2.8M13.4 34.6l2.8-2.8M31.8 16.2l2.8-2.8" />
					</svg>
				</div>
				<div class="mp-audio-copy">
					<text class="mp-eyebrow">JUST LISTEN</text>
					<text class="mp-title">The same session, your own player.</text>
					<text class="mp-subtitle">${ashui.media.PlaybackControls.clock(audio.position.get()) + " / " + ashui.media.PlaybackControls.clock(audio.duration.get())}</text>
				</div>
				<div class="grow" />
				<button type="button" variant={Secondary} size={Icon} class="mp-audio-play" onClick={_ -> audio.toggle()}>${playIcon(audio)}</button>
				<volume-control player={audio} />
			</audio>
		</div>;
	}

	static function playIcon(player:Player):Element
		return <if {player.isPlaying()}>
			<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
				<path d="M8 5v14M16 5v14" />
			</svg>
		<else>
			<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
				<path d="M7 4v16l13-8z" />
			</svg>
		</if>;

	static function main() {
		#if ashui_window
		WindowedApp.run(new WindowConfig().title("Media playback").size(WIDTH, HEIGHT).theme(DefaultTheme.bundle()), page);
		#else
		ThemeState.init(DefaultTheme.bundle(), Dark);
		// Native media has a real clock and asynchronous platform callbacks;
		// snapshots pump that event loop before capturing a decoded frame.
		Snapshot.renderer();
		var attributes = new window.WindowAttributes();
		attributes.visible(false);
		attributes.active(false);
		attributes.width(1); attributes.height(1);
		var pump = window.Window.open(attributes);
		var tree = new ashui.layout.LayoutTree();
		var cleanup:Void->Void = null;
		var root = Owner.root(tree, dispose -> { cleanup = dispose; return page(); });
		var until = Sys.time() + 10;
		var last = Sys.time();
		while (previewVideo.videoWidth.get() == 0 || previewAudio.duration.get() == 0) {
			pump.wait(0.01);
			var now = Sys.time();
			ashui.animation.AnimationScheduler.main.tick(now - last);
			last = now;
			tree.flush();
			if (now > until || previewVideo.error.get() != null || previewAudio.error.get() != null) {
				cleanup(); pump.close();
				throw "Media did not open for the snapshot";
			}
		}
		tree.flush(); tree.computeLayout(root.node, WIDTH, HEIGHT);
		Snapshot.capture("MediaPlayback", tree, root.node, WIDTH, HEIGHT, 0x0e1420);
		cleanup(); pump.close();
		#end
	}
}
