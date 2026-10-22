# Custom editors (protocol 1.1)

Feature `custom-editors` in `hello 1 ...`, with `views` (the tab is a 12a picture view the
extension draws) and usually `view-keys` (the view takes the keyboard). Manifest: `[provides]
editor = PATTERNS`, `editor.title`, `editor.model = text|owned`, `editor.priority =
default|option`. Spec section "Feature: `custom-editors`" of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md (and "Picture
views", "Feature: `view-keys`" for drawing and keys). Example: `rhun-editor/hexedit` (Rust, an
owned model for binary files of any size).

```ini
[provides]
editor = *.bin *.dat *.img
editor.title = Hex Editor
# text: rhun keeps the file as a document; owned: the extension keeps its bytes
editor.model = owned
# default: matching files open in it; option: only through Reopen Editor With...
editor.priority = option
```

## Two models

- **text**: the file is an ordinary rhun document (its DOC is the editor's `CDOC`), never shown
  as a text tab. The extension hears it like any open document (`opened`, `edits`, by its path),
  reads it with `text` and changes it with `replace` (`documents = write`). rhun owns undo, the
  dirty dot, Save, Save As, Revert File, reloads and the close question. Only `editor-open` and
  `editor-closed` come.
- **owned**: the extension keeps the contents (a binary, a huge file). rhun keeps a stand-in
  with the path, routes Undo, Redo, Save, Save As, Revert File and the close and quit questions to
  the extension, shows its dirty dot and writes the bytes it is given.

Which editor opens a file: the first extension whose `editor` patterns match with priority
`default`; a file rhun cannot open as text (a binary) opens in the first matching editor, an
`option` one too. **Reopen Editor With...** lists Text and every matching editor; the choice holds
for that file extension in the config's `[editors]` section (`*.bin = rhun-editor/hexedit`, or
`text`). An editor that refuses a file, does not run, or did not agree the feature closes its tab
and the file opens as text with the reason in a toast.

## Messages

| Direction | Message | Reply or meaning |
| --- | --- | --- |
| rhun → ext | `ID editor-open CDOC VIEW MODEL SOURCE LEN` + path | `ok ID 0` when ready (an error closes the tab, opens the file as text, shows the error); VIEW is the 12a view to `draw`; SOURCE `file`, or `backup` (open the unsaved changes rhun kept: `editor-read` reads the backup, and the editor is dirty). 30 s |
| ext → rhun | `ID editor-read CDOC OFFSET MAX` | `ok ID LEN` + up to MAX (≤ 4 MB) bytes from OFFSET; LEN 0 at the end. Needs no `project = read` |
| ext → rhun | `ID editor-dirty CDOC 0\|1` | `ok ID`; an owned model's dirty dot and close question (`refused` for a text model) |
| rhun → ext | `ID editor-save CDOC KIND PART` | KIND `save`, `saveas` or `backup`; reply `ok ID LEN` + `MORE` LF + at most 4 MB; rhun asks PART+1 until MORE is `0` (1 GB in all), then replaces the file at once. Snapshot the model at part 0 |
| rhun → ext | `0 editor-path CDOC LEN` + path | after a Save As |
| rhun → ext | `ID editor-undo CDOC`, `ID editor-redo CDOC`, `ID editor-revert CDOC` | Undo, Redo, Revert File in an owned tab; reply `ok ID 0` |
| rhun → ext | `0 editor-changed CDOC` | an owned model's file changed on disk: a clean model reads it again; a dirty one is the extension's call |
| rhun → ext | `0 editor-closed CDOC` | the tab closed (after the save-or-discard question) |

A save or backup marks the model saved only when no `editor-dirty` came after its first part was
asked for. **Backups**: 30 s after an owned editor last said `editor-dirty CDOC 1`, rhun asks
`editor-save CDOC backup PART` and keeps the parts in its state folder; when the extension stops
with unsaved changes, the tab stays with **Restore Unsaved Changes**, which starts it again and
sends `editor-open … backup`. After a crash of rhun the file reopens from its backup too. When the
extension stops, its editors' tabs close; when its program starts again at once they reopen. The
editor's view is not one of the extension's 8 tab views. With `view-keys` a press gives it the
keyboard: `key`, `text`, `paste`, `selectall` events, and `vcopy` asks for the clipboard's text.

## SDK

