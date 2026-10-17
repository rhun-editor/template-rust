# Rust: rhun-ext

```toml
[dependencies]
rhun-ext = { git = "https://github.com/rhun-editor/extension-protocol", tag = "rust-v1.2.1" }
```

No other dependencies are needed. Source and docs: `rust/rhun-ext` in
https://github.com/rhun-editor/extension-protocol (`cargo doc --open` in a clone).

## Shape of an extension

```rust
use rhun_ext::{run, Doc, Event, Ext, Feature, Handler, Opened};

#[derive(Default)]
struct Mine { /* your state: documents seen, settings, views */ }

impl Handler for Mine {
    fn ready(&mut self, ext: &Ext, project: Option<&str>) {}
    fn event(&mut self, ext: &Ext, ev: &Event) {
        if let Some(o) = Opened::parse(ev) { /* o.doc, o.version, o.lang, o.path */ }
    }
    fn command(&mut self, ext: &Ext, name: &str, doc: Doc) {
        // name is the manifest key ("say", not "hello.say"); doc is the active document or 0
    }
    fn setting(&mut self, ext: &Ext, key: &str, value: &str) {}
}

fn main() {
    if let Err(e) = run(&[], Mine::default()) { eprintln!("mine: {e}"); }
}
```

Handlers run one at a time on the main thread. Requests (`ext.toast`, `ext.text`, …) block until
rhun answers; events that arrive meanwhile wait. `Ext` is `Clone + Send`: slow work goes on a
thread of your own, which may call `ext` too.

## Requests

| Call | Does |
| --- | --- |
| `ext.text(doc)` | `(bytes, version)` |
| `ext.range_text(doc, range)` | `(bytes, version)` |
| `ext.replace(doc, version, range, text)` | one undo step; the new version (error `stale` when the version moved) |
| `ext.insert(doc, version, text)` | at the cursor, replacing the selection |
| `ext.select(doc, range)` | the cursor at the range's end |
| `ext.open(path, Pos::new(line, col))` | a tab; its `Doc` |
| `ext.diagnostics(doc, version, &[Diagnostic{range, severity, source, message}])` | replaces its marks |
| `ext.hover(doc, at, text)` | the answer to a `hover` event |
| `ext.toast(text)`, `ext.status(text)` | a message; the status bar text |
| `ext.choose(prompt, &items)` → `Option<usize>`, `ext.ask(prompt)` → `Option<String>` | prompts (`None`: cancelled) |
| `ext.register(name, keys, title)` | a command while running |
| `ext.option(doc, "tab_width", "4")` | per-document options |
| `ext.term(cmd)`, `ext.cmd(name)` | a suggested terminal command; one of rhun's own commands |
| `ext.view(title)` → `View`, `ext.draw(view, &picture)`, `ext.unview(view)` | views (feature `Views`) |

Helpers: `rhun_ext::whole_range(&text)`, `parse_edits(&body)` and `apply_edits(&mut text, &edits)`
for the `edits` stream, `Settings` (`update`, `string`, `bool`, `int`).

## A view with a chart (feature `Views`)

```rust
use rhun_ext::chart::{Chart, Series};
use rhun_ext::{Metrics, View, ViewEvent};

// run(&[Feature::Views], …); in command(): self.view = ext.view("Sizes").ok();
fn view(&mut self, ext: &Ext, view: View, ev: ViewEvent) {
    match ev {
        ViewEvent::Size { width, height } => { self.size = (width, height); self.redraw(ext, view) }
        ViewEvent::Metrics(m) => { self.metrics = m; self.redraw(ext, view) }
        ViewEvent::Hover { x, y } => { self.chart.pointer = Some((x, y)); self.redraw(ext, view) }
        ViewEvent::Leave => { self.chart.pointer = None; self.redraw(ext, view) }
        ViewEvent::Click { x, y } => if let Some(hit) = self.drawn.hit(x, y) { /* hit.index */ },
        ViewEvent::Closed => self.view = None,
        _ => {}
    }
}
fn redraw(&mut self, ext: &Ext, view: View) {
    self.drawn = self.chart.draw(self.size.0, self.size.1, &self.metrics);
    let _ = ext.draw(view, &self.drawn.picture);
}
// self.chart = Chart::bar("Lines by language", &["Rust", "Go"], vec![Series::new("lines", vec![1200.0, 800.0])]).unit(" lines");
```

