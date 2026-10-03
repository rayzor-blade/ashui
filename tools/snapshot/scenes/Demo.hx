import ashui.core.render.Snapshot;
import ashui.layout.Prop;
import ashui.theme.ColorScheme;
import ashui.theme.Themed;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/**
	A card in the default theme, light and dark: surface, border and shadow
	from the theme's tokens, corners on its radius ladder, so the larger
	ones take the theme's squircle and the pills stay round.
**/
class Demo {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var theme = ThemeState.get();
		for (scheme in [ColorScheme.Light, ColorScheme.Dark]) {
			theme.setScheme(scheme);
			var page = theme.color(Background);
			Snapshot.scene(scheme == Light ? "demo-light" : "demo-dark", 320, 200, card, page.rgb(), page.a);
		}
	}

	static function card():Div {
		var theme = ThemeState.get();
		var primary = theme.color(Primary).rgb();
		var accent = theme.color(Accent).rgb();
		var chips = [Themed.brush(AccentSubtle), Themed.brush(SuccessBg), Themed.brush(WarningBg)];
		var card:Div = hxx('
			<div width={280} height={160} margin={20} padding={16} gap={12} flexDirection={Column}
				cornerRadius={Themed.radius(Xl)} bg={Themed.brush(Surface)}
				borderColor={Themed.color(Border)} borderWidth={1}>
				<div height={56} flexShrink={0} cornerRadius={Themed.radius(Lg)}
					bg={Brush.linearGradient(0, 0, 248, 0, primary, 1, accent, 0.6)} />
				<div flexDirection={Row} gap={8}>
					<div width={64} height={24} cornerRadius={Themed.radius(Full)} bg={chips[0]} />
					<div width={48} height={24} cornerRadius={Themed.radius(Full)} bg={chips[1]} />
					<div width={72} height={24} cornerRadius={Themed.radius(Full)} bg={chips[2]} />
				</div>
			</div>
		');
		card.node.set(Prop.Shadow, Themed.shadow(Lg));
		return new Div({width: 320, height: 200}, [card]);
	}
}
