package ashui.css;

/**
	The user-agent stylesheet: built-in elements' default looks, as a
	browser's own stylesheet gives HTML elements theirs, themed through the
	theme's CSS variables. It is in force under every other sheet, so a
	page's CSS, an element's Tw classes, its `style=` and its attributes all
	win over it. `Css.useUserAgent` puts it in force; the first built-in
	element does.
**/
class UserAgent {
	public static final CSS = '
		/* Text. Sizes are the browser defaults, in em of the text around. */
		h1, h2, h3, h4, h5, h6 { font-weight: 700; color: var(--text-primary); flex-direction: row; flex-wrap: wrap; align-items: baseline; }
		h1 { font-size: 2em; margin: 0.67em 0; }
		h2 { font-size: 1.5em; margin: 0.83em 0; }
		h3 { font-size: 1.17em; margin: 1em 0; }
		h4 { font-size: 1em; margin: 1.33em 0; }
		h5 { font-size: 0.83em; margin: 1.67em 0; }
		h6 { font-size: 0.67em; margin: 2.33em 0; }
		p { margin: 1em 0; line-height: 1.5; color: var(--text-primary); flex-direction: row; flex-wrap: wrap; align-items: baseline; }
		span, strong, b, em, i, small, code, kbd, mark, s, u { flex-direction: row; flex-wrap: wrap; align-items: baseline; }
		strong, b { font-weight: 700; }
		em, i { font-style: italic; }
		small { font-size: 0.83em; }
		code, kbd {
			font-family: var(--font-mono); font-size: 0.9em;
			padding: 1px 4px; border-radius: 4px; background: var(--surface-elevated);
		}
		kbd { border: 1px solid var(--border); }
		mark { background: rgba(250, 204, 21, 0.4); }
		output { flex-direction: row; flex-wrap: wrap; align-items: baseline; color: var(--text-primary); }

		/* Links. */
		a { flex-direction: row; flex-wrap: wrap; align-items: baseline; color: var(--text-link); }
		a:hover { opacity: 0.8; }
		a:focus-visible { outline: 2px solid var(--border-focus); outline-offset: 2px; border-radius: 2px; }

		/* A thematic break: a rule across what holds it. */
		hr { height: 1px; flex-shrink: 0; align-self: stretch; margin: 8px 0; background: var(--border); }

		/* Buttons. */
		button {
			flex-direction: row; align-items: center; justify-content: center; gap: 6px;
			padding: 6px 14px; border-radius: 8px; background: var(--primary); color: var(--text-inverse);
			font-weight: 500; transition: background 120ms ease-out;
		}
		button:hover { background: var(--primary-hover); }
		button:active { background: var(--primary-active); }
		button:focus-visible { outline: 2px solid var(--border-focus); outline-offset: 2px; }
		button:disabled { opacity: 0.5; }

		/* Checkboxes and radios: a box, its mark shown while it is checked. */
		input[type="checkbox"], input[type="radio"] {
			width: 18px; height: 18px; flex-shrink: 0; align-items: center; justify-content: center;
			border: 2px solid var(--border); background: var(--input-bg);
			transition: background 120ms ease-out, border-color 120ms ease-out;
		}
		input[type="checkbox"] { border-radius: 4px; color: var(--text-inverse); }
		input[type="radio"] { border-radius: 9999px; }
		input[type="checkbox"]:hover, input[type="radio"]:hover { border-color: var(--border-hover); }
		input[type="checkbox"]:checked, input[type="checkbox"]:indeterminate { background: var(--primary); border-color: var(--primary); }
		input[type="radio"]:checked { border-color: var(--primary); }
		input[type="checkbox"] > svg, input[type="radio"] > .dot { display: none; }
		input[type="checkbox"]:checked:not(:indeterminate) > .check, input[type="checkbox"]:indeterminate > .dash { display: flex; }
		input[type="radio"]:checked > .dot { display: flex; width: 8px; height: 8px; border-radius: 9999px; background: var(--primary); }
		input:is([type="checkbox"], [type="radio"], [type="range"]):focus-visible { outline: 2px solid var(--border-focus); outline-offset: 2px; }
		input:is([type="checkbox"], [type="radio"], [type="range"]):disabled { opacity: 0.5; }

