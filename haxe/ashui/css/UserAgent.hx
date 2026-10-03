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
		input:focus-visible { outline: 2px solid var(--border-focus); outline-offset: 2px; }
		input:disabled { opacity: 0.5; }

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
