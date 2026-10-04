package ashui.draw;

/** How text is set: its face, size and weight, and how it stands at the point it is drawn at. **/
typedef TextStyle = {
	/** In layout units; 14 by default. **/
	?size:Float,
	/** A family by name; the system's interface face when unset. **/
	?family:String,
	/** 0 the system's, 1 monospace, 2 serif, 3 sans-serif: the face when `family` is unset or missing. **/
	?generic:Int,
	/** 100 to 900; 400 by default. **/
	?weight:Int,
	?italic:Bool,
	/** Added after each character, in layout units. **/
	?letterSpacing:Float,
	/** Between lines, a multiple of the face's own line; 1 by default. **/
	?lineHeight:Float,
	/** Which of its ends or its middle the point is; its start by default. **/
	?align:TextAlignment,
	/** Which of its lines the point is on: the baseline by default. **/
	?baseline:TextBaseline
}

enum abstract TextAlignment(Int) {
	var Start;
	var Middle;
	var End;
}

enum abstract TextBaseline(Int) {
	/** The baseline its letters stand on. **/
	var Alphabetic;

	/** The top of its tallest letters. **/
	var Top;

	/** Halfway between its top and its bottom. **/
	var Middle;

	/** The bottom of its deepest descenders. **/
	var Bottom;
}

/** Text as paths: its glyphs' outlines, and the measure of the run. **/
typedef TextOutline = {commands:Array<Float>, width:Float, ascent:Float, descent:Float, lineHeight:Float};

/**
	The outlines of text's glyphs, laid out and shaped by the text engine,
	so a canvas fills text as it fills any shape: at any scale and turned.
	Kept by text and style, as a canvas draws the same labels again. Only
	where the engine is, HashLink and Ash; elsewhere there are none.
**/
class GlyphOutlines {
	/** How many outlines are kept; a new one past this forgets the oldest. **/
	static inline var KEPT = 512;

	static final kept = new Map<String, TextOutline>();
	static final order:Array<String> = [];

	/** `text`'s outline set as `style` says, or null where there is no text engine or no face. **/
	public static function of(text:String, style:TextStyle):Null<TextOutline> {
		var size:Float = style.size != null ? style.size : 14.0;
		var key = '${style.family}|${style.generic}|${style.weight}|${style.italic}|$size|${style.letterSpacing}|${style.lineHeight}|$text';
		var known = kept.get(key);
		if (known != null)
			return known;
		#if hl
		var info = new hl.Bytes(16);
		var font = style.family == null ? null : ashui.core.Utf8.encode(style.family);
		var bytes = ashui.core.Utf8.encode(text);
		var weight:Int = style.weight != null ? style.weight : 400, italic = style.italic == true, generic:Int = style.generic != null ? style.generic : 0;
		var spacing:Float = style.letterSpacing != null ? style.letterSpacing : 0.0, leading:Float = style.lineHeight != null ? style.lineHeight : 1.0;
		var capacity = 4096;
		var out = new hl.Bytes(capacity * 4);
		var set = new hl.Bytes(24);
		for (i => v in [generic * 1.0, weight * 1.0, italic ? 1.0 : 0.0, size, spacing, leading])
			set.setF32(i * 4, v);
		var n = ashui.core.externs.TextNative.blinc_text_outline(bytes, font, set, out, capacity, info);
		if (n > capacity) {
			capacity = n;
			out = new hl.Bytes(capacity * 4);
			n = ashui.core.externs.TextNative.blinc_text_outline(bytes, font, set, out, capacity, info);
		}
		if (n <= 0 && text.length > 0)
			return null;
		var outline:TextOutline = {
			commands: [for (i in 0...n) out.getF32(i * 4)],
			width: info.getF32(0),
			ascent: info.getF32(4),
			descent: info.getF32(8),
			lineHeight: info.getF32(12)
		};
		kept.set(key, outline);
		order.push(key);
		if (order.length > KEPT)
			kept.remove(order.shift());
		return outline;
		#else
		return null;
		#end
	}

	/** `outline` as a path, its point moved to `(x, y)`. **/
	public static function path(outline:TextOutline, x:Float, y:Float):Path {
		var p = new Path();
		var c = outline.commands, i = 0;
		while (i < c.length) {
			switch Std.int(c[i]) {
				case 0:
					p.moveTo(x + c[i + 1], y + c[i + 2]);
					i += 3;
				case 1:
					p.lineTo(x + c[i + 1], y + c[i + 2]);
					i += 3;
				case 2:
					p.quadTo(x + c[i + 1], y + c[i + 2], x + c[i + 3], y + c[i + 4]);
					i += 5;
				case 3:
					p.cubicTo(x + c[i + 1], y + c[i + 2], x + c[i + 3], y + c[i + 4], x + c[i + 5], y + c[i + 6]);
					i += 7;
				case _:
					p.close();
					i += 1;
			}
		}
		return p;
	}
}
