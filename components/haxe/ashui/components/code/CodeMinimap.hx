package ashui.components.code;

import ashui.animation.AnimationScheduler;
import ashui.components.Library;
import ashui.components.code.CodeDocument;
import ashui.components.code.CodeHighlighter.CodeToken;
import ashui.components.code.CodeHighlighter.CodeTokenKind;
import ashui.css.Css;
import ashui.css.CssValue;
import ashui.css.Identity;
import ashui.draw.DrawContext;
import ashui.input.Interaction;
import ashui.input.Scroll;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.types.Brush;
import ashui.ui.Canvas;
import ashui.ui.Div;

/** What a minimap reads of the editor it sits beside, and writes back to through `scroll`. **/
typedef MinimapHost = {
	final document:CodeDocument;
	final metrics:CodeMetrics;
	final scroll:Scroll;
	/** The editor's height and width on screen, and a count that moves when what it shows is made again. **/
	final viewHeight:Signal<Float>;
	final viewWidth:Signal<Float>;
	/** The editor's whole width, the strip's included, which the strip's own width does not move. **/
	final boxWidth:Signal<Float>;
	final revision:Signal<Int>;
	final tabSize:Int;
	/** The space above the first line, in the editor's layout units. **/
	final pad:Float;
	/** The widest the strip gets. **/
	final maxWidth:Float;
	/** What the app marks, for the marks of decorations and markers that ask to be in the strip. **/
	final annotations:CodeAnnotations;
	/** The zones between the editor's rows and a read of them that moves when they do, so the slider keeps to the rows on screen. **/
	final zones:CodeZones;
	final zoneStamp:Void->Int;
}

/**
	A strip down an editor's right edge that draws the whole document scaled
	down, a line to a row and each token a run of its syntax colour, with a
	slider over the part on screen. Pressing the strip scrolls the editor to
	that line, dragging the slider scrolls as it moves, and the wheel over the
	strip scrolls the editor.

	The rows are drawn once per revision, a moment after the last change, in
	one canvas; scrolling moves only the slider. A document of more lines
	than the strip has rows is drawn smaller to fit it and shows every
	few lines, so the strip is always the whole document and never scrolls.
	Colours are read from the editor's own token styles, so a theme changes
	them; the strip, its slider and its border are styled by
	`--ui-code-minimap-bg`, `--ui-code-minimap-slider`,
	`--ui-code-minimap-slider-hover`, `--ui-code-minimap-slider-active` and
	`--ui-code-minimap-border`.
**/
class CodeMinimap {
	/** Token kinds the stylesheet colours; any other is drawn as plain. **/
	static final KINDS = ["plain", "markup-text", "tag", "attribute", "keyword", "string", "comment", "number", "type", "function", "operator"];

	/** A line's row, and the thickness of what is drawn in it, in layout units. **/
	static inline var ROW = 2.0;

	static inline var THICK = 1.5;

	/** A slider is never thinner than this, so it can be taken hold of. **/
	static inline var SLIDER_MIN = 12.0;

	/** The most marks drawn over the rows. **/
	static inline var MARKS = 600;

	/** The wait after a change before the rows are drawn again, in seconds. **/
	static inline var SETTLE = 0.12;

