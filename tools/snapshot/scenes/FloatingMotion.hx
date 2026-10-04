import ashui.components.Button;
import ashui.components.DropdownMenu;
import ashui.components.Popover;
import ashui.components.Tooltip;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	The floating components recorded with the motion overlay: a popover
	opened and closed by its trigger, a dropdown menu opened and an item
	chosen, and a tooltip shown by resting on its trigger. Writes
	`.ashui/snapshots/motion/floating/` (`floating-light` with
	`SCHEME=light`).
**/
class FloatingMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var chosen = Signal.make("");
		var build = () -> hxx('
			<div flexDirection={Row} padding={32} gap={48} width={760} height={420} alignItems={Start}>
				<popover>
					<popover-trigger id="pop">Open Popover</popover-trigger>
					<popover-content>
						<p>Dimensions</p>
						<p>Set the dimensions for the layer.</p>
					</popover-content>
				</popover>
				<dropdown-menu>
					<dropdown-menu-trigger id="menu">Options</dropdown-menu-trigger>
					<dropdown-menu-content>
						<dropdown-menu-label>My Account</dropdown-menu-label>
						<dropdown-menu-item id="profile" shortcut="Ctrl+P" onSelect={() -> chosen.set("profile")}>Profile</dropdown-menu-item>
						<dropdown-menu-item shortcut="Ctrl+B">Billing</dropdown-menu-item>
						<dropdown-menu-item shortcut="Ctrl+S">Settings</dropdown-menu-item>
						<dropdown-menu-separator />
						<dropdown-menu-item destructive={true}>Log out</dropdown-menu-item>
					</dropdown-menu-content>
				</dropdown-menu>
				<tooltip label="Add to library" delay={0.1}><button id="tip" variant={Outline}>Hover me</button></tooltip>
			</div>
		');
		function at(tree:ashui.layout.LayoutTree, id:String):{x:Float, y:Float} {
			var node = byId(tree, tree.root.id, id);
			if (node == null)
				throw 'no element #$id';
			var b = tree.getBounds(new ashui.layout.Node(node));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function click(tree:ashui.layout.LayoutTree, id:String) {
			var p = at(tree, id);
			ashui.input.Pointer.move(tree, p.x, p.y);
			ashui.input.Pointer.press(tree);
			ashui.input.Pointer.release(tree);
		}
		var result = MotionRecorder.record(light ? "floating-light" : "floating", 760, 420, build, {
			fps: 60,
			frames: 120,
			minFrames: 90,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1: click(tree, "pop");
				case 24: click(tree, "pop");
				case 34: click(tree, "menu");
				case 58: click(tree, "profile");
				case 70:
					var p = at(tree, "tip");
					ashui.input.Pointer.move(tree, p.x, p.y);
				case _:
			}
		});
		Sys.println(result.report);
		Sys.println('chosen: ${chosen.get()}');
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
