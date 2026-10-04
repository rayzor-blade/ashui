import ashui.components.Accordion;
import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/** An accordion's first item opening at frame 1, at 60 frames a second: it grows, revealing its content, as the items below slide down. **/
class AccordionMotion {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var open = Signal.make(([] : Array<String>));
		var build = () -> hxx('
			<div flexDirection={Column} padding={24} width={360} height={300}>
				<accordion value={open}>
					<accordion-item value="a"><accordion-trigger>Is it accessible?</accordion-trigger>
						<accordion-content><p>Yes. It follows the WAI-ARIA design pattern, and the keys move between its sections.</p></accordion-content></accordion-item>
					<accordion-item value="b"><accordion-trigger>Is it styled?</accordion-trigger>
						<accordion-content><p>Yes, by CSS you can override.</p></accordion-content></accordion-item>
					<accordion-item value="c"><accordion-trigger>Is it animated?</accordion-trigger>
						<accordion-content><p>Yes, by layout animation.</p></accordion-content></accordion-item>
				</accordion>
			</div>
		');
		Snapshot.sequence("accordion", 360, 300, build, 60, 16, (frame, tree, root) -> if (frame == 1) open.set(["a"]), page.rgb(), page.a, 2.0);
	}
}
