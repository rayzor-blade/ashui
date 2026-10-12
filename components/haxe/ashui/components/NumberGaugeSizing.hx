package ashui.components;

import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.Node;
import ashui.layout.Prop;

/** Intrinsic range sizing from formatted bounds, without owning CSS properties (095fab4). **/
@:noCompletion class NumberGaugeSizing {
	static final byIdentity = new haxe.ds.ObjectMap<Identity, NumberGaugeSizing>();
	static var hooked = false;
	static final pending = new haxe.ds.ObjectMap<ashui.layout.LayoutTree, Array<NumberGaugeSizing>>();
	final root:Node;
	final text:Node;
	final rootIdentity:Identity;
	final textIdentity:Identity;
	final samples:Array<{bytes:hl.Bytes, capacity:Int}>;
	final out:hl.Bytes;
	final info = new hl.Bytes(16);
	var minimum = 0.0;
	var space = 0.0;
	var font:Null<String> = null;
	var width:Single = 0;
	var queued = false;

	public function new(root:Node, text:Node, candidates:Array<String>) {
		this.root = root;
		this.text = text;
		rootIdentity = Identity.of(root.tree, root.id);
		textIdentity = Identity.of(text.tree, text.id);
		samples = [for (candidate in candidates) {bytes: ashui.core.Utf8.encode(candidate), capacity: candidate.length + 2}];
		var capacity = 2;
		for (sample in samples) capacity = Std.int(Math.max(capacity, sample.capacity));
		out = new hl.Bytes(capacity * 12);
		byIdentity.set(rootIdentity, this);
		byIdentity.set(textIdentity, this);
		ashui.reactive.Owner.onCleanup(() -> {
			byIdentity.remove(rootIdentity);
			byIdentity.remove(textIdentity);
			var list = pending.get(root.tree);
			if (list != null) {
				list.remove(this);
				if (list.length == 0) pending.remove(root.tree);
			}
		});
		if (!hooked) {
			hooked = true;
			Css.restyled.push(identity -> {
				var sizing = byIdentity.get(identity);
				if (sizing != null) {
					if (identity == sizing.textIdentity) sizing.invalidate();
					else { sizing.invalidate(); sizing.restore(); }
				}
			});
			ashui.layout.LayoutTree.layoutHooks.push(tree -> {
				var list = pending.get(tree);
				if (list == null) return false;
				pending.remove(tree);
				var changed = false;
				for (sizing in list) {
					sizing.queued = false;
					if (sizing.measure()) changed = true;
				}
				return changed;
			});
		}
		restore();
		invalidate();
	}

	function invalidate():Void {
		var base = Css.resolve(rootIdentity, "var(--ui-number-gauge-min-width, var(--ui-number-gauge-base-width, 114px))");
		var inset = Css.resolve(rootIdentity, "var(--ui-number-gauge-value-space, 48px)");
		var next = Css.fontSize(textIdentity) + "|" + Css.resolved(textIdentity, "font-family")
			+ "|" + Css.resolved(textIdentity, "font-weight") + "|" + Css.resolved(textIdentity, "font-style")
			+ "|" + Css.resolved(textIdentity, "letter-spacing") + "|" + base + "|" + inset;
		if (next != font) {
			font = next;
			minimum = length(base);
			space = length(inset);
			if (!queued) {
				queued = true;
				var list = pending.get(root.tree);
				if (list == null) pending.set(root.tree, list = []);
				list.push(this);
			}
		}
	}

	function measure():Bool {
		// Font writes are queued during CSS restyling. Measure after they reach
		// native code, once per changed font, and request only the needed layout pass.
		var advance = 0.0;
		for (sample in samples) {
			var count = ashui.core.externs.TextNative.blinc_text_carets(root.tree.ptr, text.id, sample.bytes, 0, 0,
				out, sample.capacity, info);
			if (count > 0 && count <= sample.capacity) advance = Math.max(advance, out.getF32((count - 1) * 12 + 4));
		}
		var previous = width;
		// Fractional glyph advances stay intact until the final outer size.
		width = Math.max(minimum, Math.ceil(advance + space));
		return restore() && width != previous;
	}

	function restore():Bool {
		// A developer's max-width (including none) or HXX property still wins.
		if (Css.computed(rootIdentity, "max-width") == null)
			return @:privateAccess root.style(Prop.MaxWidth, width);
		return false;
	}

	function length(value:String):Float {
		return Math.max(0, ashui.css.CssValue.resolve(ashui.css.CssValue.length(value), {
			percentOf: 0, fontSize: Css.fontSize(rootIdentity), rootFontSize: Css.rootFontSize,
			viewportWidth: Css.viewportWidth, viewportHeight: Css.viewportHeight
		}));
	}
}
