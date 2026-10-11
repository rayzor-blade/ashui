import ashui.components.Badge;
import ashui.components.Card;
import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Grid alignment, percentage spacing and inline defaults, before and after hidden changes. **/
class CssBindings {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var hidden = Signal.make(false);
		Css.load('
			#tiles { display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: 76px 76px; place-items: center; padding: 5%; gap: 12px; background: var(--surface-elevated); border-radius: var(--radius-lg); }
			#tiles > :last-child { justify-self: end; }
			#copy { margin: 0; font-size: 16px; line-height: 1.6; }
		');
		Snapshot.sequence("css-bindings", 820, 444, () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={444}>
			<text class="text-2xl font-semibold">Native layout, familiar CSS</text>
			<text class="text-text-secondary">Percentage spacing, grid alignment and reactive element defaults.</text>
			<div class="flex-row gap-5">
				<card width={376}>
					<card-header><card-title>Grid alignment</card-title><card-description>place-items: center · padding: 5%</card-description></card-header>
					<card-content>
						<div id="tiles" width={328}>
							<badge>Design</badge><badge variant={Success}>Ready</badge>
							<badge appearance={Outline}>Review</badge><badge variant={Warning}>End aligned</badge>
						</div>
					</card-content>
				</card>
				<card width={376}>
					<card-header><card-title>Inline defaults</card-title><card-description>Underline · strike · dotted abbreviation</card-description></card-header>
					<card-content class="flex-col gap-4">
						<p id="copy" width={328}>Read the <a href="https://example.com">release notes</a>: <del hidden={hidden}>old behavior</del> <ins>new behavior</ins>. The <abbr title="Application Programming Interface">API</abbr> follows familiar element defaults.</p>
						<div hidden={hidden} class="bg-surface-elevated rounded-lg p-3 flex-col gap-2" width={328}>
							<badge variant={Success}>Visible</badge><text class="text-text-secondary">This panel leaves no space when hidden.</text>
						</div>
						<text class="text-text-tertiary">The next frame hides the old text and panel.</text>
					</card-content>
				</card>
			</div>
		</div>, 30, 2, (frame, _, _) -> if (frame == 1) hidden.set(true), ThemeState.get().color(Background).rgb());
	}
}
