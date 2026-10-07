import ashui.components.Accordion;
import ashui.components.Alert;
import ashui.components.Avatar;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.ScrollArea;
import ashui.components.Separator;
import ashui.components.Skeleton;
import ashui.components.Spinner;
import ashui.components.Tabs;
import ashui.components.ToggleSwitch;
import ashui.core.render.Snapshot;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	The ashui.components library, section by section: buttons, badges in
	each appearance, cards, alerts, switches, tabs, accordions, and loading
	states. Dark by default; `SCHEME=light` renders the light scheme.
	`ACCORDION=1` records the accordion section in a compact, scrolled view.
	Use `tools/snapshot/run.sh --window` to play the same interactions live.
**/
class ComponentsGallery {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		var compact = Sys.getEnv("ACCORDION") != null;
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var on = Signal.make(true);
		var off = Signal.make(false);
		var off2 = Signal.make(false);
		var faq = Signal.make(["faq-1"]);
		ashui.css.Css.load('
			h2 { font-size: 20px; font-weight: 700; color: var(--text-primary); margin: 0 }
			label { font-size: 14px; font-weight: 500; color: var(--text-primary) }
			p { font-size: 13px; line-height: 1.4; color: var(--text-secondary); margin: 0 }
		');
		var build = () -> hxx('
			<div flexDirection={Column} padding={48} gap={48} width={compact ? 420 : 1400} height={3600} flexShrink={0}>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Buttons</h2>
					<div flexDirection={Row} gap={48} alignItems={Center}>
						<button>Primary</button>
						<button variant={Secondary}>Secondary</button>
						<button variant={Destructive}>Destructive</button>
						<button variant={Outline}>Outline</button>
						<button variant={Ghost}>Ghost</button>
						<button variant={Link}>Link</button>
					</div>
					<div flexDirection={Row} gap={48} alignItems={Center}>
						<button size={Sm}>Small</button>
						<button size={Md}>Medium</button>
						<button size={Lg}>Large</button>
						<button disabled={true}>Disabled</button>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Badges</h2>
					<div flexDirection={Row} gap={48} alignItems={Center}>
						<badge>In review</badge><badge variant={Warning}>Pending</badge><badge variant={Success}>Shipped</badge>
						<badge variant={Destructive}>Blocked</badge><badge variant={Secondary}>Draft</badge>
					</div>
					<div flexDirection={Row} gap={48} alignItems={Center}>
						<badge appearance={Solid}>Default</badge><badge appearance={Solid} variant={Secondary}>Secondary</badge><badge appearance={Solid} variant={Success}>Success</badge>
						<badge appearance={Solid} variant={Warning}>Warning</badge><badge appearance={Solid} variant={Destructive}>Destructive</badge>
					</div>
					<div flexDirection={Row} gap={48} alignItems={Center}>
						<badge appearance={Outline}>Default</badge><badge appearance={Outline} variant={Secondary}>Secondary</badge><badge appearance={Outline} variant={Success}>Success</badge>
						<badge appearance={Outline} variant={Warning}>Warning</badge><badge appearance={Outline} variant={Destructive}>Destructive</badge>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Cards</h2>
					<div flexDirection={Row} gap={64}>
						<card width={300}>
							<card-header><card-title>Card Title</card-title><card-description>Card description</card-description></card-header>
							<card-content><p>This is the card content. Cards are great for grouping related information.</p></card-content>
							<card-footer><button>Action</button></card-footer>
						</card>
						<card width={300}>
							<card-header><card-title>Simple Card</card-title></card-header>
							<card-content><p>A simpler card without footer.</p></card-content>
						</card>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Alerts</h2>
					<div flexDirection={Column} gap={48}>
						<alert><alert-description>This is a default informational alert.</alert-description></alert>
						<alert variant={Success}><alert-description>Operation completed successfully!</alert-description></alert>
						<alert variant={Warning}><alert-description>Please review before proceeding.</alert-description></alert>
						<alert variant={Destructive}><alert-description>An error occurred. Please try again.</alert-description></alert>
						<alert variant={Warning}><alert-title>Heads up!</alert-title><alert-description>This is an alert box with both title and description.</alert-description></alert>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Toggles</h2>
					<div flexDirection={Column} gap={24}>
						<div flexDirection={Row} gap={16} alignItems={Center}><toggle-switch checked={off} /><label>Notifications</label></div>
						<div flexDirection={Row} gap={12} alignItems={Center}><toggle-switch checked={on} /><label>Dark mode</label></div>
						<div flexDirection={Row} gap={12} alignItems={Center}><toggle-switch checked={off2} disabled={true} /><label>Disabled</label></div>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Tabs</h2>
					<div flexDirection={Column} gap={8} width={500} height={300}>
						<label>Simple Tabs</label>
						<tabs flexGrow={1}>
							<tabs-list><tabs-trigger value="account">Account</tabs-trigger><tabs-trigger value="password">Password</tabs-trigger><tabs-trigger value="notifications">Notifications</tabs-trigger></tabs-list>
							<tabs-content value="account"><div class="bg-surface-elevated px-2.5" flexGrow={1} flexDirection={Row} alignItems={Center}><p>Manage your account settings and preferences.</p></div></tabs-content>
							<tabs-content value="password"><p>Change your password and security settings.</p></tabs-content>
						</tabs>
					</div>
					<div flexDirection={Row} gap={96}>
						<div flexDirection={Column} gap={8}><label>Small Tabs</label>
							<tabs size={Sm}><tabs-list><tabs-trigger value="a">First</tabs-trigger><tabs-trigger value="b">Second</tabs-trigger></tabs-list></tabs></div>
						<div flexDirection={Column} gap={8}><label>Large Tabs</label>
							<tabs size={Lg}><tabs-list><tabs-trigger value="x">Overview</tabs-trigger><tabs-trigger value="y">Details</tabs-trigger></tabs-list></tabs></div>
					</div>
				</div>
				<div id="accordion-section" class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Accordion</h2>
					<div flexDirection={Column} gap={8}>
						<label>Single Open (default)</label>
						<accordion value={faq}>
							<accordion-item value="faq-1"><accordion-trigger id="faq-about">What is ashui?</accordion-trigger><accordion-content><p>ashui is a Haxe UI framework: fine-grained signals, CSS, and a GPU renderer.</p></accordion-content></accordion-item>
							<accordion-item value="faq-2"><accordion-trigger id="faq-motion">How do animations work?</accordion-trigger><accordion-content><p>Layout changes animate by FLIP; states and styles by CSS transitions on the theme motion tokens.</p></accordion-content></accordion-item>
							<accordion-item value="faq-3"><accordion-trigger>Is it production ready?</accordion-trigger><accordion-content><p>Under active development.</p></accordion-content></accordion-item>
						</accordion>
					</div>
					<div flexDirection={Column} gap={8}>
						<label>Multi Open</label>
						<accordion type="multiple">
							<accordion-item value="s1"><accordion-trigger id="multi-appearance">Appearance</accordion-trigger><accordion-content><p>Themes, colors and fonts.</p></accordion-content></accordion-item>
							<accordion-item value="s2"><accordion-trigger id="multi-notifications">Notifications</accordion-trigger><accordion-content><p>Email and push.</p></accordion-content></accordion-item>
							<accordion-item value="s3"><accordion-trigger>Privacy</accordion-trigger><accordion-content><p>Data sharing.</p></accordion-content></accordion-item>
						</accordion>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Loading States</h2>
					<div flexDirection={Row} gap={128} alignItems={Center}>
						<div flexDirection={Column} gap={32}><skeleton width={200} height={20} /><skeleton width={150} height={16} /><skeleton width={180} height={16} /></div>
						<skeleton width={48} height={48} class="rounded-full" />
						<div flexDirection={Row} gap={64} alignItems={Center}><spinner size={Sm} /><spinner /><spinner size={Lg} /></div>
						<div flexDirection={Row} gap={16} alignItems={Center} height={48}><avatar size="sm"><avatar-fallback>AL</avatar-fallback></avatar><avatar><avatar-fallback>CN</avatar-fallback></avatar><avatar size="lg"><avatar-fallback>GH</avatar-fallback></avatar><separator orientation="vertical" /></div>
					</div>
				</div>
			</div>
		');
		if (compact) {
			var capture = () -> <scroll-area id="gallery-scroll" width={420} height={760}>{build()}</scroll-area>;
			var result = MotionRecorder.record(light ? "components-accordion-light" : "components-accordion", 420, 760, capture, {
				fps: 60, frames: 300, minFrames: 295, settle: 1.0, scale: 2.0,
				clear: page.rgb(), overlay: false,
				before: (frame, tree, root) -> {
					function find(id:String):ashui.layout.Node {
						for (node in tree.order()) {
							var identity = ashui.css.Identity.of(tree, node);
							if (identity != null && identity.id == id) return new ashui.layout.Node(node);
						}
						throw 'no element #$id';
					}
					var scroll = ashui.input.Scroll.at(find("gallery-scroll").id);
					function click(id:String) {
						var bounds = tree.getBounds(find(id));
						ashui.input.Pointer.move(tree, bounds.x + bounds.width / 2, bounds.y + bounds.height / 2 - scroll.y.get());
						ashui.input.Pointer.press(tree);
						ashui.input.Pointer.release(tree);
					}
					switch frame {
						case 0:
							var bounds = tree.getBounds(find("accordion-section"));
							scroll.scrollTo(0, bounds.y - 24);
						case 30: click("faq-motion");
						case 90: click("multi-appearance");
						case 130: click("multi-notifications");
						case 175: click("multi-appearance");
						case 215: click("faq-about");
						case 260: click("multi-notifications");
						case _:
					}
					#if ashui_window
					if (frame == 20 && ashui.debug.SceneWindow.wanted()) {
						var app = ashui.app.WindowedApp.current;
						var name = light ? "components-accordion-window-light" : "components-accordion-window";
						sys.io.File.saveBytes(haxe.io.Path.join([Snapshot.dir(), name + ".png"]),
							MotionRecorder.capture(app.offscreen, tree, root, 420, 760, 2.0));
					}
					#end
				}
			});
			Sys.println(result.report.split("\n")[0]);
		} else
			Snapshot.scene(light ? "components-light" : "components", 1400, 3600, build, page.rgb(), page.a, 2.0, 1.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
