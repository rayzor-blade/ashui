import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.core.render.Snapshot;
import ashui.input.Scroll;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Ref;

/** Inset shadows at the edges of a scroll area that hide content (`scroll-shadow: auto`): at the top, in the middle, at the end (bd8f627). **/
class ScrollShadows {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		Css.add(CompiledCss.file("ScrollShadows.css"));
		var pane = new Ref<Div>();
		var build = () -> <div class="bg-background p-6 flex-col gap-3" width={380} height={300}>
			<text class="text-sm text-secondary">scroll-shadow: auto</text>
			<div ref={pane} id="pane">${[for (i in 0...20) <div class="line"><text>${"Row " + (i + 1)}</text></div>]}</div>
		</div>;
		Snapshot.sequence(light ? "ScrollShadows-light" : "ScrollShadows", 380, 300, build, 30, 3, (frame, tree, root) -> {
			if (frame == 0) return;
			var s = Scroll.of(pane.get().node);
			if (frame == 1) s.scrollTo(0, 150);
			if (frame == 2) s.scrollTo(0, 100000);
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
