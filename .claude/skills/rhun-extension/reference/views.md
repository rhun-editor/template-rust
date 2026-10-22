# Retained views (protocol 1.1)

Trees, logs, forms, tables and Markdown documents whose content rhun keeps and draws in the
theme: the extension sends the content once and changes it with patches; rhun keeps the user's
expansion, selection and scroll and reports what the user does. Features for `hello 1 ...`:
`view-tree` (instances, patches, events: every kind needs it), then `view-log`, `view-form`,
`view-table`, `view-doc` for those kinds, `views` (v1 12a pictures) for `kind = picture`,
`view-keys` (the keyboard in a picture) and `view-images` (images in pictures and doc views).
Manifest: `[views]`. Spec: v1.1.md, "Retained views" ("Manifest: `[views]`", "Feature:
`view-tree`", "Feature: `view-log`", "Feature: `view-form`", "Feature: `view-table`", "Feature:
`view-doc`", "Views in tabs of their own: `vtab`", "Picture views", "Feature: `view-keys`",
"Feature: `view-images`"), https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md.
Examples: `rhun-editor/todo` (a sidebar tree, Rust), `rhun-editor/markdown` (a doc view in the
side column that follows the editor, Rust), `rhun-editor/wordfreq` (a table in the panel, C).

## Manifest and instances

```ini
[views]
# KEY.FIELD; KEY [a-z0-9_]{1,40}; at most 16 views
todo.title = TODO
# sidebar (a section under the Explorer) | panel (a bottom panel tab) | side (beside Agents)
todo.place = sidebar
# tree | log | form | table | doc (each with its feature) | picture (with views)
todo.kind = tree
# yes: expanded or chosen the first time it appears
todo.open = yes
```

A declared view shows when the extension is installed, running or not; showing it starts the
extension. Right after the catch-up that follows `ready`, rhun opens one instance per declared
view: `0 view VIEW open KIND PLACE NAME`, then `0 view VIEW visible 0|1`. Fill the instance when
`open` comes (VIEW is new for each run; NAME is the manifest key). A view with no title or an
unknown place or kind is left out. Until the first `state` or root `kids` it shows "Loading…".

## Requests and patches

