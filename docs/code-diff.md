# Code diff

Import `CodeDiff` from `ashui.components` to compare two versions of a text.
The read-only view highlights added and removed lines, marks changed words,
and shows both line numbers. Long unchanged sections collapse into rows
that expand when clicked.

```tsx
import ashui.components.CodeDiff;
import ashui.reactive.Reactive;

var before = signal(File.getContent("Counter.hx.orig"));
var after = signal(File.getContent("Counter.hx"));

return <code-diff original={before} modified={after} language="haxe"
    layout="split" label="Counter.hx" height={420} />;
```

Use the standard [components setup](https://github.com/rayzor-blade/ashui/blob/main/components/README.md#setup),
including `--macro ashui.ui.Markup.enable()` in `build.hxml`.

## Props

| Prop | Default | Purpose |
| --- | --- | --- |
| `original`, `modified` | required | The two texts, as strings or signals of strings. Use LF line endings. |
| `language` | `plain` | Syntax language, using the same values as `CodeEditor`. |
| `highlighter` | none | A custom syntax highlighter, using the same interface as `CodeEditor`. |
| `layout` | `inline` | `inline` for one column of removed and added lines, `split` for the original and the modified text side by side. A signal switches between them. |
| `context` | `3` | Unchanged lines kept on each side of a change. A longer run is folded into one row. A negative number keeps every line. |
| `hunks` | found | The changes, when you have them already. See below. |
| `lineHints` | none | Reactive inline annotations on changed lines: `{side:"original" or "modified", line:0-based, text, ?detail}`. |
| `lineNumbers` | `true` | The numbers in the gutter. |
| `navigation` | `false` | A toolbar with the current change position ("2 of 5") and previous/next buttons. |
| `tabSize` | `4` | Spaces per tab stop. |
| `onStage`, `onRevert` | none | Adds a Stage or Revert button to each change. Clicking it calls the supplied handler with that change. See [Stage and revert](#stage-and-revert). |
| `hunkActions` | none | Additional change actions, placed after Stage and Revert. |
| `icons` | plain strokes | Icons for the diff's own controls: `{previous, next, folded, stage, revert}`. See [Icons](#icons). |
| `label`, `id` | none | The accessible name and the element id. |

## Layouts

Inline layout shows removed lines followed by added lines, with both source
line numbers in the gutter. Split layout shows the original on the left and
the modified text on the right. Fixed-height filler rows keep unmatched lines
aligned. The columns scroll vertically together and horizontally independently.

Edited lines share a row, with changed words marked on both sides.
If a change removes and adds the same number of lines, rows are paired in order.
Otherwise, similarity matching keeps inserted lines from shifting later pairs.
Lines with too little similarity show no word-level marks.

## Inline annotations

Supply `lineHints` for short labels after changed code lines, such as an author name:

```tsx
var hints = signal(([{side: "modified", line: 4, text: "Ada", detail: "Edited in this session"}]
    : Array<ashui.components.code.CodeDiffHint>));
return <code-diff original={before} modified={after} lineHints={hints} />;
```

Hint line numbers are zero-based in each source, independent of layout.
Context and filler rows do not show hints. Updating the signal replaces the
labels, and only visible rows mount them. Long labels truncate; their tooltip
shows `detail`, or the full label when no detail is supplied. The component
does not fetch authors or interpret revision metadata.

## Folding

Unchanged sections beyond the `context` range collapse into a row such as
`47 unchanged lines`. Click the row to expand it. `expandAll()` opens every
section; `collapseAll()` folds them again. Runs shorter than three lines
stay visible because folding would save too little space.

## Navigation

Three methods move through the changes:

| Method | What it does |
| --- | --- |
| `nextChange()` | Scrolls to the next change, and from the last to the first. |
| `previousChange()` | Scrolls to the previous change, and from the first to the last. |
| `showChange(index)` | Scrolls to a zero-based change index, clamped to the valid range. |

`goToChange(delta)` provides relative navigation. If the current change is
visible, navigation starts there. Otherwise it starts at the viewport,
so scrolling past a change and requesting the next moves forward.
`currentChange` holds the last navigated index, or -1 initially.
`changeCount` holds the total number of changes. Both are signals.

`reveal(line)` scrolls to a line of the modified text, counted from 0, and opens
the folded run that hides it.

Set `navigation` to show a toolbar with previous/next buttons and tooltips.
It displays the change count, then the current position once you navigate,
such as "2 of 3". F7 moves to the next change; Shift+F7 moves to the previous.
These shortcuts work whenever a diff column has focus, even without the toolbar.

```tsx
var diff = new Ref<CodeDiff>();

return <div class="flex-col gap-2">
    <code-diff ref={diff} original={before} modified={after} navigation={true} height={420} />
    <button onClick={_ -> diff.get().nextChange()}>Next change</button>
</div>;
```

## Changes you already have

Without `hunks`, the component compares the texts itself. Comparisons totaling
more than 4,000 lines run on a worker thread. The previous result stays visible
until completion, and `comparing` is true while the comparison runs.

Pass precomputed changes through `hunks` as
`{originalStart, originalLines, modifiedStart, modifiedLines}` records.
Line numbers are zero-based. Insertions have `originalLines=0`; deletions
have `modifiedLines=0`.

Include only changed lines, excluding patch context. Context included in a
change would be highlighted as changed. The component validates the supplied
changes against both texts and ignores them if any line outside the ranges differs.

`CodeDiffer.lines(original, modified)` compares arrays of lines.
`CodeDiffer.words(a, b)` finds changed words within a line.
Neither API requires a document or UI element, so both can run on any thread.

## Stage and revert

The application owns staging and reverting. Supply `onStage` or `onRevert`
to add an icon button on the first row of each change. Clicking a button
passes `{originalStart, originalLines, modifiedStart, modifiedLines}` to
its callback so the application can create a patch.

Actions appear on hover and remain visible for the current navigated change.
Keyboard users can press F7, Tab to an action, then Enter or Space.
Button tooltips are "Stage change" and "Revert change".

```tsx
<code-diff original={head} modified={working} height={420}
    onStage={change -> git.stage(file, change)}
    onRevert={change -> git.revert(file, change)} />
```

`hunkActions` adds actions after Stage and Revert. Each entry is
`{label, ?icon, run}`. With an icon, the label becomes a tooltip;
otherwise it appears as button text. In split layout, actions appear in
the modified column.

```tsx
<code-diff original={head} modified={working} height={420}
    hunkActions={[{label: "Copy change", icon: Icons.COPY, run: change -> copy(change)}]} />
```

## Icons

The diff supplies five stroke icons: previous, next, folded, stage and revert.
Override them through `icons`. Each value accepts the same input as `<icon>`:
an icon-set document, a compiled `SvgDocument`, or SVG markup.
Use `currentColor` to inherit the text color.

```tsx
import ashui.icons.Remix;

<code-diff original={before} modified={after} navigation={true}
    onStage={change -> stage(change)} onRevert={change -> revert(change)}
    icons={{
        previous: Remix.ARROW_UP_S_LINE, next: Remix.ARROW_DOWN_S_LINE, folded: Remix.EXPAND_UP_DOWN_LINE,
        stage: Remix.ADD_LINE, revert: Remix.ARROW_GO_BACK_LINE
    }} />
```

Each `hunkActions` entry accepts an icon in the same way.
Remix is distributed separately in `ashui-icons`, so applications only include
that package and its license when needed. Other SVG icon sets also work.

## Styling

The colours come from the theme's success and error tokens. Customize them with:

| Custom property | What it colours |
| --- | --- |
| `--ui-diff-added-bg`, `--ui-diff-removed-bg` | The background of an added or removed line. |
| `--ui-diff-added-word-bg`, `--ui-diff-removed-word-bg` | The words that changed inside a line. |
| `--ui-diff-added-gutter`, `--ui-diff-removed-gutter` | The gutter beside an added or removed line. |
| `--ui-diff-filler-bg` | A filler opposite a line the other side lacks. |
| `--ui-diff-placeholder-bg`, `--ui-diff-placeholder-bg-hover` | The row of folded lines. |
| `--ui-diff-action-bg` | A hunk action button. |

The navigation bar takes the gutter's background (`--ui-code-gutter-bg`) and the code border.

The syntax colours, font and gutter use the same custom properties as the code editor
(`--ui-code-keyword`, `--ui-code-font`, `--ui-code-gutter-bg` and the others listed
in [Code view and editor](code-editor.md#styling)). The parts to style are
`.ui-code-diff`, `.ui-code-diff-row[data-kind="added"]`, `.ui-code-diff-word`,
`.ui-code-diff-gutter` and `.ui-code-diff-fold`.

## Large files

Only viewport rows and a small overscan are mounted. Rows are reused during
scrolling. Syntax highlighting runs when a line first becomes visible and
uses a bounded cache, so rendering memory stays bounded apart from the source
text itself. Folded sections store only their positions. Expanding a section
highlights its lines as they scroll into view.

Lines longer than 2,000 characters are truncated with an ellipsis and skip
word-level marks. This bounds the cost of minified or generated lines.

## For maintainers

`CodeDiffRows` builds rows from `CodeDiffer` changes, using five integers per row.
`CodeDiffPane` pools row elements, so scrolling one line creates no new rows.
Each `CodeDiffText` highlights lines using the previous line's lexical state
or a checkpoint stored every 256 lines. Large texts build checkpoints in
per-frame slices.

Diff rows have a fixed height and do not use `CodeEditor` panes or zone widgets.
An editable modified column would need a different layout and is not supported yet.
