import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Hxx.hxx;

/**
	Colour filters and group opacity from Tailwind classes: the same card,
	a gradient with a badge and a line of text, under no filter, grayscale,
	sepia, invert, hue-rotate-90, saturate-200, brightness-125 and
	contrast-50; and two cards at opacity-50, whose badge overlaps the
	gradient: faded as one group, the gradient does not show through it;
	blur-xs, blur-md and blur-sm with grayscale; and drop shadows, on a
	card and on a star clip path, whose shadow follows the star.
	Rendered at one and two image pixels per layout unit.
**/
class Filters {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		function card()
			return hxx('
				<div class="flex flex-col items-center justify-center gap-2 w-24 h-24 rounded-xl bg-linear-to-br from-primary via-warning to-success shadow-md">
					<div class="w-10 h-10 rounded-full bg-error border-4 border-surface" />
					<text class="text-xs font-bold text-text-inverse">Card</text>
				</div>
			');
		function labelled(filtered:ashui.layout.Element, label:String)
			return hxx('
				<div class="flex flex-col items-center gap-2">
					${filtered}
					<text class="text-xs text-text-secondary">${label}</text>
				</div>
			');
		// Class strings are read at compile time, so each filter is written out.
		var build = () -> hxx('
			<div class="flex flex-row flex-wrap items-start p-6 gap-6" width={700} height={460}>
				${labelled(hxx('<div>${card()}</div>'), "none")}
				${labelled(hxx('<div class="grayscale">${card()}</div>'), "grayscale")}
				${labelled(hxx('<div class="sepia">${card()}</div>'), "sepia")}
				${labelled(hxx('<div class="invert">${card()}</div>'), "invert")}
				${labelled(hxx('<div class="hue-rotate-90">${card()}</div>'), "hue-rotate-90")}
				${labelled(hxx('<div class="saturate-200">${card()}</div>'), "saturate-200")}
				${labelled(hxx('<div class="brightness-125">${card()}</div>'), "brightness-125")}
				${labelled(hxx('<div class="contrast-50">${card()}</div>'), "contrast-50")}
				${labelled(hxx('<div class="opacity-50">${card()}</div>'), "opacity-50")}
				${labelled(hxx('<div class="opacity-50 grayscale">${card()}</div>'), "opacity-50 grayscale")}
				${labelled(hxx('<div class="blur-xs">${card()}</div>'), "blur-xs")}
				${labelled(hxx('<div class="blur-md">${card()}</div>'), "blur-md")}
				${labelled(hxx('<div class="blur-sm grayscale">${card()}</div>'), "blur-sm grayscale")}
				${labelled(hxx('<div class="drop-shadow-xl">${card()}</div>'), "drop-shadow-xl")}
				${labelled(hxx('<div class="drop-shadow-2xl"><div class="w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:polygon(50%_0,61%_35%,98%_35%,68%_57%,79%_91%,50%_70%,21%_91%,32%_57%,2%_35%,39%_35%)]" /></div>'), "star, drop-shadow-2xl")}
			</div>
		');
		Snapshot.scene("filters", 700, 460, build, page.rgb(), page.a);
		Snapshot.scene("filters@2x", 700, 460, build, page.rgb(), page.a, 2.0);
	}
}
