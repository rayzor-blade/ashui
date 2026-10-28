package ashui.components;

import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.Prop;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef ResizableProps = {
	/** Panel layout: `horizontal` (default) for a row, or `vertical` for a column. **/
	?direction:String,
	/** Shows a grip on each resize handle. **/
	?grip:Bool,
	?id:String
}

/**
	Resizable panels arranged in a row or column.

	Drag a handle, or use its arrow keys while focused, to resize the adjacent
	panels within their `minSize` and `maxSize` bounds. Double-click resets
	both panels to their initial sizes. The resize cursor remains active
	throughout a drag, even outside the handle.

	CSS: `.ui-resizable[data-direction]`, `.ui-resizable-panel`,
	`.ui-resizable-handle` with `[data-dragging]`, `:hover`, and `:focus-visible`,
	plus `.ui-resizable-line` and `.ui-resizable-grip`.
**/
class Resizable extends Component<ResizableProps> {
	/** Distance moved by each arrow-key step, in layout units. **/
	public static inline var STEP = 10.0;

	function render():Element {
		Library.use();
		var vertical = props.direction == "vertical";
		var panels:Array<ResizablePanel> = [for (c in children) if (Std.isOfType(c, ResizablePanel)) cast c];
		for (p in panels) {
			var size = p.size;
			var grow:Float = p.props.grow == null ? 1.0 : p.props.grow;
			// A panel with a size keeps it; one without shares what is left by `grow`.
			p.node.set(Prop.FlexBasis, Computed.make(() -> (Math.isNaN(size.get()) ? 0.0 : size.get() : Single)));
			p.node.set(Prop.FlexGrow, Computed.make(() -> (Math.isNaN(size.get()) ? grow : 0.0 : Single)));
			if (p.props.minSize != null)
				p.node.set(vertical ? Prop.MinHeight : Prop.MinWidth, ((p.props.minSize : Float) : Single));
			if (p.props.maxSize != null)
				p.node.set(vertical ? Prop.MaxHeight : Prop.MaxWidth, ((p.props.maxSize : Float) : Single));
		}
		var parts:Array<Element> = [];
		for (c in children) {
			parts.push(c);
			var at = panels.indexOf(cast c);
			if (at >= 0 && at < panels.length - 1)
				parts.push(handle(panels, at, vertical));
		}
		return Library.part("ui-resizable", null, ["direction" => (vertical ? "vertical" : "horizontal")], parts, props.id);
	}

	function handle(panels:Array<ResizablePanel>, at:Int, vertical:Bool):Element {
		var a = panels[at], b = panels[at + 1];
		var dragging = Signal.make(false);
		var line:Array<Element> = [];
		if (props.grip == true)
			line.push(Library.part("ui-resizable-grip", null, null, []));
		var box = Library.part("ui-resizable-handle", null, ["dragging" => Computed.make(() -> (dragging.get() ? "" : null : Null<String>))],
			[Library.part("ui-resizable-line", null, null, line)]);
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		identity.setAttribute("role", "separator");
		identity.setAttribute("aria-orientation", vertical ? "horizontal" : "vertical");
		var tree = box.tree;
		inline function along(x:Float, y:Float)
			return vertical ? y : x;
		// A sized panel's size is its own; one sharing the space is as laid out.
		function current(p:ResizablePanel):Float {
			if (!Math.isNaN(p.size.get()))
				return p.size.get();
			var r = tree.getBounds(p.node);
			return r == null ? 0.0 : vertical ? r.height : r.width;
		}
		inline function or(v:Null<Float>, fallback:Float)
			return v == null ? fallback : v;
		var initial = [a.size.get(), b.size.get()];
		// The first panel as it was when the move began, the two together, and how far the move may take the first.
		var startA = 0.0, total = 0.0, lo = 0.0, hi = 0.0;
		function begin() {
			startA = current(a);
			total = startA + current(b);
			// Either that shares the space takes its size for the move, while another still shares it, so the two always sum to `total`.
			var sharing = Lambda.count(panels, p -> Math.isNaN(p.size.get()));
			for (p in [a, b])
				if (Math.isNaN(p.size.get()) && sharing > 1) {
					p.size.set(p == a ? startA : total - startA);
					sharing--;
				}
			lo = Math.max(or(a.props.minSize, 0), total - or(b.props.maxSize, Math.POSITIVE_INFINITY));
			hi = Math.min(or(a.props.maxSize, Math.POSITIVE_INFINITY), total - or(b.props.minSize, 0));
		}
		function moveTo(next:Float) {
			var na = Math.max(lo, Math.min(hi, next));
			if (!Math.isNaN(a.size.get()))
				a.size.set(na);
			if (!Math.isNaN(b.size.get()))
				b.size.set(total - na);
		}
		var interaction = Interaction.of(box.node).setFocusable(true);
		// A drag follows the pointer until the button comes up, wherever the pointer goes.
		var drag:Null<ashui.layout.LayoutTree->Void> = null;
		function stopDrag() {
			if (drag != null)
				Pointer.hooks.remove(drag);
			drag = null;
			dragging.set(false);
		}
		interaction.onPointerDown(e -> {
			stopDrag();
			if (e.clickCount == 2) {
				a.size.set(initial[0]);
				b.size.set(initial[1]);
				return;
			}
			begin();
			var from = along(e.x, e.y);
			dragging.set(true);
			drag = t -> if (t == tree) {
				var at = Pointer.at(tree);
				if (at.pressed) moveTo(startA + along(at.x, at.y) - from) else stopDrag();
			}
			Pointer.hooks.push(drag);
		});
		Owner.onCleanup(stopDrag);
		interaction.onKeyDown(e -> {
			var step = switch e.key {
				case Named(ArrowRight) if (!vertical): STEP;
				case Named(ArrowDown) if (vertical): STEP;
				case Named(ArrowLeft) if (!vertical): -STEP;
				case Named(ArrowUp) if (vertical): -STEP;
				case Named(Home): Math.NEGATIVE_INFINITY;
				case Named(End): Math.POSITIVE_INFINITY;
				case _: return;
			}
			begin();
			moveTo(startA + step);
			e.preventDefault();
		});
		return box;
	}
}

typedef ResizablePanelProps = {
	/**
		Panel width in a row, or height in a column, in layout units. Dragging
		updates a supplied signal. Unsized panels share remaining space by
		`grow` until resized while another panel still shares that space.
	**/
	?size:IntoReactive<Float>,
	?minSize:Float,
	?maxSize:Float,
	/** Share of remaining space relative to other unsized panels. Defaults to 1. **/
	?grow:Float,
	?id:String
}

/** One panel inside a `Resizable` group. **/
class ResizablePanel extends Component<ResizablePanelProps> {
	/** Current panel size. NaN means the panel shares remaining space. **/
	public var size(default, null):Signal<Float>;

	function render():Element {
		size = switch props.size {
			case null: Signal.make(Math.NaN);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		return Library.part("ui-resizable-panel", null, null, children, props.id);
	}
}
