import ashui.components.Toast;
import ashui.debug.MotionRecorder;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Toasts recorded with the motion overlay: one shown, a second stacked on
	it, the pointer resting on the first so it outstays its time, the
	second closed by its button, the first leaving once the pointer goes.
	Writes `.ashui/snapshots/motion/toast/` (`toast-light` with
	`SCHEME=light`).
**/
class ToastMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('<div width={720} height={420}><toaster /></div>');
		var handles:Array<Null<ToastHandle>> = [];
		function centre(tree:ashui.layout.LayoutTree, index:Int):{x:Float, y:Float} {
			var toasts = [];
			function walk(at:haxe.Int64) {
				var identity = ashui.css.Identity.of(tree, at);
				if (identity != null && identity.hasClass("ui-toast"))
					toasts.push(at);
				for (c in tree.children(at))
					walk(c);
			}
			walk(tree.root.id);
			var b = tree.getBounds(new ashui.layout.Node(toasts[index]));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		var result = MotionRecorder.record(light ? "toast-light" : "toast", 720, 420, build, {
			fps: 60,
			frames: 180,
			minFrames: 150,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1:
					handles.push(Toaster.show({title: "Event Created", description: "Your event has been scheduled.", duration: 1.0}));
				case 20:
					handles.push(Toaster.show({title: "Success!", description: "Your changes have been saved.", variant: Success, duration: 4.0,
						action: {label: "Undo", run: () -> {}}}));
				case 40:
					var p = centre(tree, 0);
					ashui.input.Pointer.move(tree, p.x, p.y);
				case 100:
					handles[1].dismiss();
				case 130:
					ashui.input.Pointer.move(tree, 10, 10);
				case _:
			}
		});
		Sys.println(result.report);
	}
}
