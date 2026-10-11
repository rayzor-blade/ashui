import ashui.components.Badge;
import ashui.components.Card;
import ashui.debug.MotionRecorder;
import ashui.css.Css;
import ashui.input.Scroll;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** CSS layout milestones: git-bug 6812621, 3a58858 and 7977648 (ordering). **/
class CssLayout {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var order = Signal.make(2);
		Css.load('
			#heading { position: sticky; top: 0; z-index: 10; background: var(--surface-elevated); }
			#summary { line-clamp: 2; margin: 0; font-size: 16px; line-height: 1.5; color: var(--text-secondary); }
		');
		MotionRecorder.record("css-layout", 880, 644, () -> <div class="bg-background p-6 flex-col gap-4" width={880} height={644}>
			<text class="text-2xl font-semibold">CSS layout and text</text>
			<text class="text-text-secondary">Sticky headings, consistent stacking, and text that fits.</text>
			<div class="flex-row gap-6">
				<card width={400}>
					<card-header><card-title>Scroll and stay in view</card-title><card-description>position: sticky · top: 0 · z-index: 10</card-description></card-header>
					<card-content>
						<div id="scroll" class="overflow-y-auto flex-col rounded-lg border border-border" width={352} height={224}>
							<div class="p-3 text-text-tertiary" height={40} flexShrink={0}><text>Project activity</text></div>
							<div id="heading" class="flex-row items-center justify-between p-3" height={44} flexShrink={0}>
								<text class="font-semibold">Today</text><badge variant={Success}>8 updates</badge>
							</div>
							<for {i in [0, 1, 2, 3, 4, 5, 6, 7]}>
								<div class="flex-row items-center gap-3 p-3 border-b border-border" height={48} flexShrink={0}>
									<badge appearance={Outline}>{i + 1}</badge>
									<text class="truncate text-text-secondary" width={256}>{["Design review complete", "Native rendering verified", "Typography and spacing updated", "Scroll behavior checked", "Interaction tests passing", "Styles follow the active theme", "Playback controls aligned", "Ready for the next milestone"][i]}</text>
								</div>
							</for>
						</div>
					</card-content>
				</card>
				<card width={408}>
					<card-header><card-title>Text and layers</card-title><card-description>Ellipsis · line-clamp · sibling stacking</card-description></card-header>
					<card-content class="flex-col gap-4">
						<text class="truncate font-semibold" width={360}>A long title that ends neatly at the edge of its container</text>
						<p id="summary" width={360}>A paragraph with <strong>styled inline text</strong> stays within two lines. The final line ends with an ellipsis, while the remaining content stays available when its clamp is removed.</p>
						<div width={360} height={100}>
							<div class="absolute z-20 bg-primary rounded-lg p-4" width={238} height={72}><text class="text-white font-semibold">z-index: 20</text></div>
							<div class="absolute z-10 bg-surface-elevated border border-border rounded-lg p-4 flex-col items-end" left={100} top={28} width={238} height={72}><text>z-index: 10</text></div>
						</div>
					</card-content>
				</card>
			</div>
			<card width={832}>
				<card-header><card-title>Visual order, stable identity</card-title><card-description>CSS order moves items. Document order and keyboard focus stay A → B → C.</card-description></card-header>
				<card-content class="flex-row gap-3">
					<div order={order} animateLayout={true} class="bg-primary/10 rounded-lg p-3 flex-row items-center gap-3" width={236}><badge>A</badge><text>Reactive order: {order}</text></div>
					<div animateLayout={true} class="bg-surface-elevated rounded-lg p-3 flex-row items-center gap-3" width={236}><badge appearance={Outline}>B</badge><text>Default order: 0</text></div>
					<div animateLayout={true} class="bg-surface-elevated rounded-lg p-3 flex-row items-center gap-3" width={236}><badge appearance={Outline}>C</badge><text>Default order: 0</text></div>
				</card-content>
			</card>
		</div>, {fps: 60, frames: 48, minFrames: 20, before: (frame, tree, root) -> {
			if (frame == 1) {
				var node = Css.query(tree, root.node.id, "#scroll")[0];
				Scroll.at(node).scrollTo(0, 110);
				order.set(-1);
			}
		}, clear: ThemeState.get().color(Background).rgb()});
	}
}
