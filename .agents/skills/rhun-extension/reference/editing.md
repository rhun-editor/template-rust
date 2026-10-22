# Edits and the editor model (protocol 1.1)

Features for `hello 1 ...`: `workspace-edits`, `file-operations` (agreed only with
`workspace-edits`), `selections`, `reveal`, `diff`, `linked-editing`, `save-actions`. Manifest:
`[needs] documents = write` for any edit or save action; `project = write` (or the user's Apply)
for disk changes; `[provides] linked = PATTERNS`, `[provides] save_actions = PATTERNS`;
`[subscribe] selection` for the `selections` event. Spec: sections "Feature: `workspace-edits`",
"Feature: `file-operations`", "Feature: `selections`", "Feature: `reveal`", "Feature: `diff`",
"Feature: `linked-editing`", "Feature: `save-actions`" and "Managed saves" of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. The v1 base
(the `apply` request and section 12g's edit body) is in `protocol.md`.

## Workspace edits as transactions (`workspace-edits`)

With the feature agreed, every edit the extension sends (`apply`, a rename answer, a code action's
EDIT) is one transaction: checked whole, made everywhere or nowhere, one Undo in any tab it
touched. Format, range-format and save-actions answers and `save-apply` keep 12g's rule (one
existing document only). The body is a superset of 12g's:

```text
N LF
N entries; a text group:  PATH_LEN PRE M LF <PATH>, then M edits  L1 C1 L2 C2 LEN LF <bytes>
then extra records:       label LEN LF <one line, at most 200 bytes>   confirm 0 LF
```

PRE is a version (an open document at that version: `stale` otherwise, `nodoc` when closed), `-`
(the file on disk; an open document only while it has no unsaved changes), or `fnv1a64:HEX` (16
lowercase hex digits of the FNV-1a 64 hash of the file's bytes on disk, CR included: `stale` when
it moved). Positions always refer to rhun's text (CR before LF dropped). A closed file is edited
on disk (regular text file, at most 16 MiB) and no tab opens; clean open documents an edit also
touches are written too when the edit writes anything to disk.

Permissions: a disk change (closed file, create, rename, delete) must lie inside the project or
the extension's state folder (`needs` otherwise) and needs `project = write`, the user's standing
permission, or Apply in the confirmation list (the reply waits; `busy` when a prompt is open,
`cancelled` on Escape). `confirm` forces the list even with `project = write`.

A refused apply is `error ID CODE ENTRY TEXT`: ENTRY is the 1-based entry at fault (0 for none),
counted in phase order (creates, text groups, renames, deletes). Codes: `syntax needs nofile nodoc
stale readonly badpos toobig refused cancelled busy io`; `io` means a write failed and rhun put
everything back: the same edit may be sent again. Nothing changes on any error. Limits: 4 MiB
body, 1000 entries, 100000 edits, 64 MiB read by one edit.

## File operations (`file-operations`)

```text
create PATH_LEN FLAGS LF <PATH>           FLAGS - | overwrite,ignore-existing   (PATH/ is a folder)
rename FROM_LEN TO_LEN FLAGS LF <FROM><TO> FLAGS - | overwrite,ignore-existing
delete PATH_LEN FLAGS LF <PATH>           FLAGS - | recursive,ignore-missing
```

Absolute paths; missing parent folders are made. rhun applies phases in order: creates, text
groups, renames, deletes; text groups name files as they are after the creates and before the
renames (a file an earlier create makes takes PRE `-`). Refused: two operations on one path, a
text group for a deleted path or a rename target, anything inside `.git`, renaming or deleting
the project folder, deleting or overwriting a document with unsaved changes, a rename across
volumes, an existing target without `overwrite`/`ignore-existing`. A renamed open file keeps its
tab: extensions get `0 closed OLD` then `0 opened NEW ...` with a new DOC.

## SDK

| | Rust | Go | C |
| --- | --- | --- | --- |
| build | `WorkspaceEdit::new().doc(doc, v, edits)`, `.file(path, Some(v) or None, edits)`, `.file_hashed(path, &disk, edits)`, `.label(s)`, `.confirm()` | `var e WorkspaceEdit; e.AddDoc(doc, v, ...)`, `AddFile(path, v or OnDisk, ...)`, `AddFileHashed(path, data, ...)`, fields `Label`, `Confirm` | `rx_wedit_file(e, path, doc, version or RX_ON_DISK)`, `rx_wedit_file_hashed`, `rx_wedit_edit`, `rx_wedit_label`, `rx_wedit_confirm`, `rx_fnv1a64` |
| file ops | `.create(p, Create{..})`, `.rename(a, b, Rename{..})`, `.delete(p, Delete{..})` | `Create(p, CreateOptions{})`, `Rename(a, b, RenameOptions{})`, `Delete(p, DeleteOptions{})` | `rx_wedit_create`, `rx_wedit_rename`, `rx_wedit_delete` with `RX_OVERWRITE RX_IGNORE_EXISTING RX_RECURSIVE RX_IGNORE_MISSING` |
| send | `ext.apply(&e)` -> `Err(ApplyError{code, entry, text})` | `ext.Apply(e)` -> `*ApplyError{Code, Entry, Text}` (unwraps to `*Error`) | `rx_apply(ext, &e)`, then `rx_last_apply_error(ext)` |
| entry at fault | `e.entry(n)` -> `Entry::File(i)` / `Entry::Op(i)` | `e.Entry(n)` | |
| body for what rhun agreed | `ext.encode_edit(&e)` | `ext.EncodeEdit(e)` | `rx_wedit_finish_for(ext, e, &out)` |
| LSP `documentChanges` | `edits::from_ordered(&[Change])`, `from_ordered_origins`, `edits::locate` | `NormalizeOrdered([]Change)`, `NormalizeOrderedOrigins`, `Locate` | `rx_wedit_from_ordered`, `rx_locate` |

The SDKs follow the agreed features: without `workspace-edits` an edit goes out in 12g's grammar,
and one that needs more (a hash, a label, `confirm`, file operations; these also need
`file-operations`) fails locally as `unknown` and is not sent; a code action carrying such an edit
is left out of its list. The ordered normaliser rewrites an edit after a rename to the old name,
merges repeated edits of a file into one group and refuses what the phases cannot express with
the index of the change at fault (`OrderError`; LSP's `failedChange`). `rhun-editor/lsp`
(`wsedit.go`) maps `workspace/applyEdit` and rename answers through `NormalizeOrderedOrigins`.

```rust
// run(&[Feature::CommandArgs, Feature::WorkspaceEdits, Feature::FileOperations], …)
let Ok(disk) = std::fs::read("/proj/main.go") else { return };   // needs project = read
let fix = TextEdit::new(Range::new(Pos::new(3, 9), Pos::new(3, 15)), "helpers");
let edit = WorkspaceEdit::new()
    .create("/proj/helpers/", Create::default())         // trailing / makes a folder
    .file_hashed("/proj/main.go", &disk, vec![fix])
    .rename("/proj/util.go", "/proj/helpers/util.go", Rename::default())
    .label("Move util.go to helpers/");
if let Err(e) = ext.apply(&edit) { let _ = ext.toast(&format!("Not moved: {e}")); }
```

## Selections, reveal, diff, linked editing

| Feature | Wire | Rust | Go | C |
| --- | --- | --- | --- | --- |
| `selections` | event `0 selections DOC N LEN` + N lines `L1 C1 L2 C2` (anchor, cursor; primary first); request `ID select-many DOC N LEN` + lines (1 to 512) | `Handler::selections(&Selections)`, `ext.select_many(doc, &[Selection::new(a, c)])` | `ParseSelections(ev)`, `ext.SelectMany(doc, []Selection{...})` | `rx_parse_selections`, `rx_select_many` |
| `reveal` | `ID reveal DOC LINE COL top\|center\|nearest\|center-if-outside`; `ID show-locations LEN` + title line + a 12d locations body | `ext.reveal(doc, pos, Reveal::Center)`, `reveal_uri`, `show_locations(title, &locs)` | `Reveal(doc, pos, RevealCenter)`, `RevealURI`, `ShowLocations` | `rx_reveal(ext, doc, at, "center")`, `rx_reveal_uri`, `rx_show_locations` |
| `diff` | `ID diff LEFT RIGHT show\|background LEN` + title -> `ok ID DOC`; `ID diff-close DOC` | `ext.diff(l, r, title, Show::Front)` -> tab id, `diff_uris`, `diff_close` | `Diff(l, r, title, DiffShow)`, `DiffURIs`, `DiffClose` | `rx_diff(ext, l, r, title, background)`, `rx_diff_uris`, `rx_diff_close` |
| `linked-editing` | rhun asks `ID linked DOC VERSION LINE COL`; answer `N` LF (0, or 2 to 64) + `L1 C1 L2 C2` lines, optional `word LEN` LF + chars | `Handler::linked(&LinkedRequest) -> Linked::new(ranges)` (`.word`) | `LinkedEditor.Linked(ext, LinkedRequest) Linked{Ranges, Word}` | `linked` handler, `rx_linked_range`, `rx_linked_word` |

With `selections` agreed `insert` inserts at every selection and `select` collapses to one. Reveal
never moves the cursor or activates a tab. A diff tab's id is not a document (no `opened`, no
`text`); it follows both sides and closes when either closes; with `uris` a side may be a virtual
document's URI. Linked ranges: same text at VERSION, not overlapping, one holding the cursor;
rhun asks one provider, after the cursor rests 150 ms, and waits 1 s. `rhun-editor/lsp` answers
`linked` for HTML-like files from `textDocument/linkedEditingRange`.

## Source actions on save (`save-actions`)

```text
rhun -> ext   ID save-actions DOC VERSION KIND             -> ok ID LEN + workspace edit, or ok ID 0
ext -> rhun   ID save-apply SAVE_REQUEST DOC VERSION LEN + edit  -> ok ID NEW_VERSION
```

Needs `[provides] save_actions = PATTERNS`, `documents = write` and the feature. The user lists
kinds in `[files] code_actions_on_save` (`source.organizeImports source.fixAll`); rhun asks each
matching provider per kind, in `owner/name` order, within `code_actions_on_save_timeout` (2 s
default) for the whole phase. KIND is hierarchical: answer for KIND and its descendants. Edits may
only touch the saving document (any other group rejects the whole edit). A provider that runs
commands mid-save (a language server's `workspace/executeCommand`) sends their edits with
`save-apply` naming the save's request id and the last credited version, then answers the final
reply against the credited version (or empty). After `0 cancel SAVE_REQUEST` intermediate edits are
refused and late replies ignored. Rust `Handler::save_actions(&SaveActionsRequest)` (`req.id`,
`doc`, `version`, `kind`) and `ext.save_apply(req.id, doc, version, &edit)`; Go
`SaveActionProvider.SaveActions(ext, SaveActionsRequest)` (with `Context`, cancelled by rhun) and
`ext.SaveApplyContext(req.Context, req.ID, doc, version, edit)`; C `rx_handlers.save_actions`
(`rx_save_actions_ask`) and `rx_save_apply`. Rust and C handlers are serial: bound the work.
Example: `rhun-editor/lsp` (`save_actions.go`).

Format on save (`[files] format_on_save = true`) adds no feature: it is v1's `format` request
through the saved or sole formatter, under `format_on_save_timeout`; Format Selection and format on
type are `partial-format` (see `language.md`).

## Headless

`print-doc`, `print-tabs`, `print-state` for the result; `print-tx` (transactions, newest first),
`print-journal`, `ext-edits OWNER/NAME yes|no` (the standing permission), `print-selections`
(`sels=N` then a line per selection), `print-linked` (`linked=N` and its ranges, or `linked=none`),
`print-palette` (the confirmation list, `show-locations`), `cmd undo`, `provider-set format LANG
OWNER/NAME`, `print-providers`. `rhun-ext-check` makes transactions in its scratch project as rhun
does, answers refused applies with `error ID CODE ENTRY TEXT`, and reads each answer's edit with
the grammar rhun would.

## Pitfalls

- Build edits against the text of the version you name; `stale` means fetch again and retry once.
- A `create` path for a folder needs its trailing `/`: Go's `filepath.Join` drops it (as do
  Rust's `canonicalize` and rebuilding a path from `components()`), so append it last.
- Do not mix up phases: an edit of a file you also rename names the old path; use the normaliser
  for LSP's ordered changes instead of reordering by hand.
- Hash the bytes you actually converted positions against (`file_hashed`), not a later read.
- Format and save-action answers that name another document are refused whole, whatever was agreed.
- `select-many` with more than 512 selections is `toobig`; overlapping ones merge.
