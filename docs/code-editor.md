# Code view and editor

Import `CodeEditor` and `CodeView` from `ashui.components`. Both use the same
syntax colors, line-number gutter, folding and scrolling. `CodeView` allows
selection and copying; `CodeEditor` also edits the shared value.

```tsx
import ashui.components.CodeEditor;
import ashui.components.CodeView;
import ashui.reactive.Reactive;

var source = signal("class Hello {\n    static function main() {}\n}\n");

return <div class="flex-col gap-4">
    <code-editor value={source} language="haxe" height={360}
        label="Application source" indentGuides={true}
        onInput={text -> saveDraft(text)} />
    <code-view value={source} language="haxe" height={200}
        label="Source preview" />
</div>;
```

Use the standard [components setup](https://github.com/rayzor-blade/ashui/blob/main/components/README.md#setup),
including `--macro ashui.ui.Markup.enable()` in `build.hxml`.
The [CodeWorkbench demo](https://github.com/rayzor-blade/ashui/blob/main/tools/demo/CodeWorkbench.hx)
is a complete windowed example.

## Display options

| Prop | Default | Purpose |
| --- | --- | --- |
| `value` | `""` | A shared signal, initial string, or derived source. Use LF line endings. |
| `language` | `"plain"` | Reactive language name; unknown names use plain text. |
| `highlighter` | Built in | A custom `CodeHighlighter`, overriding `language`. |
| `lineNumbers` | `true` | Original source line numbers, including after folding. |
| `folding` | `true` | Gutter buttons for multiline `{…}` and `[…]` blocks. |
| `indentGuides` | `false` | Guides at each indentation level. |
| `highlightBrackets` | `true` | Highlight the matching `{}`, `[]` or `()` pair beside the caret. |
| `tabSize` | `4` | Spaces per tab stop, from 1 to 16. |
| `insertSpaces` | `true` | Insert spaces when indenting; `false` inserts tabs. |
| `readOnly` | `false` | Reactive edit lock; selection and copying remain available. |
| `disabled` | `false` | Reactive input and focus lock. |
| `label` | `"Code"` | Accessible name of the text surface. |
| `findShortcuts` | `true` | Handle built-in find/replace shortcuts; false lets an app bind the public methods. |

Use layout attributes or CSS for width and height. Height defaults to 320px.
Code stays unwrapped and scrolls in both directions; the gutter stays visible
when scrolling horizontally. Closing a fold keeps its opening line visible.
Nested folds keep their state. Folding does not alter the source.

Built-in lexical highlighters cover Haxe (`hxx`), JavaScript (`js`, `jsx`), TypeScript (`ts`, `tsx`),
Rust (`rs`), JSON, CSS, Python (`py`) and Lua. Multiline comments and strings
carry state between lines. Brackets inside those tokens do not create folds.
These highlighters provide lexical colors rather than semantic language analysis.
HXX/JSX markup keeps child text separate from host code. Tags, attributes,
quoted values and embedded expressions get distinct tokens, including across
lines; literal text such as `Add one` is not treated as a type name.

## Editing

The editor reuses Ashui's text editing engine: native grapheme positions,
pointer selection, double-click word selection, keyboard navigation,
clipboard and input-method composition. The caret follows the selection
into view. A focused read-only view has no blinking caret.
Click a brace or move the caret next to it to highlight its matching pair.
Braces in strings, comments and literal markup text are excluded.

- **Enter:** insert a newline with the current indentation; add one level
  after an opening brace, bracket or colon.
- **Tab / Shift+Tab:** indent or outdent the selected lines. Without a
  selection, Tab advances to the next tab stop.
- **Command+Z / Control+Z:** undo. Add Shift to redo; Control+Y also redoes.
- **Command+Enter / Control+Enter:** call `onSubmit` with the source.
- **Escape:** leave the editing surface. In a read-only view, Tab moves focus.

`onInput` fires for user edits, undo and redo. External signal updates replace
the source and clear undo history. History stores replacement patches,
bounded to 100 edits and 1 MiB, rather than copying the file for each edit.

A `Ref<CodeEditor>` exposes `focus()`, `select(anchor, caret)`, `undo()`,
`redo()`, `toggleFold(line)` and `expandAll()`. Selection offsets are Haxe
string indices; fold line numbers are **zero based**. `select` reveals folded
ancestors. `value`, `editing`, `document`, `metrics` and `scroll` are available
for custom toolbars and status displays.

Only viewport rows and a small overscan are mounted, capped at the number of
visible document lines. Shrinking or folding the source clamps the scroll offset
to the remaining content. Highlighting reuses
unchanged lines until their incoming lexical state changes. Native caret
measurements retain at most 96 lines; disposal releases the view's watches,
layout callbacks and caret timer.

For editor tabs, keep one `CodeEditorState` per document and mount only the
selected editor. Pass `state` instead of `value`:

```haxe
import ashui.components.code.CodeEditorState;
var document = new CodeEditorState(textSignal);
// Under a reactive owner:
return <if {selected.get()}><code-editor state={document} language="haxe" /></if>;
```

The state keeps text, bounded undo/redo patches, syntax/fold caches,
annotations, selection and scroll position. Disposing the view saves navigation
and releases its watches, row pools, measured text and minimap. Remounting reuses
the document cache and restores navigation after layout. `state.mounted` is false
when it holds no view capture hook. One state serves one mounted editor; a keyed
replacement may mount before the previous view is disposed.

An external text replacement while unmounted clears incompatible undo on remount.
Drop the state itself to release its document and history. Without `state`, an
editor owns its data as before; hiding such an editor with `display: none` keeps
the entire view alive, and disposing it discards its history.

## Zones between lines

`zone(owner, list, follow = false)` places an element between two lines: a peek at a change
under the line that changed, "Accept current | Accept incoming" above a conflict, an inline
blame, a code lens. Each entry is `{line, element}`; the element goes below the line
`line`, counted from 0, takes the editor's width beside the gutter and its own height, and the lines after it move
down by that height. It scrolls with the text, and the caret, selection, find marks, minimap
slider, `rectAt` and `offsetAt` all take it into account; a point inside a zone is over no
character.

```tsx
var choices:Element = Owner.root(tree, _ -> <div class="flex-row gap-2">
    <button onClick={_ -> acceptCurrent()}>Accept current</button>
    <button onClick={_ -> acceptIncoming()}>Accept incoming</button>
</div>);
editor.zone("conflict", [{line: 41, element: choices}], true);
```

Each owner's zones replace its own, as decorations and markers do, and `zone("conflict", [])` clears
them. With `follow` a zone stays with its line as the text is edited. A zone whose line is folded
away takes no room and comes back when the fold opens. `zoneLinesOf(owner)` says where an owner's zones are now.

The element is the editor's once it is given: make it under your own `Owner.root`, and know that a zone
replaced or cleared has its element taken out of the editor. The editor reads the height the element
lays out to, so a zone can change its own height and the lines below follow.

## Change marks

Two options of `markers` and `decorate` show changes the way a source-control view does.

A marker with `boundary: true` sits on the boundary below its line instead of beside it, as a small
triangle at the line's bottom edge in the gutter: "lines were deleted after this line". It takes
its colour from its class (`ui-code-change-removed` by default colours it as an error), and an
`icon` replaces the triangle. It does not use the line's own marker slot, so a line can have both. `title` is its tooltip.

A marker with `bar: true` is a change bar: a thin strip at the gutter's left edge, the height of its line, in its
own lane. It does not take the line's marker slot, so a breakpoint or a code action on the same line is still shown
beside it. Use it, not a plain marker, for added, modified and removed lines.

A marker or decoration with `minimap: true` is also drawn in the minimap, above the rows and without
drawing them again: a marker as a thin bar at the edge of its line, a decoration as a mark the width of the
strip on each line it touches. Both take the colour of their class, so `ui-code-change-added`, `-modified`
and `-removed` give the usual change colours (`--ui-diff-added-bar`, `--ui-diff-modified-bar` and
`--ui-diff-removed-bar` override them). At most 600 marks are drawn; a line hidden in a fold has none.

```tsx
editor.markers("scm", [
    {line: 12, className: "ui-code-change-added", bar: true, minimap: true},
    {line: 30, className: "ui-code-change-removed", boundary: true, minimap: true, title: "2 lines deleted"}
]);
```

## Find and replace

CodeEditor and CodeView include a compact floating search panel with a tinted
frosted-glass background. It mounts only while open and stays within the editor
when resized. CodeView and read-only editors allow search but refuse replacement.

- **Cmd+F / Ctrl+F:** open Find, seeded from a single-line selection.
- **Cmd+Option+F / Ctrl+H:** open Replace.
- **Enter / Shift+Enter in Find:** next / previous match, wrapping at the ends.
- **F3 / Shift+F3:** next / previous match. On macOS, Cmd+G / Cmd+Shift+G also work.
- **Enter in Replace:** replace the current match and advance.
- **Cmd+Enter / Ctrl+Enter in Replace:** replace all matches as one undo operation,
  subject to the editor's bounded history limits.
- **Escape:** close the panel and return focus to the editor.

The `Aa` and underlined `Ab` controls select case-sensitive and whole-word
matching. The `.*` control enables Haxe regular expressions. Bare patterns such
as `item(\d+)` are the usual input: **no delimiters are needed**. Optional Haxe
literals such as `~/item(\d+)/i` use their flags as written (`g`, `i`, `m`, `s`,
`u`); search enumerates all matches regardless of `g`. Bare patterns use multiline
anchors and the case option. Invalid expressions show an error without editing
the source. Regex replacements accept capture references such as `$1` and `$2`,
and `$$` inserts a literal dollar sign. Literal search leaves replacements literal.

A reference exposes `showFind(replace = false)`, `hideFind()` and
`findNext(backward = false)`. `editor.search.replaceOne()` and `replaceAll()`
apply through the same edit/history APIs as typing. Applications may set
`findShortcuts={false}` and bind those methods themselves. Search controls still
handle Enter and Escape.

`editor.state.search` retains only `opened`, `replacing`, `query`, `replacement`,
`matchCase`, `wholeWord` and `regex` signals. Keeping a CodeEditorState across tab
switches preserves these inputs without retaining controls, matches, regex subject
caches or editor closures. Highlight rectangles are bounded to visible rows and
reused while their geometry stays the same. Editing with Find open updates the
matches without moving the caret to another result.

Style `.ui-code-find`, `.ui-code-find-mark` and `.ui-code-find-current`, or use
`--ui-code-find-width` (460px), `--ui-code-find-bg`, `--ui-code-find-match`,
`--ui-code-find-border` and `--ui-code-find-active`. The backdrop blur, tint and
border follow theme tokens.

`tests/fixtures/components/CodeFindTest.hx` covers search syntax, flags, captures,
zero-width/Unicode input, responsive panel bounds, navigation, folded/offscreen
results, replacement undo, event-batch freshness, read-only/disabled guards and
view remount/disposal.

## Styling

The components follow the active theme's surfaces, typography, selection,
borders and shape tokens. Customize `.ui-code`, `.ui-code-gutter`,
`.ui-code-line-number`, `.ui-code-token[data-token="keyword"]`,
`.ui-code-selection`, `.ui-code-caret`, `.ui-code-guide` and `.ui-code-fold`.
`.ui-code-bracket` styles the matching-pair outline and background.
The fold control is the existing icon Button component.

```css
.source-editor {
    --ui-code-bg: var(--background);
    --ui-code-gutter-bg: var(--background);
    --ui-code-font-size: 14px;
    --ui-code-keyword: var(--primary);
}
```

Other custom properties are `--ui-code-font`, `--ui-code-border`,
`--ui-code-active-line`, `--ui-code-line-number`, `--ui-code-string`,
`--ui-code-comment`, `--ui-code-number`, `--ui-code-type`,
`--ui-code-function`, `--ui-code-operator`, `--ui-code-tag`,
`--ui-code-attribute`, `--ui-code-bracket-bg` and `--ui-code-bracket-border`. Syntax defaults have separate
light and dark palettes.

## Custom syntax

Implement `ashui.components.code.CodeHighlighter`. Return non-overlapping,
ordered spans using **Haxe string offsets** within the line, plus the lexical
state to pass to the next line. Return `""` when no multiline construct is open.
Cover the whole line, including plain text between colored tokens.

```haxe
import ashui.components.code.CodeHighlighter;

class NotesSyntax implements CodeHighlighter {
    public function new() {}

    public function highlight(line:String, state:String):CodeHighlight {
        return {
            tokens: [{from: 0, to: line.length,
                kind: StringTools.startsWith(line, "#") ? Comment : Plain}],
            state: ""
        };
    }
}
```

Pass `highlighter={new NotesSyntax()}` to either component. The token kinds
are `Plain`, `Keyword`, `StringLiteral`, `Comment`, `Number`, `Type`,
`Function`, `Operator`, `Tag`, `Attribute` and `MarkupText`; colors remain in CSS.
Use `MarkupText` for literal markup so bracket matching and folding skip it.

## Documentation popovers

`CodeHint` accepts a highlighted `signature`, optional `language` and `emphasis`
range, followed by plain `docs`. To render formatted documentation, supply
`renderDocs: Void->Element` instead. The builder takes precedence over `docs` and
runs under the popover's reactive owner. Its nodes, watches and `Owner.onCleanup`
handlers are released when the hint is replaced or closed.

```haxe
editor.showHint({
    from: start, to: end,
    renderDocs: () -> renderMarkdown(documentation)
});
```

Asynchronous providers can use `editor.hoverOffset` to discard replies after the
pointer moves. `showHint(hint, true)` pins a hint; `hideHint()` closes it. Edits,
scrolling, Escape and disposing the editor also close its hints.