		/* Text fields, numbers and text areas: a bordered box the text is edited in. */
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]), textarea {
			border: 2px solid var(--border); border-radius: 8px; background: var(--input-bg); color: var(--text-primary);
			transition: background 150ms ease-out, border-color 150ms ease-out;
		}
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]) {
			flex-direction: row; align-items: center; width: 240px; height: 38px; padding: 0 10px;
		}
		textarea { flex-direction: column; }
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):hover, textarea:hover {
			border-color: var(--border-hover);
		}
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):focus, textarea:focus {
			background: var(--input-bg-focus); border-color: var(--border-focus);
		}
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):disabled, textarea:disabled {
			background: var(--input-bg-disabled); border-color: var(--border);
		}
		input[type="number"] { width: 120px; padding-right: 2px; }
		input[type="number"] > .steppers { flex-direction: column; flex-shrink: 0; margin-left: 4px; }
		input[type="number"] > .steppers > div {
			width: 20px; height: 14px; align-items: center; justify-content: center; border-radius: 3px; color: var(--text-secondary);
		}
		input[type="number"] > .steppers > div:hover { background: var(--accent-subtle); color: var(--text-primary); }

		/* Ranges: a track, filled up to the thumb. */
		input[type="range"] { flex-direction: row; align-items: center; width: 160px; height: 20px; }
		input[type="range"] > .fill, input[type="range"] > .rest { flex-basis: 0; min-width: 0; height: 4px; }
		input[type="range"] > .fill { border-radius: 2px 0 0 2px; background: var(--primary); }
		input[type="range"] > .rest { border-radius: 0 2px 2px 0; background: var(--border); }
		input[type="range"] > .thumb {
			width: 16px; height: 16px; flex-shrink: 0; border-radius: 9999px;
			background: var(--surface-elevated); border: 2px solid var(--primary); box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
			transition: transform 120ms ease-out;
		}
		input[type="range"]:hover > .thumb { transform: scale(1.1); }

		/* Progress and meters: a track, filled to the value. */
		progress, meter { flex-direction: row; width: 160px; height: 8px; border-radius: 9999px; background: var(--border); overflow: hidden; }
		progress > .bar, meter > .bar { height: 100%; border-radius: 9999px; }
		progress > .bar { background: var(--primary); }
		progress:indeterminate > .bar { width: 30%; animation: ashui-progress-pulse 1.2s ease-in-out infinite alternate; }
		@keyframes ashui-progress-pulse { from { opacity: 0.35; } to { opacity: 1; } }
		meter > .optimum { background: var(--success); }
		meter > .suboptimum { background: var(--warning); }
		meter > .even-less-good { background: var(--error); }

		/* Fieldsets: a bordered group of controls, its legend first. */
		fieldset {
			flex-direction: column; gap: 8px; padding: 12px 14px; margin: 0;
			border: 1px solid var(--border); border-radius: 8px;
		}
		legend { flex-direction: row; align-items: baseline; padding: 0 2px; font-weight: 600; color: var(--text-primary); }

		/* Labels: their text beside their control. */
		label { flex-direction: row; align-items: center; gap: 8px; color: var(--text-primary); }

		/* Selects: the control, its list of options in the top layer, the options and their group headings. */
		select {
			flex-direction: row; align-items: center; justify-content: space-between; gap: 8px; min-width: 120px;
			padding: 6px 10px; border: 1px solid var(--border); border-radius: 8px; background: var(--input-bg); color: var(--text-primary);
		}
		select:hover { border-color: var(--border-hover); }
		select:focus-visible { outline: 2px solid var(--border-focus); outline-offset: 2px; }
		select:disabled { opacity: 0.5; }
		select > .chevron { color: var(--text-secondary); }
		listbox {
			flex-direction: column; padding: 4px; border: 1px solid var(--border); border-radius: 8px;
			background: var(--surface-elevated); box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
		}
		option { flex-direction: row; align-items: center; padding: 6px 10px; border-radius: 6px; color: var(--text-primary); }
		option:hover, option:focus { background: var(--accent-subtle); }
		option:checked { font-weight: 600; }
		option:disabled { opacity: 0.5; }
		optgroup { padding: 6px 10px 2px 10px; font-size: 0.8em; font-weight: 600; color: var(--text-secondary); }

		/* Dialogs: a panel, centred over a dimmed backdrop when modal. */
		dialog {
			flex-direction: column; gap: 12px; padding: 20px; min-width: 280px; border-radius: 12px;
			background: var(--surface-elevated); color: var(--text-primary); box-shadow: 0 16px 48px rgba(0, 0, 0, 0.25);
		}
		dialog:not([open]) { display: none; }

		/* Details: a summary that opens and closes the rest. */
		details { flex-direction: column; gap: 6px; }
		summary { flex-direction: row; align-items: center; gap: 6px; color: var(--text-primary); font-weight: 500; }
		summary:focus-visible { outline: 2px solid var(--border-focus); outline-offset: 2px; }
		summary > .marker { color: var(--text-secondary); transition: transform 150ms ease-out; }
		details[open] > summary > .marker { transform: rotate(90deg); }
		details:not([open]) > .content { display: none; }
		details > .content { flex-direction: column; gap: 6px; padding-left: 18px; }
	';
}
