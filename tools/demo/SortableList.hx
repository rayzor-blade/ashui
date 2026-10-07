import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Library;
import ashui.animation.AnimatedValue;
import ashui.animation.AnimationScheduler;
import ashui.animation.SpringConfig;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.input.Events.KeyEvent;
import ashui.input.Events.PointerEvent;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.state.Machine;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Ref;
#if ashui_window
import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
#else
import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
#end

private typedef SortableItem = {
	id:String,
	title:String,
	detail:String,
	row:Ref<Div>
}

private enum SortableState {
	Idle;
	Dragging(item:SortableItem);
	Settling(item:SortableItem, cancelled:Bool);
	Fading(item:SortableItem, cancelled:Bool);
}

private enum SortableEvent {
	Grab(item:SortableItem);
	Drop;
	Cancel;
	Fade;
	Settled;
	Reset;
	Interrupt;
}

/**
	A sortable list built with direct HXX, existing Buttons, Badges and layout motion.
	The For keeps the same items and nodes as their order changes; animateLayout
	eases the rows into their new slots. A separate HXX preview follows the
	pointer while dragging, so it doesn't lag behind those transitions.
	A framework FSM owns dragging, the spring return, and the final crossfade.

	    tools/demo/run.sh SortableList.hx
	    tools/snapshot/run.sh tools/demo/SortableList.hx

	Drag a handle, or focus it and use Up/Down, Home/End. Escape cancels a drag.
	The offscreen run exercises dragging, cancellation, keyboard sorting and reset.
**/
class SortableList {
	public static inline var WIDTH = 720;
	public static inline var HEIGHT = 800;
	static inline var ROW_HEIGHT = 72;
	static inline var ROW_GAP = 10;
	static inline var STRIDE = ROW_HEIGHT + ROW_GAP;
	static var styled = false;

