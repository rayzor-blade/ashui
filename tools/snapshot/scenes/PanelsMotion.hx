import ashui.components.Button;
import ashui.components.ContextMenu;
import ashui.components.HoverCard;
import ashui.components.Sheet;
import ashui.components.Toggle;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Toggles, a toggle group, a sheet, a hover card and a context menu,
	recorded with the motion overlay: a toggle pressed, the group's choice
	moved, the sheet opened and closed, the hover card shown by resting on
	its trigger and left, the context menu opened by a right-click and an
	item chosen. Writes `.ashui/snapshots/motion/panels/` (`panels-light`
	with `SCHEME=light`).
**/
class PanelsMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var align = Signal.make(["left"]);
		var chosen = Signal.make("");
		var build = () -> hxx('
			<div flexDirection={Column} padding={32} gap={24} width={900} height={560}>
				<div flexDirection={Row} gap={12} alignItems={Center}>
					<toggle id="bold" pressed={true}>B</toggle><toggle id="italic">I</toggle><toggle variant={Outline}>U</toggle>
					<toggle-group value={align} variant={Outline}>
						<toggle-group-item value="left">Left</toggle-group-item>
						<toggle-group-item id="center" value="center">Center</toggle-group-item>
						<toggle-group-item value="right">Right</toggle-group-item>
					</toggle-group>
				</div>
				<div flexDirection={Row} gap={24} alignItems={Center}>
					<sheet>
						<sheet-trigger id="sheet" variant={Outline}>Open Right Sheet</sheet-trigger>
						<sheet-content>
							<sheet-header><sheet-title>Edit Profile</sheet-title><sheet-description>Make changes to your profile here.</sheet-description></sheet-header>
							<p>Settings go here.</p>
							<sheet-footer><sheet-close id="sheetClose">Cancel</sheet-close><button>Save</button></sheet-footer>
						</sheet-content>
					</sheet>
					<hover-card>
						<hover-card-trigger id="who"><p>@johndoe</p></hover-card-trigger>
						<hover-card-content><p>John Doe</p><p>Building UI in Haxe. Joined December 2021.</p></hover-card-content>
					</hover-card>
				</div>
				<context-menu>
					<context-menu-trigger id="area"><div width={320} height={120} justifyContent={Justify.Center} alignItems={Center}><p>Right-click here</p></div></context-menu-trigger>
					<context-menu-content>
						<context-menu-item shortcut="Ctrl+[">Back</context-menu-item>
						<context-menu-item id="reload" shortcut="Ctrl+R" onSelect={() -> chosen.set("reload")}>Reload</context-menu-item>
						<context-menu-separator />
						<context-menu-item>Inspect</context-menu-item>
					</context-menu-content>
				</context-menu>
			</div>
		');
		function at(tree:ashui.layout.LayoutTree, id:String):{x:Float, y:Float} {
			var node = byId(tree, tree.root.id, id);
			if (node == null)
				throw 'no element #$id';
			var b = tree.getBounds(new ashui.layout.Node(node));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function click(tree:ashui.layout.LayoutTree, id:String, ?button:window.MouseButton) {
			var p = at(tree, id);
			ashui.input.Pointer.move(tree, p.x, p.y);
			ashui.input.Pointer.press(tree, button == null ? Left : button);
			ashui.input.Pointer.release(tree, button == null ? Left : button);
		}
		var result = MotionRecorder.record(light ? "panels-light" : "panels", 900, 560, build, {
			fps: 60,
			frames: 200,
			minFrames: 170,
			settle: 0.3,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1: click(tree, "italic");
				case 12: click(tree, "center");
				case 24: click(tree, "sheet");
				case 60: click(tree, "sheetClose");
				case 84:
					var p = at(tree, "who");
					ashui.input.Pointer.move(tree, p.x, p.y);
				case 130:
					ashui.input.Pointer.move(tree, 880, 540);
				case 150: click(tree, "area", Right);
				case 166: click(tree, "reload");
				case _:
			}
		});
		Sys.println(result.report);
		Sys.println('align ${align.get()} chosen ${chosen.get()}');
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
