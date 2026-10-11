import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** CSS text-shadow: hard and blurred, layered, a Tw class, on an emoji, inherited, and clipped by its box. */
class TextShadows {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		ashui.css.Css.load('
			#hard { text-shadow: 2px 2px #ef4444; }
			#soft { text-shadow: 0 2px 6px rgba(0, 0, 0, 0.45); }
			#night { background: #1e293b; }
			#glow { text-shadow: 0 0 8px #3b82f6, 0 0 2px #1d4ed8; color: white; }
			#amber { text-shadow: 3px 3px 2px #f59e0b; }
			#emoji { text-shadow: 3px 3px 3px #ef4444; }
			#parent { text-shadow: 1px 1px 0 #10b981; }
			#stop { text-shadow: none; }
			#clip { overflow: hidden; height: 40px; width: 300px; border: 1px solid #cbd5e1; text-shadow: 0 4px 10px #7c3aed; }
		');
		Snapshot.scene("text-shadows", 520, 520, () -> <div class="flex flex-col gap-4 p-6 bg-background" width={520} height={520}>
			<text id="hard" class="text-2xl font-bold">Hard shadow</text>
			<text id="soft" class="text-2xl font-bold">Blurred shadow</text>
			<div id="night" class="p-2 rounded-md"><text id="glow" class="text-2xl font-bold">Two layers, glowing</text></div>
			<text class="text-2xl font-bold text-shadow-lg">Tw text-shadow-lg</text>
			<text id="amber" class="text-xl">Offset and lightly blurred</text>
			<text id="emoji" class="text-3xl">Emoji 🎉🙂</text>
			<div id="parent" class="flex flex-col"><text class="text-lg">Inherited from a parent</text><text id="stop" class="text-lg">none stops it</text></div>
			<div id="clip" class="flex flex-col"><text class="text-xl">Clipped above</text><text class="text-xl">and below the box</text></div>
		</div>, ThemeState.get().color(Background).rgb(), 1, 2);
	}
}
