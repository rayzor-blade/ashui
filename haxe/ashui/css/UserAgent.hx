package ashui.css;

/**
	The user-agent stylesheet: built-in elements' default looks, as a
	browser's own stylesheet gives HTML elements theirs. It is in force under
	every other sheet, so a page's CSS, an element's Tw classes, its `style=`
	and its attributes all win over it. `Css.useUserAgent` puts it in force;
	the first built-in element does.

	Everything it uses is a theme token, read through the theme's CSS
	variables: colours, radii (which the theme's squircle smooths), shadows
	and motion. Every change an interactive element shows eases over the
	theme's durations and curves rather than jumping:

	- colour and border changes on hover and press: `--duration-fast`,
	  `--ease-state`;
	- a focus ring grows out from the element, a small gap from its
	  border: an outline of no width in `--focus-ring`, 2px out, widens
	  over `--duration-fast`, `--ease-out`;
	- a press shrinks a control a little, over `--duration-faster`;
	- a check mark or a radio's dot scales in with `--ease-spring`;
	- a dialog grows in from nothing and shrinks away on `--ease-sheet`, as
	  Blinc's dialogs do, its backdrop fading; a select's list scales in.
	  The top layer marks what is closing `[closing]` and keeps it for
	  `--duration-faster` while it goes.
**/
class UserAgent {
	/** Colours and borders easing between states. **/
	static inline var STATE = "var(--duration-fast) var(--ease-state)";

	/** A focus ring growing out. **/
	static inline var RING = "var(--duration-fast) var(--ease-out)";

	/** A press, quicker than a hover. **/
	static inline var PRESS = "var(--duration-faster) var(--ease-state)";

	/** A mark appearing, with a little overshoot. **/
	static inline var POP = "var(--duration-fast) var(--ease-spring)";

	/** An overlay opening, and going. **/
	static inline var ENTER = "var(--duration-fast) var(--ease-sheet)";
	static inline var EXIT = "var(--duration-faster) var(--ease-sheet) forwards";

