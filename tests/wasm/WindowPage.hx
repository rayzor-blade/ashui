import ashui.app.WindowedApp;
import ashui.components.Icon;
import ashui.icons.Remix;

/**
	An ashui window in a page: the canvas is the window, xgpu draws into it, and
	the loop runs on events the page sends (git-bug 0c8c9a0). A spinning icon
	keeps frames coming, as an idle window draws none. The program says when it
	is drawing so a driver can capture the canvas, and closes itself after a
	while.
**/
class WindowPage {
	static final SHOW_AFTER = 1.0;
	static final QUIT_AFTER = 4.0;
	static final FRAMES = 30;

	static var shown = false;

	static function main() {
		var frames = WindowedApp.run({
			title: "ashui in a page",
			width: 480,
			height: 300,
			onFrame: (n, elapsed) -> {
				if (!shown && elapsed >= SHOW_AFTER) {
					shown = true;
					Sys.println("drawing");
				}
				if (elapsed >= QUIT_AFTER)
					WindowedApp.current.quit();
			}
		}, () -> <div class="flex flex-col items-center justify-center gap-3 bg-background text-primary" width={480} height={300}>
			<icon document={Remix.LOADER_4_LINE} class="size-10 animate-spin" />
			<text class="text-2xl font-bold">Hello from a page</text>
			<text class="text-sm text-text-secondary">ashui, Arimo and Remix, drawn by xgpu</text>
		</div>);
		Sys.println('presented $frames frame(s)');
		if (frames < FRAMES)
			Sys.exit(1);
	}
}
