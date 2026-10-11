import ashui.components.Badge;
import ashui.components.Card;
import ashui.core.render.Snapshot;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Native CSS visibility and overlay scrollbar changes, using the existing components. **/
class CssInteraction {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		Css.add(CompiledCss.file("CssInteraction.css"));
		Snapshot.sequence("css-interaction", 760, 400, () -> <div width={760} height={400} class="bg-background p-6 flex-col gap-4">
			<text class="text-2xl font-semibold">CSS controls paint and input</text>
			<text class="text-text-secondary">Layout stays steady as visibility and scrollbar styles change.</text>
			<div class="gap-4">
				<card width={348}>
					<card-header><card-title>Activity</card-title><card-description>A thin scrollbar over the existing scroll container</card-description></card-header>
					<card-content>
						<div id="activity" class="css-scroll flex-col gap-2" width={300} height={164}>
							<for {label in ["Review layout changes", "Inspect pointer targets", "Capture theme snapshots", "Check compact layouts", "Verify keyboard focus", "Publish the milestone"]}>
								<div class="bg-surface-elevated rounded-md p-3" width={290} flexShrink={0}><text class="text-sm">{label}</text></div>
							</for>
						</div>
					</card-content>
				</card>
				<card width={348}>
					<card-header><card-title>Reserved space</card-title><card-description>Hidden paint keeps its place in the layout</card-description></card-header>
					<card-content class="flex-col gap-3">
						<badge appearance={Outline}>Visible</badge>
						<div id="reserved" class="css-reserved bg-primary/15 rounded-md p-3" width={300} height={48}><text>Space stays reserved</text></div>
						<badge variant={Success}>This stays in place</badge>
						<div class="css-overlay"><text class="text-sm text-text-tertiary">Painted overlays can pass pointer hits through.</text></div>
					</card-content>
				</card>
			</div>
		</div>, 30, 2, (frame, tree, root) -> {
			if (frame == 1) {
				for (id in Css.query(tree, root.node.id, "#reserved")) Identity.of(tree, id).setInline("visibility", "visible");
				for (id in Css.query(tree, root.node.id, "#activity")) Identity.of(tree, id).setInline("scrollbar-width", "none");
			}
		}, ThemeState.get().color(Background).rgb());
	}
}
