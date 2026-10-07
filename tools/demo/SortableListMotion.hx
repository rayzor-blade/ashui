import ashui.core.render.Snapshot;
import ashui.debug.MotionCheck;
import ashui.debug.MotionRecorder;
import ashui.debug.MotionTrace;
import ashui.input.Focus;
import ashui.input.Keyboard;
import ashui.input.Pointer;

/** Scripted offscreen interactions for SortableList; run through its main. **/
class SortableListMotion {
	public static function run() {
		var x = 0.0, y = 0.0;
		var before:Array<String> = [];
		var nodes = new Map<String, haxe.Int64>();
		var hooks = Pointer.hooks.length;
		var focused:Null<ashui.input.Interaction> = null;
		var movedBetweenSlots = false;
		var fadedBetweenStates = false;
		var elasticReturn = false;
		var cancelledAt = Math.POSITIVE_INFINITY;
		var stride = 0.0;
		var dir = haxe.io.Path.join([Snapshot.dir(), "motion", "sortable-list"]);
		MotionRecorder.clean(dir);
		var trace = MotionTrace.start();
		Snapshot.sequence("motion/sortable-list/frame", SortableList.WIDTH, SortableList.HEIGHT, SortableList.page, 60, 210,
			(frame, tree, root) -> {
				function node(id:String):ashui.layout.Node {
					for (n in tree.order()) {
						var identity = ashui.css.Identity.of(tree, n);
						if (identity != null && identity.id == id) return new ashui.layout.Node(n);
					}
					throw 'Missing node: $id';
				}
				function order():Array<String>
					return [for (n in tree.order()) {
						var identity = ashui.css.Identity.of(tree, n);
						if (identity != null && identity.id != null && StringTools.startsWith(identity.id, "sl-row-")) identity.id;
					}];
				function hasPreview():Bool
					return Lambda.exists(tree.order(), n -> {
						var identity = ashui.css.Identity.of(tree, n);
						return identity != null && identity.id == "sl-preview";
					});
				function check(condition:Bool, message:String)
					if (!condition) throw 'Sortable list: $message';
				function hover(id:String) {
					var b = tree.getBounds(node(id));
					x = b.x + b.width / 2;
					y = b.y + b.height / 2;
					Pointer.move(tree, x, y);
				}
				function press(id:String) {
					hover(id);
					Pointer.press(tree);
				}
				function key(k:window.Key, code:window.KeyCode)
					Keyboard.input(tree, Input(Code(code), k, None, Standard, Pressed, false, Unavailable));
				switch frame {
					case 1:
						before = order();
						for (id in before) nodes.set(id, node(id).id);
						stride = tree.getBounds(node(before[1])).y - tree.getBounds(node(before[0])).y;
						hover("sl-handle-tokens");
					case 5: press("sl-handle-tokens");
					case f if (f > 5 && f <= 30): Pointer.move(tree, x, y + (f - 5) * stride * 3 / 25);
					case 31:
						// Release beyond the list, using the framework pointer hook.
						Pointer.move(tree, SortableList.WIDTH - 10, y + stride * 3);
						Pointer.release(tree);
					case 44: hover("sl-handle-notes");
					case 48:
						check(order()[3] == "sl-row-tokens", "drag did not move the first item to slot four");
						for (id in before) check(node(id).id == nodes.get(id), 'recreated $id while sorting');
						press("sl-handle-notes");
					case f if (f > 48 && f <= 63): Pointer.move(tree, x, y - (f - 48) * stride * 5 / 15);
					case 64:
						cancelledAt = ashui.animation.AnimationScheduler.main.clock;
						key(Named(Escape), Escape);
					case 65:
						Pointer.move(tree, SortableList.WIDTH - 10, SortableList.HEIGHT - 10);
						Pointer.release(tree);
					case 90:
						check(hasPreview(), "an interrupted release timer hid the new preview");
					case 140:
						check(order()[5] == "sl-row-notes" && order()[3] == "sl-row-tokens", "Escape did not restore the previous order");
						check(!hasPreview(), "the FSM did not remove the preview after fading");
						focused = ashui.input.Interaction.byId(tree, node("sl-handle-glass").id);
						Focus.set(focused, true);
						key(Named(ArrowUp), ArrowUp);
					case 154:
						check(order()[1] == "sl-row-glass", "Up did not reorder the focused item");
						check(Focus.of(tree) == focused, "keyboard sorting lost focus");
						key(Named(End), End);
					case 168:
						check(order()[5] == "sl-row-glass", "End did not move the item to the last slot");
						key(Named(Home), Home);
					case 182:
						check(order()[0] == "sl-row-glass", "Home did not move the item to the first slot");
						press("sl-reset");
						Pointer.release(tree);
					case 204:
						check(order().join(",") == before.join(","), "reset did not restore the original order");
						check(movedBetweenSlots, "no intermediate layout transition was drawn");
						check(fadedBetweenStates, "no eased opacity transition was drawn");
						check(elasticReturn, "cancelled movement did not overshoot and spring back");
						check(Pointer.hooks.length == hooks, "drag left a pointer hook installed");
						for (id in before) check(node(id).id == nodes.get(id), 'reset recreated $id');
					case _:
				}
				// A neighbour must be drawn between its old and new slot after
				// layout settles, proving this run captured a transition.
				if (frame > 10 && frame < 30) {
					var n = node("sl-row-keyboard");
					for (track in ashui.debug.MotionTrace.current.tracks)
						if (track.node == n.id && track.kind == Layout)
							for (sample in track.samples)
								if (sample.dy != null && Math.abs(sample.dy) > 1 && Math.abs(sample.dy) < stride - 1) movedBetweenSlots = true;
				}
				for (track in ashui.debug.MotionTrace.current.tracks)
					if (track.kind == Spring && track.began >= cancelledAt) {
						for (sample in track.samples) if (sample.progress > 1.01) elasticReturn = true;
					} else if (track.property == "opacity" && track.curve == "cubic-bezier(0.4, 0, 0.2, 1)")
						for (sample in track.samples)
							if (sample.progress > 0 && sample.progress < 1) fadedBetweenStates = true;
			}
		);
		trace.stop();
		var report = MotionCheck.report(trace);
		sys.io.File.saveContent(haxe.io.Path.join([dir, "report.txt"]), report);
		sys.io.File.saveContent(haxe.io.Path.join([dir, "trace.json"]), MotionCheck.json(trace));
		Snapshot.event("motion sortable-list " + dir + " frames=210");
		Sys.println(report.split("\n")[0]);
		Sys.println("Sortable list: drag, Escape, keyboard, reset, preserved nodes, eased opacity, elastic cancellation and layout transitions passed.");
	}
}
