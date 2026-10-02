import ashui.core.render.Snapshot;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Shadow;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/** A card with a shadow, a gradient header and a row of chips. **/
class Demo {
	static function main() {
		Snapshot.scene("demo", 320, 200, () -> {
			var card:Div = hxx('
				<Div width={280} height={160} margin={20} padding={12} gap={10} flexDirection={Column}
					cornerRadius={CornerRadius.all(14)} bg={Brush.solid(0xffffff)}
					borderColor={new Color(0xd0d7de)} borderWidth={1}>
					<Div height={48} flexShrink={0} cornerRadius={CornerRadius.all(8)}
						bg={Brush.linearGradient(0, 0, 256, 0, 0x6366f1, 1, 0xec4899, 1)} />
					<Div flexDirection={Row} gap={8}>
						<Div width={60} height={24} cornerRadius={CornerRadius.all(12)} bg={Brush.solid(0xdbeafe)} />
						<Div width={44} height={24} cornerRadius={CornerRadius.all(12)} bg={Brush.solid(0xdcfce7)} />
						<Div width={72} height={24} cornerRadius={CornerRadius.all(12)} bg={Brush.solid(0xfef3c7)} />
					</Div>
				</Div>
			');
			card.node.set(ashui.layout.Prop.Shadow, new Shadow(0, 8, 16, 0x0f172a, 0.25));
			var page:Div = new Div({width: 320, height: 200, bg: Brush.solid(0xf1f5f9)}, [card]);
			page;
		}, 0xf1f5f9);
	}
}
