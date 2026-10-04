import ashui.components.Alert;
import ashui.components.Avatar;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Separator;
import ashui.components.Skeleton;
import ashui.components.Spinner;
import ashui.components.Tabs;
import ashui.components.ToggleSwitch;
import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	The ashui.components library in its own looks: buttons of each variant
	and size, badges, a card with its parts, alerts, a separator, avatars,
	skeletons, a spinner, switches and tabs.
**/
class ComponentsGallery {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var on = Signal.make(true);
		var off = Signal.make(false);
		var build = () -> hxx('
			<div flexDirection={Column} padding={24} gap={18} width={720} height={640}>
				<div flexDirection={Row} gap={8} alignItems={Center}>
					<button>Primary</button>
					<button variant={Secondary}>Secondary</button>
					<button variant={Destructive}>Delete</button>
					<button variant={Outline}>Outline</button>
					<button variant={Ghost}>Ghost</button>
					<button variant={Link}>Link</button>
				</div>
				<div flexDirection={Row} gap={8} alignItems={Center}>
					<button size={Sm}>Small</button>
					<button size={Lg}>Large</button>
					<button disabled={true}>Disabled</button>
					<badge>New</badge><badge variant={Secondary}>Draft</badge><badge variant={Success}>Paid</badge>
					<badge variant={Warning}>Due</badge><badge variant={Destructive}>Late</badge><badge variant={Outline}>Archived</badge>
				</div>
				<div flexDirection={Row} gap={18} alignItems={Start}>
					<card width={300}>
						<card-header>
							<card-title>Create project</card-title>
							<card-description>Deploy your new project in one click.</card-description>
						</card-header>
						<card-content><div height={36} /></card-content>
						<card-footer><button variant={Outline}>Cancel</button><button>Deploy</button></card-footer>
					</card>
					<div flexDirection={Column} gap={10} width={360}>
						<alert><alert-title>Heads up</alert-title><alert-description>You can add components to your app.</alert-description></alert>
						<alert variant={Destructive}><alert-title>Error</alert-title><alert-description>Your session has expired.</alert-description></alert>
						<separator />
						<div flexDirection={Row} gap={10} alignItems={Center} height={40}>
							<avatar size="sm"><avatar-fallback>AL</avatar-fallback></avatar>
							<avatar><avatar-fallback>CN</avatar-fallback></avatar>
							<avatar size="lg"><avatar-fallback>GH</avatar-fallback></avatar>
							<separator orientation="vertical" />
							<spinner />
							<toggle-switch checked={on} />
							<toggle-switch checked={off} />
						</div>
						<div flexDirection={Row} gap={10} alignItems={Center}>
							<skeleton width={40} height={40} />
							<div flexDirection={Column} gap={6}><skeleton width={180} height={12} /><skeleton width={120} height={12} /></div>
						</div>
					</div>
				</div>
				<tabs>
					<tabs-list><tabs-trigger value="account">Account</tabs-trigger><tabs-trigger value="password">Password</tabs-trigger><tabs-trigger value="team">Team</tabs-trigger></tabs-list>
					<tabs-content value="account"><p>Make changes to your account here.</p></tabs-content>
					<tabs-content value="password"><p>Change your password here.</p></tabs-content>
				</tabs>
			</div>
		');
		Snapshot.scene("components@2x", 720, 640, build, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
