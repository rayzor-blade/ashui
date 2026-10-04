import ashui.components.Menubar;
import ashui.components.NavigationMenu;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A menubar recorded with the motion overlay: File opened by a press, the
	pointer crossing to Edit, which opens in its place, the right arrow
	moving on to View, and Escape closing it; then a navigation menu's
	Products opened by resting on it, Services opening in its place, and both
	left. Writes
	`.ashui/snapshots/motion/menubar/`.
**/
class MenubarMotion {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div flexDirection={Column} padding={32} width={640} height={360}>
				<menubar>
					<menubar-menu><menubar-trigger id="file">File</menubar-trigger>
						<menubar-content><menubar-item shortcut="Ctrl+N">New Tab</menubar-item><menubar-item shortcut="Ctrl+O">Open</menubar-item><menubar-separator /><menubar-item>Print</menubar-item></menubar-content></menubar-menu>
					<menubar-menu><menubar-trigger id="edit">Edit</menubar-trigger>
						<menubar-content><menubar-item shortcut="Ctrl+Z">Undo</menubar-item><menubar-item shortcut="Ctrl+Y">Redo</menubar-item></menubar-content></menubar-menu>
					<menubar-menu><menubar-trigger id="view">View</menubar-trigger>
						<menubar-content><menubar-item>Zoom In</menubar-item><menubar-item>Zoom Out</menubar-item></menubar-content></menubar-menu>
				</menubar>
				<div height={140} />
				<navigation-menu>
					<navigation-menu-link active={true}>Home</navigation-menu-link>
					<navigation-menu-item><navigation-menu-trigger id="products">Products</navigation-menu-trigger>
						<navigation-menu-content><navigation-menu-link>Laptops</navigation-menu-link><navigation-menu-link>Phones</navigation-menu-link></navigation-menu-content></navigation-menu-item>
					<navigation-menu-item><navigation-menu-trigger id="services">Services</navigation-menu-trigger>
						<navigation-menu-content><navigation-menu-link>Support</navigation-menu-link><navigation-menu-link>Consulting</navigation-menu-link></navigation-menu-content></navigation-menu-item>
					<navigation-menu-link>About</navigation-menu-link>
				</navigation-menu>
			</div>
		');
		function at(tree:ashui.layout.LayoutTree, id:String):{x:Float, y:Float} {
			var node = byId(tree, tree.root.id, id);
			var b = tree.getBounds(new ashui.layout.Node(node));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function key(k:window.Key, code:window.KeyCode):window.KeyEvent
			return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
		var result = MotionRecorder.record("menubar", 640, 360, build, {
			fps: 60,
			frames: 170,
			minFrames: 160,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1:
					var p = at(tree, "file");
					ashui.input.Pointer.move(tree, p.x, p.y);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				case 24:
					var p = at(tree, "edit");
					ashui.input.Pointer.move(tree, p.x, p.y);
				case 48:
					ashui.input.Keyboard.input(tree, key(Named(ArrowRight), ArrowRight));
				case 66:
					ashui.input.Keyboard.input(tree, key(Named(Escape), Escape));
				case 84:
					var p = at(tree, "products");
					ashui.input.Pointer.move(tree, p.x, p.y);
				case 114:
					var p = at(tree, "services");
					ashui.input.Pointer.move(tree, p.x, p.y);
				case 140:
					ashui.input.Pointer.move(tree, 620, 340);
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
