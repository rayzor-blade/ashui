import ashui.app.WindowedApp;
import ashui.components.NumberInput;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Scroll;
import ashui.reactive.Signal;
import ashui.ui.Div;

/** Native wheel phases, device units and batching through the real window dispatcher (095fab4). **/
class NumberWheelWindow {
	static function check(name:String, ok:Bool):Void {
		if (!ok) throw name;
		Sys.println("ok   " + name);
	}

	static function main():Void {
		var value = Signal.make(50.0);
		var root:Div = null;
		var ran = false;
		WindowedApp.run({title: "Wheel gesture checks", width: 420, height: 240, active: false,
			onFrame: (_, _) -> {
				if (ran) return;
				ran = true;
				var app = WindowedApp.current, tree = app.tree, scale = app.window.scaleFactor();
				var scroll = Scroll.of(root.node);
				function settle() {
					@:privateAccess app.applyPointer(false);
					for (_ in 0...3) { tree.flush(); tree.computeLayout(root.node, 420, 240); }
				}
				function send(event:window.Event) @:privateAccess app.handle(event);
				function hoverNumber() {
					var id = Css.query(tree, root.node.id, "#number")[0];
					var b = tree.getBounds(Identity.of(tree, id).node);
					send(CursorMoved((b.x + b.width / 2) * scale, (b.y + b.height / 2 - scroll.y.get()) * scale, 0));
				}
				send(CursorMoved(200 * scale, 20 * scale, 0));
				send(MouseWheel(PixelDelta(0, -10 * scale), Started, 0)); settle();
				check("pixel wheel deltas normalize to layout units", scroll.y.get() == 10);
				hoverNumber(); send(MouseWheel(PixelDelta(0, -40 * scale), Moved, 0));
				// A later move in the same native batch cannot redirect the queued wheel.
				send(CursorMoved(200 * scale, 100 * scale, 0)); settle();
				check("batched native parent scrolling never changes a numeric descendant", value.get() == 50 && scroll.y.get() == 50);
				send(MouseWheel(PixelDelta(0, 0), Ended, 0));
				scroll.scrollTo(0, 0); settle(); hoverNumber();
				send(MouseWheel(PixelDelta(0, 0), Started, 0));
				send(MouseWheel(LineDelta(0, 1), Moved, 0));
				send(MouseWheel(LineDelta(0, 1), Moved, 0));
				send(MouseWheel(PixelDelta(0, 40 * scale), Ended, 0)); settle();
				check("coalesced lines and final pixel deltas edit a fresh numeric gesture", value.get() == 53 && scroll.y.get() == 0);
				send(CursorMoved(200 * scale, 20 * scale, 0));
				send(MouseWheel(LineDelta(0, -1), Started, 0));
				send(MouseWheel(PixelDelta(0, 0), Cancelled, 0)); settle(); hoverNumber();
				send(MouseWheel(LineDelta(0, 1), Started, 0)); settle();
				check("native cancellation releases parent gesture ownership", value.get() == 54 && scroll.y.get() == 40);
				send(CursorMoved(200 * scale, 20 * scale, 0));
				send(MouseWheel(LineDelta(0, -1), Started, 0));
				send(Focused(false)); scroll.scrollTo(0, 0); settle(); hoverNumber();
				send(MouseWheel(LineDelta(0, 1), Moved, 0)); settle();
				check("losing window focus cancels an unfinished parent gesture", value.get() == 55 && scroll.y.get() == 0);
				app.quit();
			}}, () -> {
			root = <div width={420} height={240} class="flex-col overflow-y-auto">
				<div height={700} class="flex-col shrink-0">
					<div height={80} class="shrink-0" />
					<number-input id="number" value={value} min={0} max={100} />
				</div>
			</div>;
			return root;
		});
		check("the window dispatcher checks actually ran", ran);
		Sys.println("6 checks: ALL PASSED");
	}
}
