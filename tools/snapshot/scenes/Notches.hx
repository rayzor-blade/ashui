import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Notches: a menu-bar dropdown whose concave top corners meet the bar
	(its body is inset by their radius, so it is pulled up by as much), a
	tooltip with a peak, a scoop carved in like the Dynamic Island, a
	bulge, and a V cut, each with a fill, and the dropdown with a border
	and a shadow.
**/
class Notches {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var dropdown:Notch = Notch.concaveTop(20, 16);
		var tooltip:Notch = {topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10, top: Peak(24, 10)};
		var island:Notch = {topLeft: 18, topRight: 18, bottomRight: 18, bottomLeft: 18, top: Scoop(90, 22, 8)};
		var bulge:Notch = {topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12, bottom: Bulge(80, 16, 6)};
		var cut:Notch = {topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4, bottom: Cut(40, 16)};
		var build = () -> hxx('
			<div flexDirection={Column} padding={24} gap={24} width={520} height={420}>
				<div flexDirection={Column} alignItems={Center}>
					<div width={360} height={24} bg={Brush.solid(0x111827)} />
					<div notch={dropdown} width={360} height={130} bg={Brush.solid(0x111827)} padding={28} marginTop={-20}
						class="shadow-lg border-2 border-primary">
						<text class="text-white">Battery: 87%</text>
					</div>
				</div>
				<div flexDirection={Row} gap={20} alignItems={Start}>
					<div notch={tooltip} width={120} height={70} bg={Brush.solid(0x2563eb)} padding={16} paddingTop={20}>
						<text class="text-white text-sm">A tooltip</text>
					</div>
					<div notch={island} width={150} height={90} bg={Brush.solid(0x0f172a)} />
					<div notch={bulge} width={120} height={90} bg={Brush.solid(0x16a34a)} />
					<div notch={cut} width={80} height={90} bg={Brush.solid(0xdb2777)} />
				</div>
			</div>
		');
		Snapshot.scene("notches@2x", 520, 420, build, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
