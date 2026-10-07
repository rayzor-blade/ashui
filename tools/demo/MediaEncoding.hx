import ashui.components.Badge;
import ashui.components.Button;
import ashui.core.render.Snapshot;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.media.Codec;
import ashui.media.Player;
import ashui.media.Stream;
import ashui.media.Video;
import ashui.media.VideoFit;
import ashui.reactive.Owner;
import ashui.theme.themes.DefaultTheme;
import haxe.Int64;
import haxe.io.Bytes;
import media.CodecConfiguration;
import media.EncodedVideoChunk;
import media.MediaMuxer;
import media.StreamReadStatus;
import media.VideoFrame;
import media.VideoFrameBufferInit;
import media.VideoPixelFormat;
#if ashui_window
import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
#else
import ashui.theme.ThemeState;
#end

private typedef Recording = {
	path:String,
	frames:Int,
	packets:Int,
	bytes:Int,
	elapsed:Float
}

/**
	Stream generated frames through native H.264 encoding and MP4 writing,
	then play the exported file with the existing HXX video component.
	Generation runs before the window opens; native encoding runs on a worker.

	    tools/demo/run.sh tools/demo/MediaEncoding.hx
	    tools/snapshot/run.sh tools/demo/MediaEncoding.hx
**/
class MediaEncoding {
	static inline var WIDTH = 920;
	static inline var HEIGHT = 720;
	static inline var FRAME_WIDTH = 320;
	static inline var FRAME_HEIGHT = 180;
	static inline var FPS = 24;
	static inline var FRAMES = 48;
	static var preview:Player;
	static var styled = false;

	static function frame(index:Int):VideoFrame {
		var progress = index / (FRAMES - 1);
		var cx = 32 + progress * (FRAME_WIDTH - 64);
		var cy = FRAME_HEIGHT / 2 + 32 * Math.sin(progress * Math.PI * 2);
		var pixels = Bytes.alloc(FRAME_WIDTH * FRAME_HEIGHT * 4);
		for (y in 0...FRAME_HEIGHT) for (x in 0...FRAME_WIDTH) {
			var at = (y * FRAME_WIDTH + x) * 4;
			var ball = (x - cx) * (x - cx) + (y - cy) * (y - cy) < 22 * 22;
			pixels.set(at, ball ? 204 : 36 + Std.int(x / 10));
			pixels.set(at + 1, ball ? 223 : 23 + Std.int(y / 10));
			pixels.set(at + 2, ball ? 154 : 22 + Std.int(x / 20));
			pixels.set(at + 3, 255);
		}
		var timestamp = Std.int(index * 1000000.0 / FPS);
		var end = Std.int((index + 1) * 1000000.0 / FPS);
		var init = new VideoFrameBufferInit(BGRA, Int64.ofInt(FRAME_WIDTH), Int64.ofInt(FRAME_HEIGHT), Int64.ofInt(timestamp));
		init.duration(Int64.ofInt(end - timestamp));
		return VideoFrame.create(pixels, init);
	}

