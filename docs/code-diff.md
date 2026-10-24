# Code diff

Import `CodeDiff` from `ashui.components` to show two versions of a text compared:
the lines that were removed and added in colour, the words that changed inside an
edited line marked, the line numbers of both texts in the gutter, and long runs of
unchanged lines folded into a row that opens when it is pressed. It is read-only.

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
| `language` | `plain` | The syntax colours, as `CodeEditor` takes it. |
| `highlighter` | none | An application grammar, as `CodeEditor` takes it. |
| `layout` | `inline` | `inline` for one column of removed and added lines, `split` for the original and the modified text side by side. A signal switches between them. |
| `context` | `3` | Unchanged lines kept on each side of a change. A longer run is folded into one row. A negative number keeps every line. |
| `hunks` | found | The changes, when you have them already. See below. |
| `lineNumbers` | `true` | The numbers in the gutter. |
| `navigation` | `false` | A bar above the rows with where the view is among the changes ("2 of 5") and buttons for the previous and the next. |
| `tabSize` | `4` | Spaces per tab stop. |
| `onStage`, `onRevert` | none | Setting either puts a Stage or a Revert button on the first row of each change, and calls it with the change when pressed. See [Stage and revert](#stage-and-revert). |
| `hunkActions` | none | More buttons of your own on those rows, after Stage and Revert. |
| `icons` | plain strokes | Icons for the diff's own controls: `{previous, next, folded, stage, revert}`. See [Icons](#icons). |
| `label`, `id` | none | The accessible name and the element id. |

## Layouts

Inline lists a change as its removed lines and then its added lines, with both
numbers in the gutter. Side by side lists the original in the left column and the
modified text in the right. Rows are all one height, so a line that has no partner
on the other side has a filler opposite it. The two columns scroll up and down
together, and each scrolls sideways on its own.

A removed line and an added line that are the same line edited share a row, and the
words that changed are marked on both. When a change has as many removed lines as
added lines, the first removed line is opposite the first added line, and so on.
When it has not, lines are matched by how alike they are, so a line inserted among
edited lines does not shift the lines that follow it. A line with too little in
common with its partner is shown whole, without word marks.

## Folding

Unchanged lines more than `context` away from a change are left out, and a row
says how many (`47 unchanged lines`). Pressing it shows them. `expandAll()` opens
every folded run and `collapseAll()` folds them again. Runs of fewer than three
lines are never folded, because the row would save too little.

## Navigation

Three methods move through the changes:

| Method | What it does |
| --- | --- |
| `nextChange()` | Scrolls to the next change, and from the last to the first. |
| `previousChange()` | Scrolls to the previous change, and from the first to the last. |
| `showChange(index)` | Scrolls to the change `index`, counted from 0; an index out of range is brought into it. |

`goToChange(delta)` is the general form of the first two. They count from the
current change when it is on screen, and from where the view is when it is not,
so scrolling past a change and then asking for the next goes to the one ahead.
`currentChange` is a signal holding the index of the change last gone to, and -1
before any; `changeCount` is a signal of how many there are.

`reveal(line)` scrolls to a line of the modified text, counted from 0, and opens
the folded run that hides it.

Set `navigation` for a bar that does it for the user: it says "3 changes", or
"2 of 3" once one has been gone to, and has a button for the previous change and
one for the next, each with a tooltip. F7 goes to the next change and Shift+F7
to the previous whenever a column of the diff has focus, with or without the bar.

```tsx
var diff = new Ref<CodeDiff>();

return <div class="flex-col gap-2">
    <code-diff ref={diff} original={before} modified={after} navigation={true} height={420} />
    <button onClick={_ -> diff.get().nextChange()}>Next change</button>
</div>;
```

## Changes you already have

Without `hunks` the component compares the texts itself. A comparison of a large
pair of texts (more than 4,000 lines between them) runs on the worker thread, and
the rows that were shown stay until it is done. The `comparing` signal is true in
the meantime.

When a version-control library gives you the changes, pass them as `hunks`: an
array of `{originalStart, originalLines, modifiedStart, modifiedLines}`, with lines
counted from 0. A change that only adds lines has `originalLines` of 0, and one
that only removes them has `modifiedLines` of 0. Pass the runs of removed and added
lines of a patch, not a hunk with its context lines: a context line given as part
of a change would be shown as changed. The component checks the changes against the
two texts, and ignores them if any line outside the changes differs.

`CodeDiffer.lines(original, modified)` makes the same changes from two arrays of
lines, and `CodeDiffer.words(a, b)` finds the changed words between two versions of
a line, so a program can use either without a view. They read no document and make
no element, so they can run on any thread.

## Stage and revert

The diff only shows changes; staging one or putting it back is the app's work, and the
buttons are only a way to ask for it. `onStage` and `onRevert` are hooks: give either a
function and a button appears on the first row of every change, at its right, while the
pointer is over the row, and for the current change (the one `nextChange` or F7 went
to) always, so the keyboard reaches them: F7, then Tab to a button, then Enter or Space.
A press calls the function with the
change, `{originalStart, originalLines, modifiedStart, modifiedLines}`, so the app can
turn it into a patch. The buttons are icons, and the label ("Stage change", "Revert
change") is their tooltip.

```tsx
<code-diff original={head} modified={working} height={420}
    onStage={change -> git.stage(file, change)}
    onRevert={change -> git.revert(file, change)} />
```

`hunkActions` adds buttons of your own after those: an array of `{label, ?icon, run}`. With
an `icon` the button shows only the icon and the `label` is its tooltip; without one it
shows the label. In a side-by-side layout the buttons are in the modified column.

```tsx
<code-diff original={head} modified={working} height={420}
    hunkActions={[{label: "Copy change", icon: Icons.COPY, run: change -> copy(change)}]} />
```

## Icons

The diff draws five icons of its own: the arrows of the navigation bar's two buttons, a mark at the
start of the row of a folded run, and the Stage and Revert buttons. It draws them as plain strokes, so the component needs no icon
set, and an app that wants its own gives them as `icons`. Each is an icon as the `icon` element takes
one: a document from an icon set, a compiled `SvgDocument`, or SVG markup in a string, drawn in
`currentColor` so it takes the text colour.

```tsx
import ashui.icons.Remix;

<code-diff original={before} modified={after} navigation={true}
    onStage={change -> stage(change)} onRevert={change -> revert(change)}
    icons={{
        previous: Remix.ARROW_UP_S_LINE, next: Remix.ARROW_DOWN_S_LINE, folded: Remix.EXPAND_UP_DOWN_LINE,
        stage: Remix.ADD_LINE, revert: Remix.ARROW_GO_BACK_LINE
    }} />
```

The buttons of `hunkActions` take their icons the same way, one to an action. The Remix set is in
`ashui-icons`, a separate package so that an app that does not use it does not carry its licence;
any other icons work the same.

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

A diff of tens of thousands of lines costs what it shows, not what it compares. Only the
rows in the viewport, and a few more either side, are elements, and they are reused as
you scroll. The lines are not made into a document: a line is coloured when a row first
shows it, and a bounded number of coloured lines are kept, so memory does not grow with
the length of the file, apart from the text itself. Folded runs of unchanged lines cost
nothing but their place in the file. Opening one, or `expandAll()`, colours lines as they
scroll into view, as the rest do.

A line longer than 2,000 characters is shown cut there, with an ellipsis, and has no word
marks. This keeps one minified line from costing what the rest of the file does.

## For maintainers

The rows are made by `ashui.components.code.CodeDiffRows` from the changes of
`CodeDiffer`, kept as integers, five to a row. A pane (`CodeDiffPane`) pools row
elements as the code editor does, so scrolling a line builds nothing. The lines of each
text are a `CodeDiffText`, which colours a line from the lexical state the line above ends
in: the line shown before it when there is one, otherwise a checkpoint kept every 256 lines,
filled a slice a frame for a large text.

The rows are not the code editor's panes with a filler element between lines, as VS Code
builds its diff editor, because every row here is one height; that is why this view needed
no zone widgets in `CodeEditor`, and why an editable modified side, which would, is not part
of it yet.
