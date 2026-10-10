import ashui.core.render.Snapshot;
import ashui.input.Pointer;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;

/** The element inspector over a padded, bordered card and a button: run with `ASHUI_INSPECT=1`; the capture hovers the button. */
class Inspector {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		Snapshot.scene("inspector", 720, 420, () -> {
			var save:Div = null;
			var page = <div id="page" class="flex flex-col p-6 gap-6 bg-background" width={720} height={420}>
				<text class="text-2xl font-bold">Inspector</text>
				<div id="card" class="flex flex-col p-5 gap-4 m-2 rounded-xl bg-surface border-2 border-border" width={300}>
					<text class="text-lg font-semibold">A card</text>
					<text class="text-sm text-text-secondary">Padding, border and margin are shaded around it.</text>
					${save = <div id="save" class="px-4 py-2 rounded-lg bg-primary text-text-inverse border border-primary" onClick={_ -> {}}>
						<text>Save changes</text>
					</div>}
				</div>
			</div>;
			if (!ashui.debug.SceneWindow.wanted()) {
				page.tree.flush();
				page.tree.computeLayout(page.node, 720, 420);
				var b = page.tree.getBounds(save.node);
				Pointer.move(page.tree, b.x + 4, b.y + 3);
			}
			return page;
		}, ThemeState.get().color(Background).rgb(), 1);
	}
}