	static function record():Recording {
		var dir = Snapshot.dir(); sys.FileSystem.createDirectory(dir);
		var path = sys.FileSystem.fullPath(dir) + '/media-encoding-${Std.int(Sys.time())}-${Std.random(1000000)}.mp4';
		var stream = Stream.video({maxItems: 2, maxBytes: FRAME_WIDTH * FRAME_HEIGHT * 4 * 2});
		var encoder = Codec.videoEncoder({width: FRAME_WIDTH, height: FRAME_HEIGHT, framerate: FPS, bitrate: 600000,
			limits: {maxItems: 2, maxBytes: 1048576}});
		var config:Null<CodecConfiguration> = null, writer:Null<MediaMuxer> = null;
		var generated:Null<VideoFrame> = null, pending:Null<VideoFrame> = null;
		var chunk:Null<EncodedVideoChunk> = null;
		var index = 0, packets = 0, bytes = 0;
		var started = Sys.time(), deadline = started + 30;
		var inputFinished = false, encoderFinished = false;
		try {
			while (encoder.poll() != Ended || chunk != null) {
				if (index < FRAMES && generated == null) generated = frame(index);
				if (generated != null && stream.tryWrite(generated)) { generated.close(); generated = null; index++; }
				if (index == FRAMES && !inputFinished) { stream.finish(); inputFinished = true; }
				if (pending == null && stream.poll() == Ready) pending = stream.read();
				if (pending != null && encoder.tryWrite(pending)) { pending.close(); pending = null; }
				if (pending == null && stream.poll() == Ended && !encoderFinished) { encoder.finish(); encoderFinished = true; }
				if (chunk == null && encoder.poll() == Ready) {
					if (writer == null) {
						config = encoder.getConfiguration();
						writer = MediaMuxer.video(path, config, Int64.ofInt(0), Int64.ofInt(Std.int(1000000 / FPS)), 2, Int64.ofInt(1048576));
					}
					chunk = encoder.read(); packets++; bytes += Int64.toInt(chunk.byteLength());
				}
				if (chunk != null && writer.writeVideoChunk(chunk)) { chunk.close(); chunk = null; }
				if (Sys.time() > deadline) throw "Native encoding timed out";
				Sys.sleep(0.001);
			}
			writer.endVideoTrack(); writer.finish();
			while (!writer.finished()) {
				if (Sys.time() > deadline) throw "Native MP4 finalization timed out";
				Sys.sleep(0.001);
			}
		} catch (e:Dynamic) {
			if (generated != null) generated.close(); if (pending != null) pending.close(); if (chunk != null) chunk.close();
			if (writer != null) writer.close(); if (config != null) config.close(); encoder.close(); stream.close(); throw e;
		}
		writer.close(); config.close(); encoder.close(); stream.close();
		return {path: path, frames: index, packets: packets, bytes: bytes, elapsed: Sys.time() - started};
	}

	static function page(recording:Recording):Element {
		if (!styled) { ashui.media.Library.use(); Css.add(CompiledCss.file("MediaPlayback.css")); styled = true; }
		var player = preview = new Player(recording.path, {muted: true, loop: true});
		Owner.onCleanup(player.close);
		return <div class="mp-page" width={WIDTH} height={HEIGHT}>
			<div class="mp-header">
				<div class="flex flex-col gap-2">
					<text class="mp-eyebrow">NATIVE MEDIA LAB</text>
					<text class="mp-heading">Built from frames.</text>
				</div>
				<badge variant={Secondary} appearance={Outline}>H.264 · MP4</badge>
			</div>
			<video player={player} fit={VideoFit.Contain} class="mp-video" />
			<div class="mp-caption">
				<div class="flex flex-col gap-2">
					<text class="mp-title">A native encoding round trip</text>
					<text class="mp-subtitle">${recording.frames + " frames · 24 fps · " + Math.round(recording.bytes / 1024) + " KB · Encoded in " + Math.round(recording.elapsed * 100) / 100 + "s"}</text>
				</div>
				<button type="button" variant={Outline} size={Sm} onClick={_ -> { player.seek(0); player.play(); }}>Replay clip</button>
			</div>
		</div>;
	}

	static function main():Void {
		var recording = record();
		Sys.println('Encoded ${recording.frames} frames into ${recording.packets} packets: ${recording.path}');
		#if ashui_window
		WindowedApp.run(new WindowConfig().title("Media encoding").size(WIDTH, HEIGHT).theme(DefaultTheme.bundle()), () -> page(recording));
		#else
		ThemeState.init(DefaultTheme.bundle(), Dark); Snapshot.renderer();
		var attributes = new window.WindowAttributes(); attributes.visible(false); attributes.active(false); attributes.width(1); attributes.height(1);
		var pump = window.Window.open(attributes);
		var tree = new ashui.layout.LayoutTree(); var cleanup:Void->Void = null;
		var root = Owner.root(tree, dispose -> { cleanup = dispose; return page(recording); });
		var deadline = Sys.time() + 10, last = Sys.time();
		while (preview.videoWidth.get() == 0) {
			pump.wait(0.01); var now = Sys.time(); ashui.animation.AnimationScheduler.main.tick(now - last); last = now; tree.flush();
			if (now > deadline || preview.error.get() != null) { cleanup(); pump.close(); throw "Encoded clip did not open"; }
		}
		tree.flush(); tree.computeLayout(root.node, WIDTH, HEIGHT);
		Snapshot.capture("MediaEncoding", tree, root.node, WIDTH, HEIGHT, 0x0e1420);
		cleanup(); pump.close();
		#end
	}
}
