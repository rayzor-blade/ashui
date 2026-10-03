import ashui.animation.AnimationScheduler;
import ashui.app.WindowedApp;
import ashui.input.Pointer;
import ashui.input.Scroll;
import ashui.reactive.Signal;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;
import ashui.ui.TextField;

/**
	A scripted run for measuring frame pacing and CPU, with no one at the
	window: it steps through phases on its own timers, drives the pointer
	through ashui's input path, and quits at the end.

	- `idle`: nothing changes, so nothing should be drawn;
	- `animate`: a bar moves every tick, so a frame is drawn each time the
	  compositor takes one;
	- `caret`: a focused text field blinks its caret on timers;
	- `hover`: the pointer sweeps over buttons with hover transitions, a
	  move each tick;
	- `scroll`: a list scrolls smoothly back and forth;
	- `idle-after`: nothing again, to see the loop settle.

	Each phase start is printed as `phase <name> <epoch seconds> <ms since
	the window opened> active=<bool> visible=<bool>`, the second clock being
	`ASHUI_FRAME_LOG`'s, so an outside CPU sampler and the frame log can both
	be cut by phase. The caret blinks only while the window is active.
	`PACING_PHASE_SECONDS` sets each phase's length, 8 by default.
**/
class Pacing {
	static final offset = Signal.make(0.0);
	static var opened = -1.0;
	static var field:TextField;
	static var list:Div;
	static var buttons:Div;

	static function main() {
		var env = Sys.getEnv("PACING_PHASE_SECONDS");
		var seconds = env != null ? Std.parseFloat(env) : 8.0;
		WindowedApp.run({
			title: "ashui pacing",
			width: 640,
			height: 420,
			onFrame: (frame, at) -> if (opened < 0) {
				opened = haxe.Timer.stamp() - at;
				start(seconds);
			}
		}, page);
	}

	static function phase(name:String):Void {
		var state = ashui.input.WindowState;
		Sys.println('phase $name ${Sys.time()} ${Math.round((haxe.Timer.stamp() - opened) * 10000) / 10} active=${state.active.get()} visible=${state.visible.get()}');
	}

	static function start(seconds:Float):Void {
		var scheduler = AnimationScheduler.main;
		var tree = WindowedApp.current.tree;
		var steps:Array<{name:String, run:(Void->Bool)->Void}> = [
			{name: "idle", run: _ -> {}},
			{
				name: "animate",
				run: running -> scheduler.addTicker(dt -> {
					offset.set((offset.get() + dt * 200) % 400);
					running();
				})
			},
			{
				name: "caret",
				run: _ -> {
					// A window started in the background is never made active, and the caret only blinks in the active one.
					if (!ashui.input.WindowState.active.get()) {
						Sys.println("note: the window is not active; treating it as active for the caret phase");
						ashui.input.WindowState.active.set(true);
					}
					ashui.input.Focus.set(field.editing.interaction, false);
				}
			},
			{
				name: "hover",
				run: running -> {
					ashui.input.Focus.clear(tree);
					var b = tree.getBounds(buttons.node);
					var t = 0.0;
					scheduler.addTicker(dt -> {
						t += dt;
						// Across the row and back each second, through every button's edges.
						var u = (t % 1.0) * 2;
						Pointer.move(tree, b.x + b.width * (u < 1 ? u : 2 - u), b.y + b.height / 2);
						running();
					});
				}
			},
			{
				name: "scroll",
				run: running -> {
					var b = tree.getBounds(list.node);
					var scroller = Scroll.of(list.node);
					Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					var step = -6.0;
					// A wheel delta each tick, as a trackpad sends, turning at either end.
					scheduler.addTicker(_ -> {
						var y = scroller.y.get();
						if ((step < 0 && y >= scroller.limits().y) || (step > 0 && y <= 0))
							step = -step;
						Pointer.wheel(tree, 0, step);
						running();
					});
				}
			},
			{name: "idle-after", run: _ -> {}}
		];
		var current = -1;
		function next() {
			current++;
			if (current == steps.length) {
				phase("end");
				WindowedApp.current.quit();
				return;
			}
			var mine = current;
			phase(steps[mine].name);
			steps[mine].run(() -> current == mine);
			scheduler.after(seconds, next);
		}
		next();
	}

	static function page():Div {
		return hxx('
			<div class="flex flex-col p-6 gap-5 bg-background" width={640} height={420}>
				<div class="relative h-2 rounded-full bg-surface" width={420}>
					<div class="absolute top-0 h-2 rounded-full bg-primary" left={(offset.get() : Single)} width={20} />
				</div>
				${field = new TextField({placeholder: "Caret blinks here", width: 280})}
				${buttons = hxx('<div class="flex flex-row gap-3">
					${[for (i in 0...5) hxx('<div class="px-4 py-2 rounded-lg bg-surface hover:bg-primary border-2 border-border hover:border-primary transition-colors">
						<text class="text-sm">Button ${i + 1}</text>
					</div>')]}
				</div>')}
				${list = hxx('<div class="flex flex-col gap-1 p-1 rounded-xl bg-surface border-2 border-border overflow-y-auto" width={280} height={150}>
					${[for (i in 0...40) hxx('<div class="shrink-0 px-3 py-1 rounded-md bg-surface hover:bg-surface-elevated">
						<text class="text-sm">Row ${i + 1}</text>
					</div>')]}
				</div>')}
			</div>
		');
	}
}
