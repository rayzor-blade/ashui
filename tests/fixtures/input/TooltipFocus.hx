import ashui.animation.AnimationScheduler;
import ashui.components.Button;
import ashui.components.Tooltip;
import ashui.css.Css;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.RestrainedTheme;
import ashui.ui.TopLayer;

/** Descendant keyboard focus uses Tooltip's existing FSM and owner (8dd8f7e). **/
class TooltipFocus {
	static var checks = 0;
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		checks++;
		Sys.println('ok   $name');
	}
	static function main() {
		for (dark in [true, false]) {
			ThemeState.init(RestrainedTheme.bundle(), dark ? Dark : Light);
			var tree = new LayoutTree(), stop:Void->Void = null;
			var root = Owner.root(tree, dispose -> {
				stop = dispose;
				return <div width={600} height={160}>
					<tooltip id="trigger" label="Save changes" delay={0.5}>
						<button id="first">Save</button><button id="second">Save all</button>
					</tooltip>
					<button id="outside">Outside</button>
				</div>;
			});
			function settle() { tree.flush(); tree.computeLayout(root.node, 600, 160); }
			function control(id:String) return Interaction.byId(tree, Css.query(tree, root.node.id, "#" + id)[0]);
			function tips() return Css.query(tree, root.node.id, ".ui-tooltip").length;
			function closed() { AnimationScheduler.main.tick(1); settle(); }
			settle();
			var first = control("first"), second = control("second"), outside = control("outside");
			Focus.set(first, false); settle();
			check("pointer focus does not open the tooltip", tips() == 0);
			Focus.set(first, true); settle();
			check("keyboard focus on the child opens immediately", tips() == 1 && TopLayer.openEntries().length == 1);
			var entry = TopLayer.openEntries()[0];
			Focus.set(second, true); settle();
			check("keyboard focus stays within without replacing its entry", tips() == 1 && TopLayer.openEntries()[0] == entry);
			var b = tree.getBounds(first.node);
			Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2); settle();
			Pointer.leave(tree); settle();
			check("pointer leave preserves the keyboard tooltip", tips() == 1 && TopLayer.openEntries().length == 1);
			Focus.set(outside, true); settle();
			check("focus leaving the trigger starts its existing exit", tips() == 1 && TopLayer.openEntries().length == 0);
			closed();
			check("focus exit removes the tooltip", tips() == 0 && TopLayer.openEntries().length == 0);
			Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2); settle();
			AnimationScheduler.main.tick(0.2); settle();
			check("pointer hover keeps its delay", tips() == 0);
			Focus.set(first, true); settle();
			check("keyboard focus opens a waiting tooltip immediately", tips() == 1);
			Pointer.press(tree); settle();
			check("pointer press still dismisses the tooltip", TopLayer.openEntries().length == 0);
			Pointer.release(tree); Pointer.leave(tree); Focus.clear(tree); closed();
			Focus.set(first, true); settle();
			check("tooltip reopens after its previous exit", tips() == 1);
			stop(); AnimationScheduler.main.tick(1); tree.flush();
			check("owner disposal releases the focused tooltip", root.node == null && TopLayer.openEntries().length == 0);
			tree.dispose();
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
