import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.canvaskit.Background2D;
import ashui.canvaskit.CanvasKit;
import ashui.canvaskit.Selection2D;
import ashui.canvaskit.Viewport2D;
import ashui.components.Button;
import ashui.components.Select;
import ashui.components.ToggleSwitch;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;

/** A card on the board: where it is, its size, title and colour. **/
typedef Card = {id:String, x:Float, y:Float, w:Float, h:Float, title:String, color:Int};

/**
	A board of cards in a `<canvas-kit>` filling the window. Drag the empty
	board to pan (or with the Select tool, to draw a selection box), the
	wheel to zoom about the pointer, Shift-wheel or a trackpad to pan.
	Click a card to select it, Shift- or Cmd-click to add, drag the
	selection to move it, snapped to the grid when snapping is on. Curves
	join cards that follow each other. A floating toolbar sets the tool,
	the background and snapping, and fits the board in view.

		tools/demo/run.sh Canvas2D.hx
**/
class Canvas2D {
	static function main() {
		var colors = [0x3b82f6, 0x10b981, 0xf59e0b, 0xef4444, 0x8b5cf6, 0x06b6d4];
		var titles = ["Ideas", "Research", "Design", "Build", "Test", "Ship", "Feedback", "Metrics", "Roadmap", "Notes", "Risks", "Launch"];
		var cards:Array<Card> = [
			for (i in 0...titles.length)
				{id: 'c$i', x: (i % 4) * 220.0 + (i % 2) * 30, y: Std.int(i / 4) * 160.0 + (i % 3) * 20, w: 170.0, h: 100.0, title: titles[i], color: colors[i % colors.length]}
		];
		var viewport = new Viewport2D();
		var selection = new Selection2D();
		// Bumped as cards move, so the board draws them where they are now.
		var moved = Signal.make(0);
		var tool = Signal.make("pan");
		var pattern = Signal.make("dots");
		var snapping = Signal.make(true);
		var kit:Null<CanvasKit> = null;

		// Brushes are made once: each is a native value, and the board draws every frame it moves.
		var shadow = Brush.solid(0x000000, 0.18);
		var face = Brush.solid(0x1e293b);
		var titleInk = Brush.solid(0xf1f5f9);
		var noteInk = Brush.solid(0x94a3b8);
		var wire = Brush.solid(0x94a3b8, 0.6);
		var chosenEdge = Brush.solid(0x60a5fa);
		var bands = [for (c in colors) c => Brush.solid(c)];
		var titleStyle:ashui.draw.GlyphOutlines.TextStyle = {size: 16, weight: 600};
		var noteStyle:ashui.draw.GlyphOutlines.TextStyle = {size: 12};

		function draw(ctx:ashui.draw.DrawContext, k:CanvasKit) {
			kit = k;
			moved.get();
			var z = viewport.zoom.get();
			// The connections first, under the cards: each card's right side to the next one's left, as a curve.
			var line = new Stroke(2 / z);
			for (i in 0...cards.length - 1) {
				var a = cards[i], b = cards[i + 1];
				var x0 = a.x + a.w, y0 = a.y + a.h / 2, x1 = b.x, y1 = b.y + b.h / 2;
				var reach = Math.max(40, Math.abs(x1 - x0) / 2);
				ctx.strokePath(new Path().moveTo(x0, y0).cubicTo(x0 + reach, y0, x1 - reach, y1, x1, y1), line, wire);
			}
			for (c in cards) {
				if (!k.visible(c.x - 10, c.y - 10, c.w + 20, c.h + 20))
					continue;
				ctx.fillRect(c.x + 2 / z, c.y + 4 / z, c.w, c.h, shadow, 12);
				ctx.fillRect(c.x, c.y, c.w, c.h, face, 12);
				ctx.fillRect(c.x, c.y, c.w, 8, bands.get(c.color), 4);
				ctx.text(c.title, c.x + 14, c.y + 40, titleInk, titleStyle);
				ctx.text('${Math.round(c.x)}, ${Math.round(c.y)}', c.x + 14, c.y + 70, noteInk, noteStyle);
				if (selection.has(c.id))
					ctx.strokeRect(c.x - 3 / z, c.y - 3 / z, c.w + 6 / z, c.h + 6 / z, new Stroke(2 / z), chosenEdge, 14);
				k.region(c.id, c.x, c.y, c.w, c.h);
			}
		}

		// Made once, so changing the background does not make a new native brush each time.
		var backgrounds = [
			"dots" => Background2D.dots(0x64748b, 20),
			"grid" => Background2D.grid(0x64748b, 20),
			"crosshatch" => Background2D.crosshatch(0x64748b, 20),
			"none" => new Background2D(None)
		];

		function page():Element {
			var choices:Array<Element> = [
				<select-item value="dots">Dots</select-item>,
				<select-item value="grid">Grid</select-item>,
				<select-item value="crosshatch">Crosshatch</select-item>,
				<select-item value="none">None</select-item>
			];
			var tools:Array<Element> = [<select-item value="pan">Pan tool</select-item>, <select-item value="select">Select tool</select-item>];
			return <div class="w-full h-full">
				<canvas-kit widthPercent={1} heightPercent={1} viewport={viewport} selection={selection}
					tool={Computed.make(() -> tool.get() == "select" ? Select : Pan)}
					snap={Computed.make(() -> snapping.get() ? 20.0 : 0.0)}
					background={Computed.make(() -> backgrounds.get(pattern.get()))}
					draw={draw}
					onDrag={(ids, dx, dy) -> {
						for (c in cards)
							if (ids.indexOf(c.id) >= 0) {
								c.x += dx;
								c.y += dy;
							}
						moved.set(moved.get() + 1);
					}} />
				<div class="flex flex-row items-center gap-3 px-3 py-2 rounded-xl border border-white/10 bg-surface/70 backdrop-blur-md" position={Absolute} top={16} left={16}>
					<select value={tool} width={130}>{tools}</select>
					<select value={pattern} width={130}>{choices}</select>
					<div flexDirection={Row} gap={8} alignItems={Center}><toggle-switch checked={snapping} /><text>Snap</text></div>
					<button variant={Outline} onClick={_ -> if (kit != null) kit.fitContent()}>Fit</button>
				</div>
				<div class="px-3 py-1.5 rounded-lg border border-white/10 bg-surface/70 backdrop-blur-md" position={Absolute} left={16} bottom={16}>
					<text class="text-xs font-medium">${Math.round(viewport.zoom.get() * 100) + "%  ·  " + selection.ids.get().length + " selected"}</text>
				</div>
			</div>;
		}
		WindowedApp.run(new WindowConfig().title("Canvas kit").size(1100, 720).theme(DefaultTheme.bundle()), page);
	}
}
