import ashui.components.Badge;
import ashui.components.Card;
import ashui.components.Label;
import ashui.components.Size;
import ashui.components.Tabs;
import ashui.css.Css;
import ashui.debug.MotionRecorder;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.Node;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** One selected background slides and resizes, including rapid choices and tray resizing (5bc757e). **/
class TabsMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var selected = signal("overview"), width = signal((624 : Single));
		var build = () -> <div class="bg-background flex-col p-6 gap-4" width={760} height={780}>
			<div class="flex-col gap-2">
				<text class="text-xl font-semibold">Tabs · moving selection</text>
				<text class="text-sm text-secondary">One background follows clicks, keyboard navigation and layout.</text>
			</div>
			<for {density in [Size.Sm, Size.Md, Size.Lg]}>
				<card width={712}>
					<card-content class="flex-col gap-4">
						<div class="flex-row items-center justify-between">
							<label>${density == Size.Sm ? "Small" : density == Size.Md ? "Medium · default" : "Large"}</label>
							<badge variant={Secondary}>${selected.get() == "overview" ? "Overview" : selected.get() == "activity" ? "Activity" : "Keyboard shortcuts"}</badge>
						</div>
						<tabs size={density} value={selected} width={width}>
							<tabs-list>
								<tabs-trigger value="overview" id={"overview-" + density} flexGrow={1}>Overview</tabs-trigger>
								<tabs-trigger value="activity" id={"activity-" + density} flexGrow={1}>Activity</tabs-trigger>
								<tabs-trigger value="shortcuts" id={"shortcuts-" + density} flexGrow={1}>Keyboard shortcuts</tabs-trigger>
								<tabs-trigger value="archive" disabled={true} flexGrow={1}>Archive</tabs-trigger>
							</tabs-list>
							<tabs-content value="overview"><text class="text-sm text-secondary">Your workspace at a glance.</text></tabs-content>
							<tabs-content value="activity"><text class="text-sm text-secondary">The latest changes across your workspace.</text></tabs-content>
							<tabs-content value="shortcuts"><text class="text-sm text-secondary">Use the arrow keys, Home and End to move between tabs.</text></tabs-content>
						</tabs>
					</card-content>
				</card>
			</for>
			<!-- Compact unequal labels keep their intrinsic text width and padding (4a624a1). -->
			<card width={712}>
				<card-content class="flex-col gap-4">
					<label>Compact · unequal labels</label>
					<tabs size={Sm} value={selected} width={250}>
						<tabs-list>
							<tabs-trigger value="overview" class="flex-auto">Object</tabs-trigger>
							<tabs-trigger value="activity" class="flex-auto">Physics</tabs-trigger>
							<tabs-trigger value="shortcuts" class="flex-auto">Animation</tabs-trigger>
						</tabs-list>
					</tabs>
				</card-content>
			</card>
		</div>;
		var result = MotionRecorder.record(light ? "tabs-light" : "tabs", 760, 780, build, {
			fps: 60, frames: 180, minFrames: 170, settle: 0.5,
			clear: ThemeState.get().color(Background).rgb(),
			before: (frame, tree, root) -> {
				function node(id:String):Node return new Node(Css.query(tree, root.node.id, "#" + id)[0]);
				function click(id:String) {
					var b = tree.getBounds(node(id));
					Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					Pointer.press(tree); Pointer.release(tree);
				}
				switch frame {
					case 5: click("activity-sm");
					case 30: click("shortcuts-lg");
					case 35: click("overview-md");
					case 65: click("shortcuts-sm");
					case 100:
						Pointer.leave(tree);
						Focus.set(Interaction.of(node("shortcuts-lg")), true);
						Keyboard.input(tree, Input(Code(Home), Named(Home), None, Standard, Pressed, false, Unavailable));
					case 130: width.set(664);
					case 150: selected.set("activity");
					case _:
				}
			}
		});
		Sys.println(result.report);
	}
}