	public static function page():Element {
		if (!styled) {
			Library.use();
			Css.add(CompiledCss.file("SortableList.css"));
			styled = true;
		}
		var original:Array<SortableItem> = [
			{id: "tokens", title: "Design tokens", detail: "Colors, type and spacing"},
			{id: "keyboard", title: "Keyboard navigation", detail: "Focus and accessible controls"},
			{id: "calendar", title: "Calendar pickers", detail: "Month and year selection"},
			{id: "glass", title: "Liquid glass", detail: "Tint, refraction and aberration"},
			{id: "motion", title: "Motion snapshots", detail: "Capture and review transitions"},
			{id: "notes", title: "Release notes", detail: "Document the latest changes"}
		].map(item -> {id: item.id, title: item.title, detail: item.detail, row: new Ref<Div>()});
		var items = Signal.make(original.copy());
		var phase = new Machine<SortableState, SortableEvent>(Idle, (state, event) -> switch [state, event] {
			case [_, Grab(item)]: Dragging(item);
			case [Dragging(item), Drop]: Settling(item, false);
			case [Dragging(item), Cancel]: Settling(item, true);
			case [Settling(item, cancelled), Fade]: Fading(item, cancelled);
			case [Fading(_, _), Settled]: Idle;
			case [_, Reset] | [_, Interrupt]: Idle;
			case _: null;
		});
		var dragged = Computed.make(() -> switch phase.state.get() {
			case Idle: (null : Null<SortableItem>);
			case Dragging(item) | Settling(item, _) | Fading(item, _): item;
		});
		var dragTop = Signal.make(0.0);
		var previewOpacity = Computed.make(() -> phase.state.get().match(Fading(_, _)) ? 0.0 : 1.0);
		var message = Signal.make("Your order is saved for this session.");
		var list = new Ref<Div>();
		var saved:Array<SortableItem> = [];
		var hook:Null<LayoutTree->Void> = null;
		var release:Null<AnimatedValue> = null;

		function unhook() {
			if (hook != null) Pointer.hooks.remove(hook);
			hook = null;
		}
		function stopRelease() {
			if (release != null) release.setImmediate(dragTop.get());
			release = null;
		}
		phase.onExit(Dragging(null), _ -> unhook());
		phase.onEnter(Idle, _ -> stopRelease());
		phase.onEnter(Dragging(null), _ -> stopRelease());
		phase.onEnter(Settling(null, false), state -> switch state {
			case Settling(item, cancelled):
				if (cancelled) items.set(saved.copy());
				message.set(cancelled ? "Drag cancelled. Previous order restored." : '${item.title} is now item ${items.get().indexOf(item) + 1}.');
				var spring = new AnimatedValue(AnimationScheduler.main, dragTop.get(), SpringConfig.gentle());
				release = spring;
				spring.setTarget(items.get().indexOf(item) * STRIDE);
				AnimationScheduler.main.addTicker(_ -> {
					if (release != spring) return false;
					dragTop.set(spring.get());
					return true;
				});
			case _:
		});
		// State timers are cancelled by the FSM on a new grab, keyboard move
		// or reset. No delayed callback can hide a subsequent drag's preview.
		phase.after(Settling(null, false), 0.6, Fade);
		phase.after(Fading(null, false), 0.2, Settled);
		function move(item:SortableItem, target:Int) {
			var next = items.get().copy();
			target = Std.int(Math.max(0, Math.min(next.length - 1, target)));
			if (next.indexOf(item) == target) return;
			next.remove(item);
			next.insert(target, item);
			items.set(next);
			message.set('${item.title} is now item ${target + 1}.');
		}
		function begin(item:SortableItem, e:PointerEvent) {
			if (e.button != Left) return;
			phase.send(Interrupt);
			var box = list.get();
			var tree = box.tree;
			var bounds = tree.getBounds(box.node);
			var row = tree.getBounds(item.row.get().node);
			var grab = e.y - row.y;
			// Hit coordinates include layout motion: grabbing a row before its
			// previous move finishes starts the preview where it is drawn.
			for (hit in tree.hitTest(e.x, e.y)) if (hit.id == item.row.get().node.id) grab = hit.y;
			saved = items.get().copy();
			dragTop.set(e.y - grab - bounds.y);
			phase.send(Grab(item));
			message.set('Moving ${item.title}. Escape cancels.');
			hook = t -> {
				if (t != tree) return;
				var at = Pointer.at(tree);
				if (!at.pressed) {
					phase.send(Drop);
					return;
				}
				// Use settled slots, not the animated rows, to avoid oscillating
				// between two indices while the neighbours are still moving.
				var top = Math.max(0, Math.min((items.get().length - 1) * STRIDE, at.y - bounds.y - grab));
				dragTop.set(top);
				move(item, Math.round(top / STRIDE));
			};
			Pointer.hooks.push(hook);
			e.preventDefault();
			e.stopPropagation();
		}
		function sortKey(item:SortableItem, e:KeyEvent) {
			if (phase.state.get().match(Dragging(_))) return;
			var at = items.get().indexOf(item);
			var target = switch e.key {
				case Named(ArrowUp): at - 1;
				case Named(ArrowDown): at + 1;
				case Named(Home): 0;
				case Named(End): items.get().length - 1;
				case _: return;
			};
			phase.send(Interrupt);
			move(item, target);
			e.preventDefault();
			e.stopPropagation();
		}
		Owner.onCleanup(() -> {
			unhook();
			stopRelease();
		});

		return <div class="sl-page" width={WIDTH} height={HEIGHT}
			onKeyDown={e -> if (e.key.match(Named(Escape)) && phase.state.get().match(Dragging(_))) { phase.send(Cancel); e.preventDefault(); }}>
			<div class="flex flex-row items-center justify-between gap-4">
				<div class="flex flex-col gap-2">
					<text class="sl-eyebrow">INTERACTIONS</text>
					<text class="text-3xl font-semibold">Sortable list</text>
					<text class="text-sm text-text-secondary">A little motion to keep everything in place.</text>
				</div>
				<button id="sl-reset" variant={Outline} size={Sm} type="button" onClick={_ -> {
					phase.send(Reset);
					items.set(original.copy());
					message.set("Original order restored.");
				}}>Reset order</button>
			</div>
			<div class="flex flex-row items-center justify-between">
				<text class="text-sm font-semibold">Up next</text>
				<badge variant={Secondary}>6 items</badge>
			</div>
			<div ref={list} id="sl-list" class="sl-list relative" height={original.length * STRIDE - ROW_GAP}>
				<for {item in items}>
					<div ref={item.row} id={"sl-row-" + item.id} class="sl-row transition-opacity duration-200 ease-in-out" height={ROW_HEIGHT} animateLayout={true}
						opacity={dragged.get() == item && previewOpacity.get() > 0 ? 0.25 : 1.0}>
						<button id={"sl-handle-" + item.id} variant={Ghost} size={Icon} type="button" class="sl-handle"
							onPointerDown={e -> begin(item, e)} onKeyDown={e -> sortKey(item, e)}>
							<svg width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
								<path d="M9 5h.01M9 12h.01M9 19h.01M15 5h.01M15 12h.01M15 19h.01" />
							</svg>
						</button>
						<text class="sl-rank">${StringTools.lpad(Std.string(items.get().indexOf(item) + 1), "0", 2)}</text>
						<div class="flex flex-col gap-1 flex-1">
							<text class="text-sm font-semibold">${item.title}</text>
							<text class="sl-detail">${item.detail}</text>
						</div>
						<svg class="sl-arrow" width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
							<path d="M7 17 17 7M7 7h10v10" />
						</svg>
					</div>
				</for>
				<for {preview in (dragged.get() == null ? [] : [dragged.get()])}>
					<div id="sl-preview" class="sl-row sl-preview absolute transition-opacity duration-200 ease-in-out"
						left={0} top={dragTop} widthPercent={1} height={ROW_HEIGHT} opacity={previewOpacity}>
						<div class="sl-grip">
							<svg width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
								<path d="M9 5h.01M9 12h.01M9 19h.01M15 5h.01M15 12h.01M15 19h.01" />
							</svg>
						</div>
						<text class="sl-rank">${StringTools.lpad(Std.string(items.get().indexOf(preview) + 1), "0", 2)}</text>
						<div class="flex flex-col gap-1 flex-1">
							<text class="text-sm font-semibold">${preview.title}</text>
							<text class="sl-detail">${preview.detail}</text>
						</div>
						<badge variant={Primary}>${phase.state.get().match(Dragging(_)) ? "Moving" : "Settling"}</badge>
					</div>
				</for>
			</div>
			<div class="sl-footer flex flex-col gap-2">
				<text class="text-sm">${message.get()}</text>
				<text class="sl-detail">Drag a handle · Up / Down to move · Home / End · Escape to cancel</text>
			</div>
		</div>;
	}

	static function main() {
		#if ashui_window
		WindowedApp.run(new WindowConfig().title("Sortable list").size(WIDTH, HEIGHT).resizable(false).theme(DefaultTheme.bundle()), page);
		#else
		ThemeState.init(DefaultTheme.bundle(), Light);
		Snapshot.scene("sortable-list", WIDTH, HEIGHT, page);
		SortableListMotion.run();
		#end
	}

}
