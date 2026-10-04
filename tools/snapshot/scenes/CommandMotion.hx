import ashui.components.Combobox;
import ashui.components.Command;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A command list filtered by typing and driven by the arrows, and a
	combobox opened, searched and an option chosen, recorded with the motion
	overlay. Writes `.ashui/snapshots/motion/command/`.
**/
class CommandMotion {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var picked = Signal.make("");
		var framework = Signal.make("");
		var build = () -> hxx('
			<div flexDirection={Row} padding={32} gap={40} width={760} height={460} alignItems={Start}>
				<command onSelect={v -> picked.set(v)} width={320}>
					<command-input id="search" placeholder="Type a command or search..." />
					<command-list>
						<command-empty>No results found.</command-empty>
						<command-group heading="Suggestions">
							<command-item value="calendar">Calendar</command-item>
							<command-item value="emoji" keywords={["smile"]}>Search Emoji</command-item>
							<command-item value="calculator">Calculator</command-item>
						</command-group>
						<command-separator />
						<command-group heading="Settings">
							<command-item value="profile" shortcut="Ctrl+P">Profile</command-item>
							<command-item value="settings" shortcut="Ctrl+S">Settings</command-item>
						</command-group>
					</command-list>
				</command>
				<combobox id="fw" value={framework} placeholder="Select framework..." options={[
					{value: "haxe", label: "Haxe"}, {value: "heaps", label: "Heaps"}, {value: "openfl", label: "OpenFL"}, {value: "kha", label: "Kha"}
				]} />
			</div>
		');
		function at(tree:ashui.layout.LayoutTree, id:String):{x:Float, y:Float} {
			var node = byId(tree, tree.root.id, id);
			var b = tree.getBounds(new ashui.layout.Node(node));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function key(k:window.Key, code:window.KeyCode):window.KeyEvent
			return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
		function type(tree:ashui.layout.LayoutTree, text:String)
			ashui.input.Keyboard.text(tree, text);
		var result = MotionRecorder.record("command", 760, 460, build, {
			fps: 60,
			frames: 120,
			minFrames: 110,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1:
					var p = at(tree, "search");
					ashui.input.Pointer.move(tree, p.x, p.y);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				case 8: type(tree, "ca");
				case 20: ashui.input.Keyboard.input(tree, key(Named(ArrowDown), ArrowDown));
				case 30: ashui.input.Keyboard.input(tree, key(Named(Enter), Enter));
				case 44:
					var p = at(tree, "fw");
					ashui.input.Pointer.move(tree, p.x, p.y);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				case 64: type(tree, "op");
				case 80: ashui.input.Keyboard.input(tree, key(Named(Enter), Enter));
				case _:
			}
		});
		Sys.println(result.report.split("\n")[0]);
		Sys.println('picked ${picked.get()} framework ${framework.get()}');
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
