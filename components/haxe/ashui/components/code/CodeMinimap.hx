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
	final revision:Signal<Int>;
	final tabSize:Int;
	/** The space above the first line, in the editor's layout units. **/
	final pad:Float;
	/** The widest the strip gets. **/
	final maxWidth:Float;
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

		var width = Computed.make(() -> (Math.min(host.maxWidth, Math.max(24, host.viewWidth.get() * .25)) : Single));
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
				var tokens:Array<CodeToken> = line.tokens.length == 0 ? [{from: 0, to: text.length, kind: CodeTokenKind.Plain}] : line.tokens;
				for (token in tokens) {
					var a = token.from, b = token.to;
					while (a < b && text.charCodeAt(a) <= " ".code)
						a++;
					while (b > a && text.charCodeAt(b - 1) <= " ".code)
						b--;
					if (a >= b)
						continue;
					var x0 = column(text, a, tabs), x1 = column(text, b, tabs);
					if (x0 >= limit)
						break;
					var ink = colours.get(token.kind);
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

		var canvas:Canvas = <canvas widthPercent={1} heightPercent={1} draw={draw} retain={true} />;
		var dragging = Signal.make(false);

		function span():Float {
			var h = host.viewHeight.get();
			return Math.min(h, Math.max(SLIDER_MIN, h / host.metrics.lineHeight * pitch()));
		}
		var sliderTop = Computed.make(() -> {
			host.revision.get();
			var top = (host.scroll.y.get() - host.pad) / host.metrics.lineHeight * pitch();
			(Math.max(0, Math.min(top, host.viewHeight.get() - span())) : Single);
		});
		var sliderHeight = Computed.make(() -> { host.revision.get(); (span() : Single); });
		var slider = new Div({classes: ["ui-code-minimap-slider"], top: sliderTop, height: sliderHeight});

		var strip = new Div({classes: ["ui-code-minimap"], width: width, height: height}, [(canvas : Element), slider].concat(probeBoxes));
		Identity.of(strip.tree, strip.node.id).bindAttribute("data-dragging", Computed.make(() -> (dragging.get() ? "true" : null : Null<String>)));

		/** Scrolls the editor so the slider's top is at `top` in the strip. **/
		function scrollTo(top:Float):Void {
			var line = top / pitch();
			host.scroll.scrollTo(host.scroll.x.get(), host.pad + line * host.metrics.lineHeight);
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
