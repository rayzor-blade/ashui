import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.Themed;
import ashui.theme.themes.DefaultTheme;
import ashui.types.CornerRadius;
import ashui.types.CornerShape;
import ashui.types.Style;
import ashui.ui.Div;

/** Each corner shape on the same 24px radius: theme squircle, round, squircle, bevel, scoop, notch, square. **/
class Shapes {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		Snapshot.scene("shapes", 560, 120, () -> {
			var shapes:Array<Null<CornerShape>> = [
				null,
				CornerShape.round().lock(),
				CornerShape.squircle(),
				CornerShape.bevel(),
				CornerShape.scoop(),
				CornerShape.notch(),
				CornerShape.square()
			];
			new Div({width: 560, height: 120, padding: 16, gap: 16, flexDirection: FlexDirection.Row}, [
				for (shape in shapes)
					new Div({
						width: 64, height: 88, flexShrink: 0, cornerRadius: CornerRadius.all(24), cornerShape: shape,
						bg: Themed.brush(Primary), borderColor: Themed.color(TextPrimary), borderWidth: 3
					})
			]);
		}, page.rgb(), page.a);
	}
}
