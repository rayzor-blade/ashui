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
	';
}
