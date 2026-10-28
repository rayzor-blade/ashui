# Dialogs and forms

Built-in elements carry their behavior into HXX. A modal dialog manages focus
and plays its existing opening and closing transitions; a form validates its
controls before submitting.

```tsx
import ashui.ui.Dialog;
import ashui.ui.Ref;

var dialog = new Ref<Dialog>();

<dialog ref={dialog} open={showDialog} closedby="closerequest"
    onCancel={event -> { if (hasUnsavedChanges) event.preventDefault(); }}>
    <form method="dialog" class="flex-col items-stretch gap-4 w-full">
        <input name="displayName" required value={displayName} />
        <button name="action" value="saved">Save</button>
    </form>
</dialog>
```

Pass a signal to `open` to share the dialog's state. `closedby` controls
which user actions can request dismissal:

- `any`: Escape or a backdrop press.
- `closerequest`: Escape only.
- `none`: explicit controls and API calls only.

Call `preventDefault()` in `onCancel` to keep the dialog open. A child that
consumes Escape also prevents dismissal. When `closedby` is omitted,
`dismissible` applies: true allows Escape and backdrop presses; false disables both.

`dialog.get().requestClose(value)` sends `onCancel` before closing.
`dialog.get().close(value)` closes directly. The value is stored in
`returnValue`; omitting it preserves the previous value. `onClose` runs once
when an open dialog closes. `modal={false}` displays it in place.

A form with `method="dialog"` closes its containing dialog after successful
submission. The submit button's `value` becomes the dialog's `returnValue`.
Validation and `onSubmit` still run; `novalidate` skips validation.

Enter in a text input activates the first submit button. `type="button"`
never submits; `type="reset"` restores the controls. `FormData` includes named
controls and the selected submit button's `name` and `value`, in document order.

The component library's `Button` supports the same `type`, `name` and `value`.
Its `DialogContent` accepts `closedby`, `onCancel` and `onClose`; it uses the
built-in dialog underneath. See the existing
[DialogMotion example](../tools/snapshot/scenes/DialogMotion.hx) for a dialog
form with the default component theme and transitions.
