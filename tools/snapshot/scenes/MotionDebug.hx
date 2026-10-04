import ashui.components.Accordion;
import ashui.components.Button;
import ashui.components.Tabs;
import ashui.components.ToggleSwitch;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Records the components' motion with the motion overlay, for review: the
	pointer comes to rest on a button, a switch turns on, a tab is chosen and
	an accordion section opens, a few frames apart. Writes frames, a
	filmstrip, curves and a report to `.ashui/snapshots/motion/components/`.
**/
class MotionDebug {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var on = Signal.make(false);
		var tab = Signal.make("one");
		var open = Signal.make(([] : Array<String>));
		var build = () -> hxx('
			<div flexDirection={Column} padding={24} gap={20} width={520} height={420}>
				<div flexDirection={Row} gap={24} alignItems={Center}>
					<button id="save">Save</button>
					<toggle-switch checked={on} />
				</div>
				<tabs value={tab}>
					<tabs-list><tabs-trigger value="one">One</tabs-trigger><tabs-trigger value="two">Two</tabs-trigger></tabs-list>
					<tabs-content value="one"><p>The first panel.</p></tabs-content>
					<tabs-content value="two"><p>The second panel.</p></tabs-content>
				</tabs>
				<accordion value={open}>
					<accordion-item value="a"><accordion-trigger>Is it animated?</accordion-trigger>
						<accordion-content><p>Yes, by layout animation, and every frame of it is traced.</p></accordion-content></accordion-item>
					<accordion-item value="b"><accordion-trigger>Can it be checked?</accordion-trigger>
						<accordion-content><p>The report says.</p></accordion-content></accordion-item>
				</accordion>
			</div>
		');
		var result = MotionRecorder.record("components", 520, 420, build, {
			fps: 60,
			frames: 90,
			minFrames: 20,
			settle: 0.5,
			clear: page.rgb(),
			before: (frame, tree, root) -> {
				switch frame {
					case 1:
						var b = tree.getBounds(new ashui.layout.Node(byId(tree, root.node.id, "save")));
						ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					case 6:
						on.set(true);
					case 11:
						tab.set("two");
					case 16:
						open.set(["a"]);
					case _:
				}
			}
		});
		Sys.println(result.report);
	}

	/** The node under `at` whose CSS id is `id`. **/
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
