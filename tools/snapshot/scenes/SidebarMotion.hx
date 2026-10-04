import ashui.components.Sidebar;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A sidebar collapsed by its toggle and expanded again, recorded with the
	motion overlay: its width eases between the two by layout animation,
	its labels clipped as it goes, and the page beside it slides over.
	Writes `.ashui/snapshots/motion/sidebar/` (`sidebar-light` with
	`SCHEME=light`; `PLAIN=1` leaves the overlay out).
**/
class SidebarMotion {
	static final HOME = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>';
	static final SEARCH = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>';
	static final INBOX = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/></svg>';
	static final USER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>';
	static final GEAR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>';
	static final HELP = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>';

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		var plain = Sys.getEnv("PLAIN") != null;
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var collapsed = Signal.make(false);
		ashui.css.Css.load('main p { font-size: 16px; color: var(--text-primary); }');
		var build = () -> hxx('
			<div padding={24} width={760} height={460} flexDirection={Column}>
				<sidebar-layout height={400}>
					<sidebar collapsed={collapsed}>
						<sidebar-item icon={HOME} active={true}>Dashboard</sidebar-item>
						<sidebar-item icon={SEARCH}>Search</sidebar-item>
						<sidebar-item icon={INBOX}>Inbox</sidebar-item>
						<sidebar-group label="ACCOUNT">
							<sidebar-item icon={USER}>Profile</sidebar-item>
							<sidebar-item icon={GEAR}>Settings</sidebar-item>
						</sidebar-group>
						<sidebar-group label="HELP"><sidebar-item icon={HELP}>Support</sidebar-item></sidebar-group>
					</sidebar>
					<sidebar-inset><div padding={32}><p>Icon Size Comparison</p></div></sidebar-inset>
				</sidebar-layout>
			</div>
		');
		var result = MotionRecorder.record((light ? "sidebar-light" : "sidebar") + (plain ? "-plain" : ""), 760, 460, build, {
			fps: 60,
			frames: 80,
			minFrames: 75,
			clear: page.rgb(),
			overlay: !plain,
			thumbs: 12,
			before: (frame, tree, root) -> switch frame {
				case 1 | 40:
					var toggle = [for (id in tree.order()) if (ashui.css.Identity.of(tree, id) != null && ashui.css.Identity.of(tree, id).hasClass("ui-sidebar-toggle")) id][0];
					var b = tree.getBounds(new ashui.layout.Node(toggle));
					ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				case _:
			}
		});
		Sys.println(result.report);
	}
}
