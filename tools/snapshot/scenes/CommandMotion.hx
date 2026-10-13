import ashui.components.Combobox;
import ashui.components.Command;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	A command list filtered by typing and driven by the arrows, and a
	combobox opened, searched and an option chosen, recorded with the motion
	overlay. Writes `.ashui/snapshots/motion/command/`.
**/
class CommandMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var picked = Signal.make("");
		var framework = Signal.make("");
		// 6a88875 / 08938d7: a declarative catalog tall enough to exercise selection reveal.
		var suggestions = Signal.make([
			{value: "calendar", label: "Calendar"}, {value: "emoji", label: "Search Emoji"}, {value: "calculator", label: "Calculator"},
			{value: "files", label: "Files"}, {value: "downloads", label: "Downloads"}, {value: "history", label: "History"},
			{value: "library", label: "Library"}, {value: "terminal", label: "Terminal"}, {value: "theme", label: "Appearance"},
			{value: "help", label: "Help"}
		]);
		var build = () ->
			<div flexDirection={Row} padding={32} gap={40} width={760} height={460} alignItems={Start}>
				<command onSelect={v -> picked.set(v)} width={320}>
					<command-input id="search" placeholder="Type a command or search..." />
					<command-list>
						<command-empty>No results found.</command-empty>
						<command-group heading="Suggestions">
							<for {tool in suggestions.get()}><command-item value={tool.value} keywords={tool.value == "emoji" ? ["smile"] : []}>{tool.label}</command-item></for>
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
		;
		function at(tree:ashui.layout.LayoutTree, id:String):{x:Float, y:Float} {
			var node = byId(tree, tree.root.id, id);
			var b = tree.getBounds(new ashui.layout.Node(node));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function key(k:window.Key, code:window.KeyCode):window.KeyEvent
			return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
		function type(tree:ashui.layout.LayoutTree, text:String)
			ashui.input.Keyboard.text(tree, text);
		var result = MotionRecorder.record(light ? "command-light" : "command", 760, 460, build, {
			fps: 60,
			frames: 160,
			minFrames: 145,
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
				case 96:
					var input = ashui.ui.Input.at(tree, byId(tree, root.node.id, "search"));
					input.value.set("");
					ashui.input.Focus.set(ashui.input.Interaction.of(input.node), true);
				case 105: ashui.input.Keyboard.input(tree, key(Named(End), End));
				case 125:
					suggestions.set(suggestions.get().slice(0, 3));
				case 135: ashui.input.Keyboard.input(tree, key(Named(Home), Home));
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
