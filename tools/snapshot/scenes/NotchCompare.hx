import ashui.core.render.Snapshot;
import ashui.layout.Prop;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.types.Shadow;
import ashui.types.Style;
import ashui.ui.Div;

/**
	Notched shapes with a drop shadow on each:
	a menu-bar dropdown, a bulge, a cut, a peak and a scoop, then the same
	with a border, which follows each outline alone.
**/
class NotchCompare {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var dark = 0x1f2937;
		function shape(notch:Notch, w:Float, h:Float, bordered:Bool):Div {
			var d = new Div({width: w, height: h, bg: Brush.solid(dark), notch: notch, flexShrink: 0});
			d.node.set(Prop.Shadow, new Shadow(0, 6, 8, 0x000000, 0.12));
			if (bordered) {
				d.node.set(Prop.BorderWidth, 2);
				d.node.set(Prop.BorderColor, new ashui.types.Color(0x3b82f6));
			}
			return d;
		}
		function row(bordered:Bool):Div {
			var r = 16.0;
			return new Div({flexDirection: Row, alignItems: Start, gap: 6, padding: 4}, [
				new Div({flexDirection: Column, alignItems: Center}, [
					new Div({width: 220, height: 30, bg: Brush.solid(dark)}),
					shape(Notch.concaveTop(32, 16), 220, 84, bordered)
				]),
				shape({topLeft: r, topRight: r, bottomRight: r, bottomLeft: r, top: Bulge(60, 14, 6)}, 160, 70, bordered),
				shape({topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12, top: Cut(40, 16)}, 120, 44, bordered),
				shape({topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12, top: Peak(50, 18)}, 130, 70, bordered),
				shape({topLeft: 24, topRight: 24, top: Scoop(80, 20, 8)}, 160, 70, bordered)
			]);
		}
		var build = () -> new Div({width: 900, height: 520, bg: Brush.solid(0xf3f4f6), flexDirection: Column, gap: 24, padding: 16}, [row(false), row(true)]);
		Snapshot.scene("notch-compare", 900, 520, build, 0xf3f4f6, 1.0);
	}
}
