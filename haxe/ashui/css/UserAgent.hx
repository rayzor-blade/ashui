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
	';
}
