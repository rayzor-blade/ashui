import ashui.components.Button;
import ashui.components.Dialog;
import ashui.debug.MotionRecorder;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A dialog opened from its trigger at frame 1 and closed from its Cancel
	button at frame 24, recorded with the motion overlay to
	`.ashui/snapshots/motion/dialog/` (or `dialog-light` with `SCHEME=light`).
**/
class DialogMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div flexDirection={Column} padding={32} gap={16} width={720} height={480}>
				<dialog>
					<dialog-trigger id="open" variant={Outline}>Open Basic Dialog</dialog-trigger>
					<dialog-content>
						<dialog-header>
							<dialog-title>Edit Profile</dialog-title>
							<dialog-description>Make changes to your profile here. Click save when you are done.</dialog-description>
						</dialog-header>
						<p>This is a basic dialog with custom content.</p>
						<dialog-footer><dialog-close id="cancel">Cancel</dialog-close><button>Confirm</button></dialog-footer>
					</dialog-content>
				</dialog>
			</div>
		');
		function click(tree:ashui.layout.LayoutTree, root:ashui.layout.Element, id:String) {
			var node = byId(tree, root.node.id, id);
			if (node == null) {
				// In the top layer, under the tree's root rather than the scene's.
				node = byId(tree, tree.root.id, id);
			}
			if (node == null)
				throw 'no element #$id to click';
			var b = tree.getBounds(new ashui.layout.Node(node));
			ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(tree);
			ashui.input.Pointer.release(tree);
		}
		var result = MotionRecorder.record(light ? "dialog-light" : "dialog", 720, 480, build, {
			fps: 60,
			frames: 60,
			minFrames: 30,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1: click(tree, root, "open");
				case 24: click(tree, root, "cancel");
				case _:
			}
		});
		Sys.println(result.report);
	}

	static function byId(tree:ashui.layout.LayoutTree, at:haxe.Int64, id:String):Null<haxe.Int64> {
		var identity = ashui.css.Identity.of(tree, at);
		if (identity != null && identity.id == id)
			return at;
		for (child in tree.children(at)) {
			var found = byId(tree, child, id);
			if (found != null)
				return found;
		}
		return null;
	}
}
