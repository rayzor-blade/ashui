import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/**
	CSS text-decoration: lines, styles, colour, thickness, offset, the
	shorthand, and how an ancestor's line stacks with a descendant's: a
	descendant's own `none` draws nothing of its own but does not undo
	the ancestor's line, and a descendant's own line draws beside it.
**/
class TextDecorations {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		ashui.css.Css.load('
			#under { text-decoration-line: underline; }
			#over { text-decoration-line: overline; }
			#through { text-decoration-line: line-through; }
			#both { text-decoration-line: underline line-through; }
			#red { text-decoration: underline red; }
			#double { text-decoration-line: underline; text-decoration-style: double; }
			#dotted { text-decoration-line: underline; text-decoration-style: dotted; text-decoration-color: #3b82f6; }
			#dashed { text-decoration-line: underline; text-decoration-style: dashed; }
			#thick { text-decoration-line: underline; text-decoration-thickness: 4px; text-underline-offset: 6px; }
			#parent { text-decoration: underline; }
			#own-none { text-decoration: none; }
			#own-over { text-decoration: overline; }
		');
		Snapshot.scene("text-decorations", 420, 460, () -> <div class="flex flex-col gap-3 p-6 bg-background" width={420} height={460}>
			<text id="under" class="text-xl">Underline</text>
			<text id="over" class="text-xl">Overline</text>
			<text id="through" class="text-xl">Line-through</text>
			<text id="both" class="text-xl">Underline and through</text>
			<text id="red" class="text-xl">Shorthand, red</text>
			<text id="double" class="text-xl">Double</text>
			<text id="dotted" class="text-xl">Dotted, blue</text>
			<text id="dashed" class="text-xl">Dashed</text>
			<text id="thick" class="text-xl">Thick, offset</text>
			<div id="parent" class="flex flex-col gap-3">
				<text class="text-lg">Inherited line</text>
				<text id="own-none" class="text-lg">Own none, still underlined</text>
				<text id="own-over" class="text-lg">Own overline stacks too</text>
			</div>
		</div>, ThemeState.get().color(Background).rgb(), 1, 2);
	}
}
