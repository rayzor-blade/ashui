package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.For;

typedef PaginationProps = {
	/** The page shown, from 1. A signal is read and written; a constant sets it once. **/
	?page:IntoReactive<Int>,
	total:Int,
	/** Pages shown each side of the current one before an ellipsis; 1 by default. **/
	?siblings:Int,
	/** Buttons to the first and last pages too. **/
	?edges:Bool,
	?size:Size,
	?onPageChange:Int->Void,
	?id:String
}

/**
	Pages to step through: previous and next, the first and last pages, the
	current one with its neighbours, ellipses for the rest; the buttons
	follow the page as it changes. CSS: `.ui-pagination` (`[data-size]`),
	`.ui-pagination-button` (`[data-state]` active, `:hover`, `:disabled`),
	`.ui-pagination-ellipsis`.
**/
class Pagination extends Component<PaginationProps> {
	public var page(default, null):Signal<Int>;

	static final ICONS = [
		"prev" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>',
		"next" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>',
		"first" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m11 17-5-5 5-5"/><path d="m18 17-5-5 5-5"/></svg>',
		"last" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 17 5-5-5-5"/><path d="m13 17 5-5-5-5"/></svg>'
	];
	static final parsed = new Map<String, ashui.svg.SvgDocument>();

	function render():Element {
		page = switch props.page {
			case null: Signal.make(1);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var p = page, total = props.total, siblings = props.siblings == null ? 1 : props.siblings;
		var go = (n:Int) -> {
			var to = Std.int(Math.max(1, Math.min(total, n)));
			if (to != p.get()) {
				p.set(to);
				if (props.onPageChange != null)
					props.onPageChange(to);
			}
		};
		// What shows, by key: the pages near the current one, the first and last, and an ellipsis where pages are left out.
		var keys = Computed.make(() -> {
			var at = p.get();
			var out = [];
			var from = Std.int(Math.max(1, at - siblings)), to = Std.int(Math.min(total, at + siblings));
			if (from > 1)
				out.push("p1");
			if (from > 2)
				out.push("gap-start");
			for (n in from...to + 1)
				out.push('p$n');
			if (to < total - 1)
				out.push("gap-end");
			if (to < total)
				out.push('p$total');
			out;
		});
		var parts:Array<Element> = [];
		if (props.edges == true)
			parts.push(step("first", () -> go(1), Computed.make(() -> p.get() <= 1)));
		parts.push(step("prev", () -> go(p.get() - 1), Computed.make(() -> p.get() <= 1)));
		parts.push(new For(() -> keys.get(), key -> {
			if (StringTools.startsWith(key, "gap"))
				return Library.part("ui-pagination-ellipsis", null, null, [new ashui.ui.Text("…")]);
			var n = Std.parseInt(key.substr(1));
			var b = Library.part("ui-pagination-button", "button", ["state" => Computed.make(() -> (p.get() == n ? "active" : null : Null<String>))],
				[new ashui.ui.Text(Std.string(n))]);
			Interaction.of(b.node).setFocusable(true).onClick(_ -> go(n));
			b;
		}));
		parts.push(step("next", () -> go(p.get() + 1), Computed.make(() -> p.get() >= total)));
		if (props.edges == true)
			parts.push(step("last", () -> go(total), Computed.make(() -> p.get() >= total)));
		return Library.part("ui-pagination", "nav", ["size" => (props.size == null ? Size.Md : props.size : String)], parts, props.id);
	}

	function step(kind:String, run:Void->Void, disabled:Computed<Bool>):Element {
		var doc = parsed.get(kind);
		if (doc == null)
			parsed.set(kind, doc = ashui.svg.SvgDocument.parse(ICONS.get(kind)));
		var icon = new ashui.ui.Svg(doc, {width: 16, height: 16});
		var b = Library.part("ui-pagination-button", "button", ["step" => kind], [icon]);
		var i = Interaction.of(b.node).setFocusable(true);
		i.setDisabled(disabled);
		i.onClick(_ -> run());
		return b;
	}
}
