import ashui.app.WindowedApp;
import ashui.input.Events;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;
import ashui.ui.TextField;

/**
	A live window of what ashui's input does so far:

	- buttons with hover:, active: and focus-visible: classes and colour
	  transitions, one counting its clicks;
	- a button disabled and enabled by another, with a disabled: class;
	- Tab and Shift+Tab moving focus, Enter, or Space on release, clicking;
	- a text field: typing, selection with Shift, the mouse or Command+A,
	  word and line moves with Alt and Command, Enter submitting;
	- a turned card whose button is hit where it is drawn, clipped to the card;
	- a box that adds up wheel and trackpad scrolling;
	- icons in currentColor, which follow their button's text colour;
	- a theme switch, and a line logging the latest event.
**/
class Interactions {
	static final clicks = Signal.make(0);
	static final locked = Signal.make(false);
	static final typed = Signal.make("");
	static final scrolled = Signal.make(0.0);
	static final latest = Signal.make("Events show here.");

	static function main() {
		WindowedApp.run({title: "ashui interactions", width: 760, height: 540}, page);
	}

	static function log(text:String):Void
		latest.set(text);

	static function count(e:PointerEvent):Void {
		clicks.set(clicks.get() + 1);
		log('click on the counter at ${Math.round(e.localX)}, ${Math.round(e.localY)} in it');
	}

	static function toggleLock(_:PointerEvent):Void {
		locked.set(!locked.get());
		log(locked.get() ? "the target button is disabled" : "the target button is enabled");
	}

	static function scroll(e:PointerEvent):Void {
		scrolled.set(scrolled.get() + e.deltaY);
		log('wheel ${Math.round(e.deltaX)}, ${Math.round(e.deltaY)}');
	}

	static function page():Div {
		return hxx('
			<div class="flex flex-col p-6 gap-5 bg-background" width={760} height={540}>
				<div class="flex flex-row items-center justify-between">
					<text class="text-2xl font-bold">Interactions</text>
					<div class="flex flex-row items-center gap-2 px-3 py-2 rounded-lg bg-surface border-2 border-border hover:bg-surface-elevated focus-visible:border-border-focus transition-colors"
						focusable={true} onClick={() -> { ThemeState.get().toggleScheme(); log("theme switched"); }}>
						<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
						</svg>
						<text class="text-sm">Theme</text>
					</div>
				</div>
				<text class="text-sm text-text-secondary">Hover and press the buttons. Tab and Shift+Tab move focus; Enter, or Space, clicks. Click the field and type. Scroll over the wheel box.</text>

				<div class="flex flex-row items-center gap-3">
					<div class="flex flex-row items-center gap-2 px-4 py-2 rounded-lg bg-primary hover:bg-primary-hover active:bg-primary-active text-text-inverse border-2 border-primary focus-visible:border-border-focus transition-colors"
						focusable={true} onClick={count}
						onPointerEnter={_ -> log("pointer entered the counter")} onPointerLeave={_ -> log("pointer left the counter")}>
						<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
							<line x1="12" y1="5" x2="12" y2="19" />
							<line x1="5" y1="12" x2="19" y2="12" />
						</svg>
						<text class="text-sm font-semibold">Clicked ${clicks.get()} times</text>
					</div>
					<div class="px-4 py-2 rounded-lg bg-surface hover:bg-surface-elevated active:bg-border border-2 border-border focus-visible:border-border-focus transition-colors"
						focusable={true} onClick={toggleLock}>
						<text class="text-sm">${locked.get() ? "Enable the target" : "Disable the target"}</text>
					</div>
					<div class="px-4 py-2 rounded-lg bg-success hover:bg-primary active:bg-primary-active disabled:bg-input-bg-disabled text-text-inverse border-2 border-success focus-visible:border-border-focus disabled:border-border transition-colors"
						focusable={true} disabled={locked.get()} onClick={() -> log("the target was clicked")}>
						<text class="text-sm font-semibold">Target</text>
					</div>
				</div>

				<div class="flex flex-row items-start gap-6">
					<div class="flex flex-col gap-2">
						<text class="text-xs text-text-tertiary">Text field: click it, or Tab to it; Enter submits</text>
						<text-field value={typed} placeholder="Type here" width={280}
							onInput={v -> log("input: " + v.length + " characters")} onSubmit={v -> log("submitted: " + v)} />
					</div>
					<div class="flex flex-col gap-2">
						<text class="text-xs text-text-tertiary">Turned card, hit where drawn</text>
						<div class="flex flex-col items-start rotate-6 rounded-xl overflow-hidden bg-surface border border-border" width={180} height={96}>
							<div class="w-full shrink-0 bg-linear-to-r from-primary to-warning" height={28} />
							<div class="m-3 px-3 py-1 rounded-md bg-accent-subtle hover:bg-accent active:bg-primary transition-colors"
								onClick={e -> log("turned button clicked at " + Math.round(e.localX) + ", " + Math.round(e.localY) + " in its own coordinates")}>
								<text class="text-sm">Click me</text>
							</div>
						</div>
					</div>
					<div class="flex flex-col gap-2">
						<text class="text-xs text-text-tertiary">Wheel box</text>
						<div class="flex items-center justify-center rounded-xl bg-surface border-2 border-border hover:border-border-hover transition-colors"
							width={160} height={96} onWheel={scroll}>
							<text class="text-sm">Scrolled ${Math.round(scrolled.get())}</text>
						</div>
					</div>
				</div>

				<div class="flex flex-row items-center gap-2 px-4 py-3 rounded-lg bg-surface border border-border">
					<text class="text-xs text-text-tertiary">Latest event</text>
					<text class="text-sm">${latest.get()}</text>
				</div>
			</div>
		');
	}
}
