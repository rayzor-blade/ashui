import ashui.components.Checkbox;
import ashui.components.Badge;
import ashui.components.Card;
import ashui.components.Combobox;
import ashui.components.Input;
import ashui.components.InputOtp;
import ashui.components.Label;
import ashui.components.NumberInput;
import ashui.components.Progress;
import ashui.components.RadioGroup;
import ashui.components.Select;
import ashui.components.Slider;
import ashui.components.Size;
import ashui.components.Textarea;
import ashui.components.ToggleSwitch;
import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	The library's form components, section by section: fields, checkboxes
	and switches, sliders, radio groups, selects and progress. Dark by
	default; `SCHEME=light` renders the light scheme. NumberInput's three
	sizes appear together (git-bug ffc482f).
**/
class FormsGallery {
	/** All density variants, aligned in columns, using existing controls (git-bug e8a1b50). **/
	static function sizes():ashui.layout.Element
		return <div class="bg-background flex-col p-6 gap-6" width={1280} height={1120}>
			<h2>Form controls · size variants</h2>
			<div class="flex-row gap-6 items-start">
				<for {size in [Size.Sm, Size.Md, Size.Lg]}>
					<card width={392}>
						<card-header><card-title>${size == Size.Sm ? "Small" : size == Size.Md ? "Medium · default" : "Large"}</card-title></card-header>
						<card-content class="flex-col gap-4">
							<div class="flex-col gap-2" height={72}><label>Name</label><input size={size} value="Alex Rivera" /></div>
							<div class="flex-col gap-2" height={72}><label>Password</label><input size={size} type="password" value="ashui-demo" revealable={true} /></div>
							<div class="flex-col gap-2" height={72}><label>Region</label><select size={size} value="eu"><select-item value="eu">Europe</select-item><select-item value="us">Americas</select-item></select></div>
							<div class="flex-col gap-2" height={72}><label>Search</label><combobox size={size} value="design" options={[{value: "design", label: "Design"}, {value: "engineering", label: "Engineering"}]} /></div>
							<div class="flex-col gap-2" height={176}><label>Notes</label><textarea size={size} value={Signal.make("The same controls, with typography and spacing that fit each size.")} /></div>
							<div class="flex-col gap-2" height={80}><label>Verification code</label><input-otp size={size} length={4} separator={2} value="1234" /></div>
							<div height={32} class="flex-row items-center"><checkbox size={size} checked={true}>Email updates</checkbox></div>
							<div height={88}><radio-group size={size} value="standard"><radio-group-item value="standard">Standard</radio-group-item><radio-group-item value="priority">Priority</radio-group-item></radio-group></div>
							<div height={64}><slider size={size} label="Volume" value={0.65} min={0} max={1} step={0.01} format={v -> Std.string(Math.round(v * 100)) + "%"} /></div>
							<div height={40} class="flex-row items-center gap-2"><badge size={size} variant={Success}>Active</badge><badge size={size} variant={Secondary}>4 items</badge></div>
						</card-content>
					</card>
				</for>
			</div>
		</div>;

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		ashui.css.Css.load('
			h2 { font-size: 20px; font-weight: 700; color: var(--text-primary); margin: 0 }
		');
		var size = Signal.make("medium");
		var color = Signal.make("blue");
		var fruit = Signal.make("");
		var dim = Signal.make("medium");
		var sizing = Sys.getEnv("SIZES") == "1";
		if (sizing)
			// SF Mono's unhinted CFF outlines overflow the native atlas on macOS (git-bug c2cfa79).
			// Keep the comparison readable using available TrueType monospace faces; component styles retain the theme token.
			ashui.css.Css.load('.ui-input-otp-slot { font-family: Menlo, Consolas, "Liberation Mono", monospace; }');
		var build = () -> sizing ? sizes() :
			<div flexDirection={Column} padding={48} gap={48} width={1400} height={1500}>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Form Inputs</h2>
					<div flexDirection={Row} gap={24} alignItems={Start}>
						<div flexDirection={Column} gap={12}>
							<div flexDirection={Column} gap={8}><label>Username</label><input placeholder="Enter username" /></div>
							<div flexDirection={Column} gap={8}><label required={true}>Email</label><input type="email" placeholder="you@example.com" /></div>
							<div flexDirection={Column} gap={8}><label>Password</label><input type="password" value="hunter22" revealable={true} /></div>
							<div flexDirection={Column} gap={8}><label>Password, shown</label><input type="password" value="hunter22" revealable={true} reveal={true} /></div>
						</div>
						<div flexDirection={Column} gap={12}>
							<div flexDirection={Column} gap={8}><label>Bio</label><textarea placeholder="Tell us about yourself..." /></div>
							<div flexDirection={Column} gap={8}><label>Quantity</label><number-input size={Lg} value={1.0} min={0} /></div>
							<div flexDirection={Column} gap={8}><label>Temperature</label><number-input size={Lg} value={22.5} step={0.5} /></div>
						</div>
						<div flexDirection={Column} gap={12}>
							<div flexDirection={Column} gap={8}><label>Small</label><number-input size={Sm} value={12.5} step={0.5} /></div>
							<div flexDirection={Column} gap={8}><label>Medium (default)</label><number-input value={12.5} step={0.5} /></div>
							<div flexDirection={Column} gap={8}><label>Large</label><number-input size={Lg} value={12.5} step={0.5} /></div>
						</div>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Toggles</h2>
					<div flexDirection={Row} gap={96} alignItems={Start}>
						<div flexDirection={Column} gap={24}>
							<checkbox>Accept terms</checkbox>
							<checkbox checked={true}>Checked by default</checkbox>
							<checkbox disabled={true}>Disabled</checkbox>
						</div>
						<div flexDirection={Column} gap={24}>
							<toggle-switch />
							<toggle-switch checked={true} />
							<toggle-switch disabled={true} />
						</div>
					</div>
				</div>
				<div flexDirection={Row} gap={48} alignItems={Start}>
					<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12" width={420}>
						<h2>Sliders</h2>
						<div flexDirection={Column} gap={24}>
							<slider label="Volume" value={0.5} min={0} max={1} step={0.01} />
							<slider label="Brightness" value={75.0} min={0} max={100} format={v -> Std.string(Math.round(v))} />
							<slider label="Disabled" value={0.3} min={0} max={1} disabled={true} format={_ -> ""} />
						</div>
					</div>
					<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12" width={420}>
						<h2>Radio Groups</h2>
						<div flexDirection={Row} gap={64} alignItems={Start}>
							<div flexDirection={Column} gap={16}><label>Select Size</label>
								<radio-group value={size}>
									<radio-group-item value="small">Small</radio-group-item>
									<radio-group-item value="medium">Medium</radio-group-item>
									<radio-group-item value="large">Large</radio-group-item>
								</radio-group></div>
							<div flexDirection={Column} gap={16}><label>Select Color</label>
								<radio-group value={color} orientation="horizontal">
									<radio-group-item value="red">Red</radio-group-item>
									<radio-group-item value="blue">Blue</radio-group-item>
								</radio-group></div>
						</div>
					</div>
					<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12" width={360}>
						<h2>Select</h2>
						<div flexDirection={Column} gap={8}><label>Favorite Fruit</label>
							<select value={fruit} placeholder="Choose a fruit...">
								<select-item value="apple">Apple</select-item><select-item value="banana">Banana</select-item>
							</select></div>
						<div flexDirection={Column} gap={8}><label>Size</label>
							<select value={dim}><select-item value="small">Small</select-item><select-item value="medium">Medium</select-item></select></div>
						<div flexDirection={Column} gap={8}><label>Disabled</label>
							<select value="o1" disabled={true}><select-item value="o1">Option 1</select-item></select></div>
					</div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-12">
					<h2>Progress</h2>
					<div flexDirection={Column} gap={20}>
						<progress value={25.0} max={100} />
						<progress value={50.0} max={100} size={Sm} />
						<progress value={75.0} max={100} size={Lg} />
					</div>
				</div>
			</div>;
		Snapshot.scene(sizing ? (light ? "form-sizes-light" : "form-sizes") : (light ? "forms-light" : "forms"),
			sizing ? 1280 : 1400, sizing ? 1120 : 1500, build, page.rgb(), page.a, 2.0, 0.5);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