| Request | Reply |
| --- | --- |
| `ID vpatch VIEW LEN` + patch | `ok ID REV`: applied whole, or nothing (`syntax op N`, `badpos OP ID`, `toobig nodes`, `noview`) |
| `ID vshow NAME FOCUS` | `ok ID VIEW`: opens the declared view's place; FOCUS `focus` or `-` |
| `ID vreveal VIEW HOW LEN` + node id | `ok ID`; HOW `-` or a comma list of `select`, `focus`, `expand` |
| `ID vtab KIND TITLE` | `ok ID VIEW`: a retained view in an editor tab of its own (`open KIND tab -` follows; `closed` when the user closes it) |
| `ID unview VIEW` | `ok ID`: closes such a tab (v1's request) |
| host: `ID vkids VIEW REV LEN` + node id | answer `ok ID LEN` + a patch (one `kids` op for that node) |
| host: `ID vmore VIEW REV HAVE LEN` + parent id | answer `ok ID LEN` + a patch (one `add` op) |

Patch body: `N` LF, then N ops `NAME ARGS... LEN` LF + LEN bytes. Ops: `title`, `badge N 0`,
`message`, `state ready|loading|empty|error TEXT_LEN LEN` + TEXT + up to 3 action keys, `busy 0|1 0`,
`action KEY ICON title|node|none LEN` + title (at most 32 actions), `select-mode single|multi 0`,
`kids PARENT_LEN N MORE LEN` + PARENT + node records (replaces the children; PARENT empty: the
root), `add` (appends), `set` (one node record), `del`, `expand`, `collapse` (+ id). MORE 1 adds a
"Load more" row (rhun then asks `vmore`).

Node record: `ID_LEN LABEL_LEN EXTRA_LEN KIDS` LF + id + label + extras; KIDS `leaf`, `closed`,
`open`. Node ids: 1 to 1000 bytes, no LF or NUL, unique in the instance, stable across patches
(they carry expansion and selection). Extras: `desc`, `tip` (Markdown with `markdown` agreed),
`icon SPEC COLOR 0`, `color NAME 0`, `hl FROM TO 0`, `badge N 0`, `check 0|1 0`, `open LINE COL
LEN` + path (a click opens it), `command NAME ARGS_LEN` + ARGS (a click runs a command reference),
`inline LEN` + keys (row buttons, 4), `menu LEN` + keys (context menu, 16), `ctx LEN` (the
`viewItem` context value), `data LEN` (given as ARGS to `[menu.view_item]` commands). Node icons
are `file folder folder-open search check close plus minus dot refresh branch pin puzzle more
terminal spark user arrow-up arrow-down discard gear` (the spec's list; rhun 0.18 also draws
`play ring circle circle-filled circle-slash warning error bug beaker stop`) or `file:NAME` (the
Explorer's icon for that name); colors `fg muted accent error warning success add mod del
c1`…`c8`. Node icons take no `ext:NAME` (status items and menus do).

Events (`0 view VIEW WHAT ...`, a node id as the body): `visible 0|1`, `focus 0|1`, `select REV N
LEN`, `activate REV LEN` (Enter, double click, or a leaf click without `open`/`command`), `expand`,
`collapse`, `check REV STATE LEN`, `action REV KEY LEN` (empty id: a header button),
`discarded REV WHAT LEN`, `closed` (a `vtab` tab closed). REV is the content the user acted on.

## The other kinds

- **log** (`view-log`): ops `log N LEN` + N lines `SEV TEXT` LF (SEV `trace debug info warn
  error -`; SGR colors kept) and `clear 0`; event `clear`. A ring of 10000 lines and 4 MB.
- **form** (`view-form`): ops `form N LEN` + field records (the whole form) and `field LEN` + one.
  Field record `KEY TYPE ROW WEIGHT LABEL_LEN EXTRA_LEN` LF; TYPE `text area number check select
  button label`; records `value SEQ LEN`, `placeholder`, `options` (one a line), `lines N 0`, `range
  MIN MAX STEP 0`, `msg SEVERITY LEN`, `disabled 0`, `primary 0`. Events `change REV KEY SEQ LEN` +
  value, `press REV KEY`, `submit REV KEY`. **The user owns a value**: `value SEQ` applies only
  when SEQ is the field's current sequence (or at creation); echo the SEQ of the last `change`.
- **table** (`view-table`): a tree with `columns N LEN` + `ALIGN WIDTH SORT TITLE_LEN` LF + title
  records (1-16), `sorted COL asc|desc|- 0`, and a node's `cell LEN` records for columns 2 and on.
  rhun sorts by itself unless a node pages its children (`MORE`): then it sends `sort REV COL
  asc|desc` and the extension resends the rows.
- **doc** (`view-doc`): ops `doc LEN` + Markdown (1 MB), `base LEN` + an absolute folder for
  relative links, `follow DOC 0` (the view tracks document DOC's top line; `0` stops). Images:
  `img:IMG` (`view-images`) or a path under the base; rhun never fetches remote images. Links it
  does not follow itself come as `link REV LEN` + target.
- **picture** (`views` + `view-tree`): a v1 12a picture in a place. It opens as `open picture
  PLACE NAME`; draw it with `draw VIEW`; it sends 12a's `size`, `metrics` and pointer events;
  only `title`, `badge`, `message`, `busy` patches apply. It is not one of the 8 tab views.
- **view-keys** (with `views`): a pressed picture takes the keyboard: `focus 0|1`, `key MODS NAME`,
  `text LEN`, `paste LEN`, `selectall`, `dblclick X Y MODS`; pointer events gain a last MODS field.
  Copy and cut ask the extension: host request `ID vcopy VIEW copy|cut`, answer `ok ID LEN` + text.
- **view-images** (with `views`): `ID vimage LEN` + PNG/JPEG/GIF bytes → `ok ID IMG`; `ID unimage
  IMG`; the picture shape `image X Y W H IMG`. 64 images and 128 MB per extension.

## SDK

| | Rust (`rhun_ext::views`) | Go (`rhunext`) | C (`rhunext.h`) |
| --- | --- | --- | --- |
| patch | `Patch::new()`, `.title .badge .message .state(State::Empty(text, keys)) .busy .action(key, Some(icon), Where::Title, title) .select_mode .kids(parent, &nodes, more) .add .set .del .expand .collapse .log(&[(LogLevel::Info, "…")]) .clear .columns .sorted(Some((col, desc))) .form .field .doc .base .follow .raw` | `NewPatch()`, `Title Badge Message State(state, text, keys...) Busy Action(key, icon, WhereTitle, title) SelectMode Kids Add Set Del Expand Collapse Log(LogLine{LogInfo, "…"}) Clear Columns(Column{…}) Sorted Form Field Doc Base Follow Raw` | `rx_patch p; memset(&p, 0, sizeof p);` `rx_patch_title _badge _message _state _busy _action _select_mode _kids _add _set _del _expand _collapse _log _clear _columns _sorted _form _field _doc _base _follow _raw`, `rx_patch_free` |
| node | `Node::new(id, label).kids(Kids::Open) .desc .tip .icon(Icon::named("file"), Some(ViewColor::Accent)) .color .highlight(0..4) .badge .check .context .data .open(path, line, col) .command(name, args) .inline(&[..]) .menu(&[..]) .cell` | `NewNode(id, label).WithKids(KidsOpen).Desc .Tip .Icon(IconNamed("file"), ViewAccent) .Color .Highlight .Badge .Check .Context .Data .Open .Command .Inline .Menu .Cell` | `rx_node_rec(&recs, id, idlen, label, "leaf", &extra)` with `rx_x_desc _tip _icon _color _hl _badge _check _ctx _data _open _command _inline _menu _cell` |
| send | `ext.patch(view, &p)` → REV, `ext.vshow(name, focus)`, `ext.vreveal(view, id, &["select"])`, `ext.vtab(kind, title)`, `ext.unview(view)` | `PatchView`, `ShowView`, `RevealView`, `TabView`, `CloseView` | `rx_view_patch`, `rx_vshow`, `rx_vreveal`, `rx_vtab`, `rx_unview` |
| events | `Handler::view_open(&ViewOpen)`, `view_event(view, &RetainedEvent)` (`Select`, `Activate`, `Action{key,..}`, `Check`, `Change{key, seq, value,..}`, `Press`, `Submit`, `Sort`, `Link`, `Clear`, `Closed` …) | `RetainedViewer` (`ViewOpen`, `ViewEvent` with `RetainedEvent{Kind, Rev, IDs, Key, Seq, Body…}`, `.ID()`) | `view_open`, `view_event` handlers (`rx_view_open`, `rx_retained_event`) |
| lazy kids | `Handler::view_children` / `view_more` (`ChildrenRequest`) → `Result<Patch, String>` | `ChildrenProvider` (`ViewChildren`, `ViewMore`) | `view_children` (`rx_children_ask`, `have` -1 for `vkids`) |
| table, form | `Column::new(t).right().min(6).sortable()`; `views::Field::new(key, FieldType::Text, row, weight, label).value(Some(seq), v)` | `Column{Title, Align, Min, Sort}`; `NewFormField(key, "text", row, weight, label).Value(seq, v)` | `rx_column`; `rx_field_rec` + `rx_fx_value _placeholder _options _msg` |
| pictures | `Handler::view` (`ViewEvent::Key`, `Text`, `Paste`, `SelectAll`, `DoubleClick`, `Focus`), `view_copy`, `view_event_mods(ev)`; `ext.image(bytes)`, `ext.unimage`, `Picture::image` | `Viewer` (`ViewEvent.Mods/Key/Text/On`), `ViewCopier`; `Image`, `Unimage`, `Picture.Image` | `view` handler (`rx_view_event`), `view_copy`; `rx_image`, `rx_unimage`, `rx_pic_image` |

Features: Rust `Feature::ViewTree ViewLog ViewForm ViewTable ViewDoc ViewKeys ViewImages Views`;
Go `FeatureViewTree …`; C the words in `rx_run("views view-tree view-table", …)`.

## Minimal example (Rust): a sidebar tree

```rust
use rhun_ext::views::{Kids, Node, Patch, RetainedEvent, State, ViewOpen, Where};
use rhun_ext::{run, Ext, Feature, Handler, View};

struct Tree;
impl Handler for Tree {
    fn view_open(&mut self, ext: &Ext, open: &ViewOpen) {
        if open.name != "files" { return; }
        let mut p = Patch::new();
        p.action("refresh", Some("refresh"), Where::Title, "Refresh")
            .kids(b"", &[Node::new("src", "src").kids(Kids::Closed)], false)
            .kids(b"src", &[Node::new("src/main.rs", "main.rs").open("/abs/src/main.rs", 1, 1)], false)
            .state(State::Ready);
        if let Err(e) = ext.patch(open.view, &p) { eprintln!("tree: {e}"); }
    }
    fn view_event(&mut self, _ext: &Ext, _view: View, ev: &RetainedEvent) {
        if let RetainedEvent::Action { key, .. } = ev { eprintln!("action {key}"); }
    }
}
fn main() { let _ = run(&[Feature::ViewTree], Tree); }
```

## Headless

`print-sidebar`, `print-panel-tabs`, `print-side-tabs` (place items), `print-views` (also retained
instances: `view=ID kind=K place=P name=N rev=R state=S busy=B title=T badge=N visible=V
nodes=N`), `print-view NAME|VIEW` (rows: `row I y=Y d=DEPTH open|closed|leaf|loading|more|error
… id=ID label=L`; tables add `columns=…` and `cells=A|B`), `print-log NAME|VIEW`, `print-form
NAME|VIEW`, `print-docview NAME|VIEW`, `view-show NAME`, `view-focus NAME`, `view-item-menu VIEW
ID [CONTEXT]` (then `print-menu`, `menu-pick`), `print-tip`. Pictures: `print-views`, `shot PATH`.

## Pitfalls

- A view is filled per instance: wait for `open` (each run gets new VIEW numbers); patching a
  view you remember from a previous run is `noview`.
- A patch is all or nothing: one bad op (an id listed twice, a parent that does not exist yet)
  drops every op. Create parents before their `kids` in the same patch.
- Keep node ids stable: a new id for the same row loses its expansion and selection.
- A root `kids` makes the view `ready`; send `state empty TEXT` when there is nothing, or it stays
  "Loading…". A `closed` node whose children you never give is asked with `vkids` when expanded:
  answer it (or give the children up front).
- Form values: echo the SEQ of the last `change`, else your `value` is dropped while the user types.
- `rhun_ext::Field` is a snippet field; the form field is `rhun_ext::views::Field`.
- An unknown node icon draws nothing: stay within the list above (Rust's `Icon::ext` and Go's
  `IconExt` build `ext:KEY`, which tree rows do not draw).
- `vtab` takes a kind whose feature was agreed (`tree`, `log`, `form`, `table`, `doc`); a kind
  not agreed is `unknown`, a ninth tab (with 12a views) `toobig 8 views`.
- Retained instances end without events when the extension stops; declared views come back with
  new instances at the next start.
