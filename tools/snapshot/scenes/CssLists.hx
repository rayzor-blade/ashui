import ashui.components.Badge;
import ashui.components.Card;
import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Existing list markers, inherited CSS, individual overrides and marker removal. **/
class CssLists {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var sheet = Css.load('#steps { list-style-type: lower-roman; } #supplies { list-style-type: square; } #supplies > li:last-child { list-style-type: circle; }');
		Snapshot.sequence("css-lists", 840, 434, () -> <div class="bg-background p-6 flex-col gap-4" width={840} height={434}>
			<text class="text-2xl font-semibold">Familiar lists, styled with CSS</text>
			<text class="text-text-secondary">Existing counters and bullets follow the inherited marker style.</text>
			<div class="flex-row gap-4">
				<card width={388}>
					<card-header><card-title>Release checklist</card-title><card-description>Start at three · preserve item ordinals</card-description></card-header>
					<card-content class="flex-col gap-3">
						<badge appearance={Outline}>Ordered markers</badge>
						<ol id="steps" start={3} width={340}>
							<li>Review the changes</li>
							<li>Capture dark and light snapshots</li>
							<li value={8}>Publish the package</li>
						</ol>
						<text class="text-sm text-text-tertiary">Next frame: decimal-leading-zero</text>
					</card-content>
				</card>
				<card width={388}>
					<card-header><card-title>Quality checks</card-title><card-description>Nested inheritance · per-item override</card-description></card-header>
					<card-content class="flex-col gap-3">
						<badge variant={Success}>Built-in list elements</badge>
						<ul id="supplies" width={340}>
							<li>Inspect each theme<ul><li>Check compact layouts</li></ul></li>
							<li>Verify pointer feedback</li>
						</ul>
						<text class="text-sm text-text-tertiary">Next frame: no markers or marker space</text>
					</card-content>
				</card>
			</div>
		</div>, 30, 2, (frame, _, _) -> {
			if (frame == 1) {
				var next = ashui.css.Stylesheet.parse('#steps { list-style-type: decimal-leading-zero; } #supplies { list-style-type: none; }');
				Css.replace(sheet, next);
			}
		}, ThemeState.get().color(Background).rgb());
	}
}
