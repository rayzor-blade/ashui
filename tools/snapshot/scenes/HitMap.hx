import ashui.components.Button;
import ashui.core.render.Snapshot;
import ashui.input.Pointer;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;

/** Native hit regions of ordinary elements, overlapping boxes and clipped content. */
class HitMap {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		Snapshot.scene("hit-map", 900, 500, () -> {
			var plain:Div = null;
			var page = <div id="page" class="flex flex-col p-6 gap-6 bg-background" width={900} height={500}>
				<text class="text-2xl font-bold">Native hit map</text>
				<text class="text-sm text-text-secondary">Plain containers and text are hit targets too. Hover to inspect the exact path.</text>
				<div id="cards" class="flex flex-row gap-6">
					${plain = <div id="plain-card" class="flex flex-col p-5 gap-4 rounded-xl bg-surface border border-border" width={230} height={170}>
						<text class="text-lg font-semibold">A plain container</text>
						<text class="text-sm text-text-secondary">No event handlers.</text>
						<text class="text-sm text-text-secondary">Its padding still receives hits.</text>
					</div>}
					<div id="action-card" class="flex flex-col p-5 gap-4 rounded-xl bg-surface border border-border" width={230} height={170}>
						<text class="text-lg font-semibold">Framework button</text>
						<button id="save" onClick={_ -> Sys.println("Save clicked in the hit-map demo")}>Save changes</button>
					</div>
				</div>
				<div id="overlap" class="relative" width={490} height={130}>
					<div id="behind" class="absolute rounded-lg bg-accent-subtle" left={0} top={0} width={230} height={110}>
						<text class="p-4 text-sm">Behind the clipped shape</text>
					</div>
					<div id="circle" class="absolute bg-primary [clip-path:circle()]" left={160} top={0} width={110} height={110} />
					<div id="plain-outline" class="absolute rounded-lg border-2 border-warning" left={320} top={0} width={160} height={110}>
						<text class="p-4 text-sm">Another plain container</text>
					</div>
				</div>
			</div>;
			// The offscreen capture inspects padding; the window takes real input.
			if (!ashui.debug.SceneWindow.wanted()) {
				page.tree.flush();
				page.tree.computeLayout(page.node, 900, 500);
				var b = page.tree.getBounds(plain.node);
				Pointer.move(page.tree, b.x + 8, b.y + b.height / 2);
			}
			return page;
		}, ThemeState.get().color(Background).rgb(), 1);
	}
}