	public static function make(host:MinimapHost):Div {
		// What the rows are drawn from changes in `stamp`, a moment after the last revision; `inks` when a token style is restyled.
		var stamp = Signal.make(0);
		var inks = Signal.make(0);
		var pending:Null<ashui.animation.AnimationScheduler.Timer> = null;
		new Watch(() -> host.revision.get(), _ -> {
			if (pending != null)
				pending.cancel();
			pending = AnimationScheduler.main.after(SETTLE, () -> {
				pending = null;
				stamp.set(stamp.get() + 1);
			});
		});
		Owner.onCleanup(() -> if (pending != null) pending.cancel());

		// A quarter of the text's width is a fifth of the whole, which is measured with the strip in it and so is not changed by it:
		// a width taken from the text's width, which the strip takes from, can settle on two sizes and swap them each frame.
		var width = Computed.make(() -> (Math.min(host.maxWidth, Math.max(24, Math.round(host.boxWidth.get() * .2))) : Single));
		var height = Computed.make(() -> (host.viewHeight.get() : Single));

		// One probe a kind, styled as a token is, to read its colour from.
		var probes:Array<Identity> = [];
		var colours = new Map<String, {rgb:Int, alpha:Float}>();
		var probeBoxes = [for (kind in KINDS) {
			var box = Library.part("ui-code-minimap-probe", null, ["token" => kind], null, null, ["ui-code-token"]);
			probes.push(Identity.of(box.tree, box.node.id));
			(box : Element);
		}];
		function read():Void {
			for (i in 0...KINDS.length) {
				var text = Css.resolved(probes[i], "color");
				colours.set(KINDS[i], switch (try CssValue.color(text) catch (_:Dynamic) CurrentColor) {
					case Rgba(rgb, a): {rgb: rgb, alpha: a};
					case CurrentColor: {rgb: 0x888888, alpha: 1.0};
				});
			}
		}
		var restyled:Identity->Void = identity -> if (probes.indexOf(identity) >= 0) {
			read();
			inks.set(inks.get() + 1);
		};
		Css.restyled.push(restyled);
		Owner.onCleanup(() -> Css.restyled.remove(restyled));

		/** Layout units a line takes in the strip: a line's row, or less when the document has more lines than the strip has rows. **/
		function pitch():Float
			return Math.min(ROW, host.viewHeight.get() / Math.max(1, host.document.visible.length));

		function column(text:String, index:Int, tabs:Bool):Int {
			if (!tabs)
				return index;
			var at = 0;
			for (i in 0...index)
				at += text.charCodeAt(i) == "\t".code ? host.tabSize - at % host.tabSize : 1;
			return at;
		}

		function draw(ctx:DrawContext):Void {
			stamp.get();
			inks.get();
			var lines = host.document.visible, count = lines.length, h = host.viewHeight.get();
			if (count == 0 || h <= 0)
				return;
			var rowPitch = pitch(), step = rowPitch < .5 ? Math.ceil(.5 / rowPitch) : 1;
			var thick = Math.max(.5, Math.min(THICK, rowPitch * step * .75)), limit = ctx.width;
			var plain = colours.get("plain");
			var row = 0;
			while (row < count) {
				var line = host.document.lines[lines[row]], text = line.text, y = row * rowPitch;
				var tabs = text.indexOf("\t") >= 0, from = 0, to = 0, rgb = 0, alpha = 1.0, open = false;
				function flush() {
					if (open)
						ctx.fillRect(from, y, Math.min(to, limit) - from, thick, Brush.solid(rgb, alpha * .85));
					open = false;
				}
				// A line with no tokens is one plain run.
				var count = line.tokenCount == 0 ? 1 : line.tokenCount;
				for (t in 0...count) {
					var a = line.tokenCount == 0 ? 0 : line.tokenFrom(t), b = line.tokenCount == 0 ? text.length : line.tokenTo(t);
					var kind:CodeTokenKind = line.tokenCount == 0 ? CodeTokenKind.Plain : line.tokenKind(t);
					while (a < b && text.charCodeAt(a) <= " ".code)
						a++;
					while (b > a && text.charCodeAt(b - 1) <= " ".code)
						b--;
					if (a >= b)
						continue;
					var x0 = column(text, a, tabs), x1 = column(text, b, tabs);
					if (x0 >= limit)
						break;
					var ink = colours.get(kind);
					if (ink == null)
						ink = plain;
					var red = ink == null ? 0x888888 : ink.rgb, opacity = ink == null ? 1.0 : ink.alpha;
					if (open && red == rgb && opacity == alpha && x0 - to <= 1)
						to = x1;
					else {
						flush();
						from = x0;
						to = x1;
						rgb = red;
						alpha = opacity;
						open = true;
					}
				}
				flush();
				row += step;
			}
		}

		// Not retained: once drawn, the strip is shown from the GPU, and the triangles of a long file would stay in the editor's memory.
		var canvas:Canvas = <canvas widthPercent={1} heightPercent={1} draw={draw} />;
		var dragging = Signal.make(false);

		// A height in the editor as a place among its rows, and back: the rows are one height, but zones between them are not.
		function rowOf(y:Float):Float {
			host.zoneStamp();
			return host.zones.fraction(y - host.pad, host.metrics.lineHeight, host.document.visible.length);
		}
		function yOf(row:Float):Float {
			host.zoneStamp();
			var whole = Std.int(Math.floor(row));
			return host.pad + host.zones.yOf(whole, host.metrics.lineHeight) + (row - whole) * host.metrics.lineHeight;
		}
		function span():Float {
			var h = host.viewHeight.get(), y = host.scroll.y.get();
			return Math.min(h, Math.max(SLIDER_MIN, (rowOf(y + h) - rowOf(y)) * pitch()));
		}
		var sliderTop = Computed.make(() -> {
			host.revision.get();
			var top = rowOf(host.scroll.y.get()) * pitch();
			(Math.max(0, Math.min(top, host.viewHeight.get() - span())) : Single);
		});
		var sliderHeight = Computed.make(() -> { host.revision.get(); (span() : Single); });
		var slider = new Div({classes: ["ui-code-minimap-slider"], top: sliderTop, height: sliderHeight});

		// Marks the app asked for, over the rows: a bar at the edge for a marker, the width of the row for a decoration. They are elements,
		// not part of the canvas, so a change of marks never draws the rows again; a few hundred at most, one a line and class.
		var marks = Computed.make(() -> {
			host.revision.get();
			host.annotations.revision.get();
			host.annotations.minimapMarks(MARKS);
		});
		function markView(m:CodeAnnotations.MinimapMark):Element {
			var top = Computed.make(() -> {
				host.revision.get();
				var d = host.document, line = Std.int(Math.min(m.line, d.lines.length - 1)), at = d.rows[line];
				(at < 0 ? 0 : at * pitch() : Single);
			});
			var thick = Computed.make(() -> (Math.max(2, pitch() * 1.2) : Single));
			var hidden = Computed.make(() -> {
				host.revision.get();
				var d = host.document, line = Std.int(Math.min(m.line, d.lines.length - 1));
				(d.visible[d.rows[line]] == line ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility);
			});
			return new Div({classes: ["ui-code-minimap-mark", m.className].concat(m.bar ? ["ui-code-minimap-bar"] : []), top: top, height: thick, visibility: hidden});
		}
		var layer = new Div({classes: ["ui-code-minimap-marks"]}, [<for {m in marks}>{markView(m)}</for>]);
		var strip = new Div({classes: ["ui-code-minimap"], width: width, height: height}, [(canvas : Element), (layer : Element), slider].concat(probeBoxes));
		Identity.of(strip.tree, strip.node.id).bindAttribute("data-dragging", Computed.make(() -> (dragging.get() ? "true" : null : Null<String>)));

		/** Scrolls the editor so the slider's top is at `top` in the strip. **/
		function scrollTo(top:Float):Void {
			host.scroll.scrollTo(host.scroll.x.get(), yOf(top / pitch()));
		}
		// Where on the slider it was taken hold of, so it moves with the pointer instead of jumping to it; off it, its middle.
		var grab = 0.0;
		var i = Interaction.of(strip.node);
		i.onPointerDown(p -> {
			if (p.button != Left)
				return;
			dragging.set(true);
			var top = sliderTop.get(), size = span();
			grab = p.localY >= top && p.localY <= top + size ? p.localY - top : size / 2;
			scrollTo(p.localY - grab);
		});
		i.onPointerMove(p -> if (dragging.get()) scrollTo(p.localY - grab));
		i.onPointerUp(_ -> dragging.set(false));
		i.onWheel(p -> if (host.scroll.scrollTo(host.scroll.x.get() - p.deltaX, host.scroll.y.get() - p.deltaY)) p.stopPropagation());
		return strip;
	}
}
