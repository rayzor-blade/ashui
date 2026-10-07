import ashui.app.WindowedApp;
import ashui.canvaskit.CanvasKit;
import ashui.canvaskit.Geometry;
import ashui.canvaskit.SceneKit;
import ashui.components.Button;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.media.Audio;
import ashui.media.Equalizer;
import ashui.media.Video;
import ashui.reactive.Reactive;
import ashui.theme.themes.HybridTheme;

/** Compiled through installed Haxelibs, with their automatic framework macros. */
class Consumer {
	static function main() {
		Css.add(CompiledCss.file("consumer.css"));
		WindowedApp.run({title: "Package consumer", width: 640, height: 480, theme: HybridTheme.bundle()}, () -> {
			var count = signal(0);
			var label = computed(() -> 'Clicked ${count.get()} times');
			var equalizer = new Equalizer();
			var box = Geometry.box();
			return <div class="consumer p-4 gap-3" width={640} height={480}>
				<button type="button" onClick={_ -> count.set(count.get() + 1)}>${label.get()}</button>
				<canvas-kit width={160} height={100} />
				<scene-kit width={160} height={100} antialias={true} draw={ctx -> ctx.drawMesh(box)} />
				<video src={"video.mp4"} controls={false} equalizer={equalizer} />
				<audio src={"audio.mp3"} controls={false} equalizer={equalizer} />
			</div>;
		});
	}
}
