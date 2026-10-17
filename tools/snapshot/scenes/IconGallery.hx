import ashui.components.Icon;
import ashui.core.render.Snapshot;
import ashui.icons.Remix;
import ashui.svg.SvgDocument;
import ashui.theme.ColorScheme;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/** A few of the Remix icons as `<icon>` elements, tinted by the text colour, light and dark. **/
class IconGallery {
	static final rows:Array<Array<SvgDocument>> = [
		[Remix.PLAY_LINE, Remix.PAUSE_LINE, Remix.SAVE_3_LINE, Remix.SETTINGS_3_LINE, Remix.SEARCH_LINE, Remix.HOME_LINE, Remix.USER_LINE, Remix.FOLDER_LINE],
		[Remix.FILE_LINE, Remix.MAIL_LINE, Remix.CHAT_3_LINE, Remix.NOTIFICATION_LINE, Remix.HEART_LINE, Remix.STAR_LINE, Remix.BOOKMARK_LINE, Remix.DOWNLOAD_LINE],
		[Remix.UPLOAD_LINE, Remix.SHARE_LINE, Remix.LINK, Remix.EDIT_LINE, Remix.DELETE_BIN_LINE, Remix.ADD_LINE, Remix.CLOSE_LINE, Remix.CHECK_LINE],
		[Remix.ARROW_RIGHT_LINE, Remix.MENU_LINE, Remix.FILTER_LINE, Remix.CALENDAR_LINE, Remix.TIME_LINE, Remix.MAP_PIN_LINE, Remix.CAMERA_LINE, Remix.LOCK_LINE]
	];

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var theme = ThemeState.get();
		for (scheme in [ColorScheme.Light, ColorScheme.Dark]) {
			theme.setScheme(scheme);
			var page = theme.color(Background);
			Snapshot.scene(scheme == Light ? "icons-light" : "icons-dark", 360, 200, gallery, page.rgb(), page.a, 2);
		}
	}

	static function gallery():Div {
		return hxx('
			<div class="flex flex-col items-center justify-center gap-5" width={360} height={200}>
				<for {row in rows}>
					<div class="flex flex-row gap-5">
						<for {icon in row}><icon document={icon} class="size-6 text-primary" /></for>
					</div>
				</for>
			</div>
		');
	}
}