| | Rust (`rhun_ext::custom_editor`, `Feature::CustomEditors`) | Go (`FeatureCustomEditors`) | C (`"custom-editors"`) |
| --- | --- | --- | --- |
| open | `Handler::editor_open(&EditorOpen) -> Result<(), String>` (`cdoc`, `view`, `model: Model::Text \| Owned`, `source`, `path`) | `CustomEditor.EditorOpen(ext, *EditorOpen) error` (`CDoc`, `View`, `Model`, `Source`, `Path`) | `rx_handlers.editor_open(ext, cdoc, view, model, path, user)`: NULL, or why |
| save | `Handler::editor_save(&EditorSave) -> Result<(bool, Vec<u8>), String>` (`kind: SaveKind::Save \| SaveAs \| Backup`, `part`); `part_of(data, part, PART_MAX)` | `CustomEditor.EditorSave(ext, *EditorSave) (more bool, part []byte, err error)`; `EditorPartOf`, `EditorPartMax` | `editor_save(ext, cdoc, kind, part, out, &more, user)` |
| undo, redo, revert | `editor_undo`, `editor_redo`, `editor_revert` | `EditorCommands` (`EditorUndo`, `EditorRedo`, `EditorRevert`) | `editor_cmd` ("undo", "redo", "revert") |
| events | `editor_changed`, `editor_path`, `editor_closed` | `EditorEvents` (`EditorChanged`, `EditorPath`, `EditorClosed`) | `editor_event` ("changed", "closed", "path") |
| requests | `ext.editor_read(cdoc, offset, max)`, `editor_read_all(cdoc)`, `editor_dirty(cdoc, bool)` | `EditorRead`, `EditorReadAll`, `EditorDirty` | `rx_editor_read` (malloc'd; free it), `rx_editor_dirty` |
| copy, cut (`view-keys`) | `Handler::view_copy(view, cut) -> Option<String>` | `ViewCopier.ViewCopy` | `rx_handlers.view_copy` |

The C `editor_open` handler gets no SOURCE: a C editor cannot tell a backup restore from a file.

```rust
use rhun_ext::custom_editor::{part_of, CDoc, EditorOpen, EditorSave, SaveKind, PART_MAX};
use rhun_ext::picture::Align;
use rhun_ext::{run, Color, Ext, Feature, Handler, Picture, TextSize, View, ViewEvent};

#[derive(Default)]
struct Hex { cdoc: CDoc, view: View, bytes: Vec<u8>, saved: Vec<u8>, snapshot: Vec<u8> }

impl Hex {
    fn draw(&self, ext: &Ext) {
        let mut p = Picture::new();
        let line: Vec<String> = self.bytes.iter().take(16).map(|b| format!("{b:02x}")).collect();
        p.text(8.0, 8.0, TextSize::Mono, Align::Left, Color::Fg, &line.join(" "));
        let _ = ext.draw(self.view, &p);
    }
}

impl Handler for Hex {
    fn editor_open(&mut self, ext: &Ext, req: &EditorOpen) -> Result<(), String> {
        // an owned model reads the file (or its backup) through rhun
        self.bytes = ext.editor_read_all(req.cdoc).map_err(|e| e.to_string())?;
        // a backup holds unsaved changes: rhun shows the editor dirty
        self.saved = if req.source == "backup" { Vec::new() } else { self.bytes.clone() };
        (self.cdoc, self.view) = (req.cdoc, req.view);
        self.draw(ext);
        Ok(())
    }
    fn view(&mut self, ext: &Ext, _view: View, ev: ViewEvent) {
        if let ViewEvent::Text(t) = ev {            // view-keys: a typed character
            if let Ok(b) = u8::from_str_radix(&t, 16) {
                self.bytes.insert(0, b);
                let _ = ext.editor_dirty(self.cdoc, self.bytes != self.saved);
                self.draw(ext);
            }
        }
        // a real editor also redraws on ViewEvent::Size and ViewEvent::Metrics
    }
    fn editor_save(&mut self, _ext: &Ext, req: &EditorSave) -> Result<(bool, Vec<u8>), String> {
        if req.part == 0 { self.snapshot = self.bytes.clone(); }   // the bytes as of part 0
        let (more, part) = part_of(&self.snapshot, req.part, PART_MAX);
        if !more && req.kind != SaveKind::Backup { self.saved = self.snapshot.clone(); }
        Ok((more, part.to_vec()))
    }
    fn editor_revert(&mut self, ext: &Ext, cdoc: CDoc) -> Result<(), String> {
        self.bytes = ext.editor_read_all(cdoc).map_err(|e| e.to_string())?;
        self.saved = self.bytes.clone();
        let _ = ext.editor_dirty(cdoc, false);
        self.draw(ext);
        Ok(())
    }
    fn editor_closed(&mut self, _ext: &Ext, _cdoc: CDoc) { *self = Hex::default(); }
}

fn main() {
    let _ = run(&[Feature::Views, Feature::ViewKeys, Feature::CustomEditors], Hex::default());
}
```

One editor at a time here; a real one keys its state by CDOC (several files can be open).

## Testing headless

`print-custom` (`cdoc=ID ext=OWNER/NAME model=text|owned dirty=D path=P view=V
state=opening|ready|stopped` per editor), `reopen-with OWNER/NAME|text`, `custom-backup` (takes
the backups due now), `custom-restore` (presses Restore Unsaved Changes), `custom-timeout`
(`timeout=MS`); `shot PATH`, `click X Y`, `type` and `key` drive and show the view. Open the file
with `open PATH` (an `option` editor needs `reopen-with` first); `dirty=` in `print-custom` shows
what `editor-dirty` said.

## Pitfalls

- Answer `editor-open` quickly (30 s cap) and read big files lazily with `editor_read` ranges.
- Take the snapshot at part 0: edits during a multi-part save must not mix into it.
- Text model: do not send `editor-dirty` (it is `refused`); edit through `replace` like any
  document, with `documents = write`.
- Draw on `size` and `metrics`, in theme colors; the view is a 12a picture (`views`).
- Without `view-keys` the editor has only the pointer, prompts and its commands.
