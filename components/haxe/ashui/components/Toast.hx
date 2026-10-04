package ashui.components;

import ashui.components.Button;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.For;
import ashui.ui.Text;

enum abstract ToastVariant(String) to String {
	var Default = "default";
	var Success = "success";
	var Warning = "warning";
	var Destructive = "destructive";
}

typedef ToastOptions = {
	title:String,
	?description:String,
	?variant:ToastVariant,
	/** Seconds it shows for, while the pointer is not on it; 5 by default, 0 until it is dismissed. **/
	?duration:Float,
	/** A button on it: its label, and what it does before the toast goes. **/
	?action:{label:String, run:Void->Void},
	/** Whether it has a close button; true by default. **/
	?closable:Bool
}

/** A shown toast, to take it away before its time. **/
class ToastHandle {
	final entry:ToastEntry;

	@:allow(ashui.components)
	function new(entry:ToastEntry)
		this.entry = entry;

	public function dismiss():Void
		entry.machine.send(Dismiss);
}

/** Where a toast is: shown, held while the pointer is on it, leaving, gone. **/
private enum ToastState {
	Shown;
	Held;
	Leaving;
	Gone;
}

private enum ToastEvent {
	Rest;
	Leave;
	Timeout;
	Dismiss;
	Done;
}

/**
	The toasts: placed once, at the end of the app's root, it stacks every
	toast `Toaster.show` makes in a corner, the newest nearest the edge.
	Each toast stays its `duration`, longer while the pointer is on it, then
	slides away; the rest close the gap by layout animation. Its life is a
	`Machine`: `data-state` on the toast is shown, held or leaving.

	```haxe
	<div ...>{app}<toaster /></div>
	Toaster.show({title: "Saved", description: "Your changes are saved.", variant: Success});
	```

	CSS: `.ui-toaster` (`[data-position]`), `.ui-toast` (`[data-variant]`,
	`[data-state]`), `.ui-toast-icon`, `.ui-toast-body`, `.ui-toast-title`,
	`.ui-toast-description`, `.ui-toast-close`; `--ui-toast-bg`,
	`-border`, `-radius`, `-width`, `-shadow`.
**/
class Toaster extends Component<{?position:String, ?id:String}> {
	/** The toaster `show` puts toasts in: the last one made. **/
	public static var current(default, null):Null<Toaster> = null;

	@:allow(ashui.components)
	final toasts = Signal.make(([] : Array<ToastEntry>));

	function render():Element {
		var list = toasts;
		var root = Library.part("ui-toaster", null, ["position" => (props.position == null ? "bottom-right" : props.position)], [
			new For(() -> list.get(), entry -> entry.build())
		], props.id);
		current = this;
		ashui.reactive.Owner.onCleanup(() -> if (current == this) current = null);
		return root;
	}

	/** Shows a toast in the current toaster; its handle dismisses it early. Without a toaster, nothing is shown. **/
	public static function show(options:ToastOptions):Null<ToastHandle> {
		var toaster = current;
		if (toaster == null)
			return null;
		var entry = new ToastEntry(toaster, options);
		toaster.toasts.set(toaster.toasts.get().concat([entry]));
		return new ToastHandle(entry);
	}
}

@:allow(ashui.components)
private class ToastEntry {
	static final ICONS = [
		"success" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>',
		"warning" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>',
		"destructive" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>'
	];
	static final CLOSE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>';
	static final parsed = new Map<String, ashui.svg.SvgDocument>();

	final toaster:Toaster;
	final options:ToastOptions;
	final machine:Machine<ToastState, ToastEvent>;

	function new(toaster:Toaster, options:ToastOptions) {
		this.toaster = toaster;
		this.options = options;
		machine = new Machine<ToastState, ToastEvent>(Shown, (s, e) -> switch [s, e] {
			case [Shown, Rest]: Held;
			case [Held, Leave]: Shown;
			case [Shown, Timeout] | [Shown, Dismiss] | [Held, Dismiss]: Leaving;
			case [Leaving, Done]: Gone;
			case _: null;
		});
		var duration = options.duration == null ? 5.0 : options.duration;
		if (duration > 0)
			machine.after(Shown, duration, Timeout);
		var theme = ashui.theme.ThemeState.tryGet();
		// Gone once its exit animation has played.
		machine.after(Leaving, theme == null ? 0 : theme.animations().durationFast / 1000, Done);
		machine.onEnter(Gone, _ -> toaster.toasts.set(toaster.toasts.get().filter(t -> t != this)));
		// It starts shown: its timer starts now, as if it had just entered.
		machine.start();
	}

	static function icon(svg:String, size:Float, cls:String):ashui.ui.Svg {
		var doc = parsed.get(svg);
		if (doc == null)
			parsed.set(svg, doc = ashui.svg.SvgDocument.parse(svg));
		var i = new ashui.ui.Svg(doc, {width: size, height: size});
		ashui.css.Identity.of(i.tree, i.node.id).setClasses([cls]);
		return i;
	}

	function build():Element {
		var variant:String = options.variant == null ? Default : options.variant;
		var parts:Array<Element> = [];
		var glyph = ICONS.get(variant);
		if (glyph != null)
			parts.push(icon(glyph, 20, "ui-toast-icon"));
		var body:Array<Element> = [Library.part("ui-toast-title", null, null, [new Text(options.title)])];
		if (options.description != null)
			body.push(Library.part("ui-toast-description", null, null, [new Text(options.description)]));
		for (b in body)
			ashui.text.InlineFlow.attach(cast b);
		parts.push(Library.part("ui-toast-body", null, null, body));
		var m = machine;
		if (options.action != null) {
			var a = options.action;
			parts.push(new Button({variant: Outline, size: Sm, type: "button", onClick: _ -> {
				a.run();
				m.send(Dismiss);
			}}, [new Text(a.label)]));
		}
		if (options.closable != false) {
			var close = Library.part("ui-toast-close", "button", null, [icon(CLOSE, 16, "ui-toast-close-icon")]);
			Interaction.of(close.node).setFocusable(true).onClick(_ -> m.send(Dismiss));
			parts.push(close);
		}
		var box = Library.part("ui-toast", null, ["variant" => variant, "state" => machine.name()], parts);
		var i = Interaction.of(box.node);
		i.onPointerEnter(_ -> m.send(Rest));
		i.onPointerLeave(_ -> m.send(Leave));
		// The others close the gap it leaves, and move up as one arrives.
		ashui.animation.LayoutAnimation.attach(box.node);
		ashui.reactive.Owner.onCleanup(() -> m.dispose());
		return box;
	}
}