	public static final CSS = '
		/* Text. Sizes are the browser defaults, in em of the text around. Elements that hold a flow of text are no wider than what holds them, so it wraps there. */
		p, h1, h2, h3, h4, h5, h6, dt, dd, caption, legend, figcaption { max-width: 100%; min-width: 0; }
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
			padding: 1px 4px; border-radius: var(--radius-sm); background: var(--surface-elevated);
		}
		kbd { border: 1px solid var(--border); }
		mark { background: var(--warning-bg); color: var(--text-primary); }
		output { flex-direction: row; flex-wrap: wrap; align-items: baseline; color: var(--text-primary); }

		/* Preformatted text and quotations. */
		pre {
			flex-direction: column; margin: 1em 0; padding: 10px 12px; border-radius: var(--radius-default);
			font-family: var(--font-mono); font-size: 0.9em; line-height: 1.5;
			background: var(--surface-elevated); color: var(--text-primary); overflow: auto;
		}
		pre > code { padding: 0; background: transparent; font-size: 1em; }
		blockquote {
			flex-direction: column; margin: 1em 0; padding: 2px 0 2px 14px;
			border-left: 3px solid var(--border); color: var(--text-secondary);
		}
		blockquote > p { margin: 0.25em 0; color: var(--text-secondary); }
		figure { flex-direction: column; gap: 6px; margin: 1em 0; }
		figcaption { flex-direction: row; flex-wrap: wrap; align-items: baseline; font-size: 0.9em; color: var(--text-secondary); }

		/* Lists: each item its marker, then its content; a list inside an item sits under the text of the item. */
		ul, ol { flex-direction: column; gap: 2px; margin: 1em 0; color: var(--text-primary); }
		li ul, li ol { margin: 2px 0 0 0; }
		/*
			The marker is a line of the item text tall, its bullet centred on that line and set down a little, from the middle
			of the line to the middle of the lowercase letters, sized with the text.
		*/
		li { flex-direction: row; align-items: flex-start; }
		li > .marker { flex-shrink: 0; width: 32px; padding-right: 8px; align-items: center; justify-content: flex-end; color: var(--text-secondary); }
		li > .marker > .bullet { display: none; flex-shrink: 0; width: 0.35em; height: 0.35em; margin-top: 0.2em; }
		li > .marker.disc > .bullet { display: flex; border-radius: var(--radius-full); background: var(--text-secondary); }
		li > .marker.circle > .bullet { display: flex; border-radius: var(--radius-full); border: 1.5px solid var(--text-secondary); }
		li > .marker.square > .bullet { display: flex; width: 0.3em; height: 0.3em; background: var(--text-secondary); }
		li > .content { flex-grow: 1; min-width: 0; flex-direction: row; flex-wrap: wrap; align-items: baseline; }
		dl { flex-direction: column; margin: 1em 0; color: var(--text-primary); }
		dt { flex-direction: row; flex-wrap: wrap; align-items: baseline; font-weight: 600; }
		dd { flex-direction: row; flex-wrap: wrap; align-items: baseline; margin: 0 0 6px 24px; color: var(--text-secondary); }

		/* Tables: every row a grid of the columns of the table, so cells line up. */
		table { flex-direction: column; border: 1px solid var(--border); border-radius: var(--radius-default); overflow: hidden; color: var(--text-primary); }
		caption { flex-direction: row; padding: 8px 12px; font-weight: 600; border-bottom: 1px solid var(--border); }
		thead, tbody, tfoot { flex-direction: column; }
		thead { background: var(--surface-elevated); }
		tfoot { background: var(--surface-elevated); }
		tr { display: grid; }
		tr + tr, thead + tbody, tbody + tbody, tbody + tfoot, thead + tfoot { border-top: 1px solid var(--border); }
		th, td { flex-direction: row; flex-wrap: wrap; align-items: baseline; min-width: 0; padding: 8px 12px; }
		th { font-weight: 600; }
		col, colgroup { display: none; }

		/* Focus rings: an outline of no width at rest, a small gap out from the border, growing out to show focus. */
		a, button, input, textarea, select, summary { outline: 0 solid var(--focus-ring); outline-offset: 2px; }
		a:focus-visible, button:focus-visible, summary:focus-visible, select:focus-visible,
		input:is([type="checkbox"], [type="radio"], [type="range"]):focus-visible { outline-width: 3px; }

		/* Links. */
		a {
			flex-direction: row; flex-wrap: wrap; align-items: baseline; color: var(--text-link); border-radius: var(--radius-sm);
			transition: opacity ${STATE}, outline-width ${RING};
		}
		a:hover { opacity: 0.8; }
		a:active { opacity: 0.65; }

		/* A thematic break: a rule across what holds it. */
		hr { height: 1px; flex-shrink: 0; align-self: stretch; margin: 8px 0; background: var(--border); }

		/* Buttons: a press shrinks them a little. */
		button {
			flex-direction: row; align-items: center; justify-content: center; gap: 6px;
			padding: 6px 14px; border-radius: var(--radius-default); background: var(--primary); color: var(--text-inverse);
			font-weight: 500;
			transition: background ${STATE}, opacity ${STATE}, transform ${PRESS}, outline-width ${RING};
		}
		button:hover { background: var(--primary-hover); }
		button:active { background: var(--primary-active); transform: scale(0.97); }
		button:disabled { opacity: 0.5; transform: none; }

		/* Checkboxes and radios: a box, its mark scaling in while it is checked. */
		input[type="checkbox"], input[type="radio"] {
			width: 18px; height: 18px; flex-shrink: 0; align-items: center; justify-content: center;
			border: 2px solid var(--border); background: var(--input-bg);
			transition: background ${STATE}, border-color ${STATE}, transform ${PRESS}, outline-width ${RING};
		}
		input[type="checkbox"] { border-radius: var(--radius-sm); color: var(--text-inverse); }
		input[type="radio"] { border-radius: var(--radius-full); }
		input[type="checkbox"]:hover, input[type="radio"]:hover { border-color: var(--border-hover); }
		input[type="checkbox"]:active, input[type="radio"]:active { transform: scale(0.92); }
		input[type="checkbox"]:checked, input[type="checkbox"]:indeterminate { background: var(--primary); border-color: var(--primary); }
		input[type="checkbox"]:checked:hover, input[type="checkbox"]:indeterminate:hover { background: var(--primary-hover); border-color: var(--primary-hover); }
		input[type="radio"]:checked { border-color: var(--primary); }
		input[type="checkbox"] > svg {
			/* Both marks in the same place, centred in the box whatever its size. */
			position: absolute; top: 0; right: 0; bottom: 0; left: 0; margin: auto; opacity: 0; transform: scale(0.4);
			transition: opacity ${STATE}, transform ${POP};
		}
		input[type="checkbox"]:checked:not(:indeterminate) > .check, input[type="checkbox"]:indeterminate > .dash { opacity: 1; transform: scale(1); }
		input[type="radio"] > .dot {
			width: 8px; height: 8px; border-radius: var(--radius-full); background: var(--primary); transform: scale(0);
			transition: transform ${POP};
		}
		input[type="radio"]:checked > .dot { transform: scale(1); }
		input:is([type="checkbox"], [type="radio"], [type="range"]):disabled { opacity: 0.5; transform: none; }

		/* Text fields, numbers and text areas: a bordered box the text is edited in; focus grows a ring out from it. */
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]), textarea {
			border: 2px solid var(--border); border-radius: var(--radius-default); background: var(--input-bg); color: var(--text-primary);
			transition: background ${STATE}, border-color ${STATE}, outline-width ${RING};
		}
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]) {
			flex-direction: row; align-items: center; width: 240px; height: 38px; padding: 0 10px;
		}
		textarea { flex-direction: column; }
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):hover, textarea:hover {
			border-color: var(--border-hover);
		}
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):focus, textarea:focus {
			background: var(--input-bg-focus); border-color: var(--border-focus); outline-width: 3px;
		}
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):disabled, textarea:disabled {
			background: var(--input-bg-disabled); border-color: var(--border);
		}
		input[type="number"] { width: 120px; padding-right: 2px; }
		input[type="number"] > .steppers { flex-direction: column; flex-shrink: 0; margin-left: 4px; }
		input[type="number"] > .steppers > div {
			width: 20px; height: 14px; align-items: center; justify-content: center; border-radius: var(--radius-sm); color: var(--text-secondary);
			transition: background ${STATE}, color ${STATE}, transform ${PRESS};
		}
		input[type="number"] > .steppers > div:hover { background: var(--accent-subtle); color: var(--text-primary); }
		input[type="number"] > .steppers > div:active { transform: scale(0.85); }

		/* Ranges: a track, filled up to the thumb, which grows under the pointer. */
		input[type="range"] {
			flex-direction: row; align-items: center; width: 160px; height: 20px; border-radius: var(--radius-full);
			transition: outline-width ${RING};
		}
		input[type="range"] > .fill, input[type="range"] > .rest { flex-basis: 0; min-width: 0; height: 4px; }
		input[type="range"] > .fill { border-radius: var(--radius-full) 0 0 var(--radius-full); background: var(--primary); }
		input[type="range"] > .rest { border-radius: 0 var(--radius-full) var(--radius-full) 0; background: var(--border); }
		input[type="range"] > .thumb {
			width: 16px; height: 16px; flex-shrink: 0; border-radius: var(--radius-full);
			background: var(--surface-elevated); border: 2px solid var(--primary); box-shadow: var(--shadow-sm);
			transition: transform ${STATE}, box-shadow ${STATE}, border-color ${STATE};
		}
		input[type="range"]:hover > .thumb { transform: scale(1.1); box-shadow: var(--shadow-md); border-color: var(--primary-hover); }
		input[type="range"]:active > .thumb { transform: scale(1.2); }

		/* Progress and meters: a track, filled to the value, easing to a new one. */
		progress, meter { flex-direction: row; width: 160px; height: 8px; border-radius: var(--radius-full); background: var(--border); overflow: hidden; }
		progress > .bar, meter > .bar {
			height: 100%; border-radius: var(--radius-full);
			transition: width var(--duration-normal) var(--ease-out), background ${STATE};
		}
		progress > .bar { background: var(--primary); }
		progress:indeterminate > .bar { width: 30%; animation: ashui-progress-pulse var(--duration-slowest) var(--ease-in-out) infinite alternate; }
		@keyframes ashui-progress-pulse { from { opacity: 0.35; } to { opacity: 1; } }
		meter > .optimum { background: var(--success); }
		meter > .suboptimum { background: var(--warning); }
		meter > .even-less-good { background: var(--error); }

		/* Fieldsets: a bordered group of controls, its legend first. */
		fieldset {
			flex-direction: column; gap: 8px; padding: 12px 14px; margin: 0;
			border: 1px solid var(--border); border-radius: var(--radius-default);
		}
		legend { flex-direction: row; align-items: baseline; padding: 0 2px; font-weight: 600; color: var(--text-primary); }

		/* Forms, and controls the user has left invalid, in the error colours of the theme. */
		form { flex-direction: column; align-items: flex-start; }
		input:is([type="text"], [type="password"], [type="search"], [type="email"], [type="tel"], [type="url"], [type="number"]):user-invalid,
		input:is([type="checkbox"], [type="radio"]):user-invalid {
			border-color: var(--border-error); outline-color: var(--focus-ring-error);
		}

		/* Labels: their text beside their control. */
		label { flex-direction: row; align-items: center; gap: 8px; color: var(--text-primary); }

		/* The top layer: the backdrop under what it holds fades in, and out as it closes. */
		backdrop { animation: ashui-fade-in ${ENTER}; }
		backdrop[closing] { animation: ashui-fade-out ${EXIT}; }
		@keyframes ashui-fade-in { from { opacity: 0; } to { opacity: 1; } }
		@keyframes ashui-fade-out { from { opacity: 1; } to { opacity: 0; } }

		/* Selects: the control, its list of options in the top layer, the options and their group headings. */
		select {
			flex-direction: row; align-items: center; justify-content: space-between; gap: 8px; min-width: 120px;
			padding: 6px 10px; border: 1px solid var(--border); border-radius: var(--radius-default); background: var(--input-bg); color: var(--text-primary);
			transition: background ${STATE}, border-color ${STATE}, transform ${PRESS}, outline-width ${RING};
		}
		select:hover { border-color: var(--border-hover); }
		select:active { transform: scale(0.98); }
		select[open] { border-color: var(--border-focus); }
		select:disabled { opacity: 0.5; transform: none; }
		select > .chevron { color: var(--text-secondary); transition: transform var(--duration-normal) var(--ease-state); }
		select[data-placeholder] { color: var(--text-tertiary); }
		select[open] > .chevron { transform: rotate(180deg); }
		listbox {
			flex-direction: column; padding: 4px; border: 1px solid var(--border); border-radius: var(--radius-default);
			background: var(--surface-elevated); box-shadow: var(--shadow-lg);
			animation: ashui-list-in ${ENTER};
		}
		listbox[closing] { animation: ashui-list-out ${EXIT}; }
		@keyframes ashui-list-in { from { opacity: 0; transform: translateY(-4px) scale(0.96); } to { opacity: 1; transform: none; } }
		@keyframes ashui-list-out { from { opacity: 1; transform: none; } to { opacity: 0; transform: translateY(-4px) scale(0.96); } }
		option {
			flex-direction: row; align-items: center; padding: 6px 10px; border-radius: var(--radius-md); color: var(--text-primary);
			transition: background ${STATE};
		}
		option:hover, option:focus { background: var(--accent-subtle); }
		option:checked { font-weight: 600; }
		option:disabled { opacity: 0.5; }
		optgroup { padding: 6px 10px 2px 10px; font-size: 0.8em; font-weight: 600; color: var(--text-secondary); }

		/* Dialogs: a panel, centred over a dimmed backdrop when modal, growing in from nothing and shrinking away. */
		dialog {
			flex-direction: column; gap: 12px; padding: 20px; min-width: 280px; border-radius: var(--radius-xl);
			background: var(--surface-elevated); color: var(--text-primary); box-shadow: var(--shadow-2xl);
		}
		dialog[open] { animation: ashui-grow-in ${ENTER}; }
		dialog[closing] { animation: ashui-shrink-out ${EXIT}; }
		dialog:not([open]):not([closing]) { display: none; }
		@keyframes ashui-grow-in { from { opacity: 0; transform: scale(0); } to { opacity: 1; transform: scale(1); } }
		@keyframes ashui-shrink-out { from { opacity: 1; transform: scale(1); } to { opacity: 0; transform: scale(0); } }

		/* Details: a summary that opens and closes the rest, its marker turning. */
		details { flex-direction: column; gap: 6px; }
		summary {
			flex-direction: row; align-items: center; gap: 6px; color: var(--text-primary); font-weight: 500; border-radius: var(--radius-sm);
			transition: opacity ${STATE}, outline-width ${RING};
		}
		summary:hover { opacity: 0.8; }
		summary > .marker { color: var(--text-secondary); transition: transform var(--duration-normal) var(--ease-state); }
		details[open] > summary > .marker { transform: rotate(90deg); }
		details:not([open]) > .content { display: none; }
		details > .content { flex-direction: column; gap: 6px; padding-left: 18px; animation: ashui-list-in ${ENTER}; }
	';
}
