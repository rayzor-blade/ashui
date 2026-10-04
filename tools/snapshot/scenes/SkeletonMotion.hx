import ashui.components.Avatar;
import ashui.components.Skeleton;
import ashui.debug.MotionRecorder;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Skeletons shimmering, recorded with the motion overlay: a highlight
	sweeps across each, a full pass per loop. Writes
	`.ashui/snapshots/motion/skeleton/` (`skeleton-light` with
	`SCHEME=light`); `PLAIN=1` leaves the overlay out, to see the shimmer itself.
**/
class SkeletonMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div flexDirection={Row} padding={32} gap={24} width={520} height={160} alignItems={Center}>
				<skeleton width={48} height={48} class="rounded-full" />
				<div flexDirection={Column} gap={8}><skeleton width={240} height={16} /><skeleton width={180} height={16} /><skeleton width={200} height={16} /></div>
			</div>
		');
		var plain = Sys.getEnv("PLAIN") != null;
		var result = MotionRecorder.record((light ? "skeleton-light" : "skeleton") + (plain ? "-plain" : ""), 520, 160, build,
			{fps: 30, frames: 48, minFrames: 48, clear: page.rgb(), thumbs: 9, overlay: !plain, scale: 2});
		Sys.println(result.report.split("\n")[0]);
	}
}