`Chart::bar`, `Chart::line`, `Chart::pie`; `.unit()`, `.item()`; the hovered item gets a band and
a tooltip. For your own drawing use `Picture` (`rect`, `rrect`, `line`, `poly`, `fill`, `circle`,
`ring`, `pie`, `text`, `clip`, `unclip`) with `Color::Accent`, `Color::Series(n)`, `Color::Rgb`.
Text width: `metrics.width(TextSize::Normal, "text")` (the interface font is monospaced).

## Completion and signature help (features `Complete`, `Signature`)

```rust
use rhun_ext::{CompleteRequest, CompletionItem, CompletionList, Kind, SignatureHelp, SignatureRequest};
use rhun_ext::complete::word_range;

fn complete(&mut self, ext: &Ext, req: &CompleteRequest) -> CompletionList {
    let Ok((text, _)) = ext.text(req.doc) else { return CompletionList::default() };
    let line = String::from_utf8_lossy(&text).lines().nth(req.at.line as usize - 1).unwrap_or("").to_string();
    let r = word_range(req.at.line, &line, req.at.col);
    CompletionList::new(vec![
        CompletionItem::new(r, Kind::Function, "println").insert("println!()").detail("macro").doc("Prints a line."),
    ])
}
fn signature(&mut self, ext: &Ext, req: &SignatureRequest) -> Option<SignatureHelp> {
    Some(SignatureHelp::new("fn add(a: i32, b: i32)").active_param("b: i32").doc("Adds."))
}
```

Manifest: `[provides] complete = *.rs` (and `complete.triggers`), `signature = *.rs`
(`signature.triggers = ( ,`); `run(&[Feature::Complete, Feature::Signature], …)`.

## Definition, references, symbols, code actions, rename, format

```rust
use rhun_ext::{
    ActionsRequest, CodeAction, FormatRequest, Location, PosRequest, RenameRequest, Symbol, SymbolKind,
    Target, TextEdit, WorkspaceEdit,
};

fn definition(&mut self, ext: &Ext, req: &PosRequest) -> Vec<Location> {
    // one location opens at once; several make a list; none says "No definition found"
    vec![Location::new(Target::Path("/abs/path/lib.rs".into()), range).text("pub fn add(a: i32, b: i32) -> i32 {")]
}
fn references(&mut self, ext: &Ext, req: &PosRequest) -> Vec<Location> { /* the same */ }
fn symbols(&mut self, ext: &Ext, req: &PosRequest) -> Vec<Symbol> {
    vec![Symbol::new(whole_fn, SymbolKind::Function, 0, "main").detail("fn()")]   // document order
}
fn actions(&mut self, ext: &Ext, req: &ActionsRequest) -> Vec<CodeAction> {
    let fix = WorkspaceEdit::new().doc(req.doc, req.version, vec![TextEdit::new(req.range, "fixed")]);
    vec![CodeAction::new("quickfix", "Fix it").edit(fix), CodeAction::new("source", "Organize imports").data(b"organize")]
}
fn action(&mut self, ext: &Ext, data: &[u8]) { /* the chosen action's data, after its edit */ }
fn rename(&mut self, ext: &Ext, req: &RenameRequest) -> Result<WorkspaceEdit, String> {
    // req.name is the new name; Err(text) is shown to the user
    Ok(WorkspaceEdit::new()
        .doc(req.doc, req.version, edits_here)
        .file("/abs/path/other.rs", None, edits_there))   // None: a file that is not open, as on disk
}
fn format(&mut self, ext: &Ext, req: &FormatRequest) -> WorkspaceEdit {
    // req.tab_width, req.spaces: the document's own settings
    WorkspaceEdit::new().doc(req.doc, req.version, vec![TextEdit::new(rhun_ext::whole_range(&text), &formatted)])
}
```

Manifest: `[provides] definition = *.rs`, `references`, `symbols`, `actions`, `rename`, `format`
(each a list of patterns); `run(&[Feature::Definition, Feature::References, Feature::Symbols,
Feature::Actions, Feature::Rename, Feature::Format], …)`. Keys: F12, shift+F12, ctrl+r, ctrl+.,
F2 (on a word), shift+alt+f. Build edits against the request's version: a group whose version
is not the open document's makes rhun refuse the whole edit.

## Release builds
`cargo build --release` per target on its own runner (the template's workflow): Linux
`x86_64-unknown-linux-musl` (static), macOS `aarch64-apple-darwin`, Windows
`x86_64-pc-windows-msvc` with `-C target-feature=+crt-static`.
