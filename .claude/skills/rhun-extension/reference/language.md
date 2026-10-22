# Language features (protocol 1.1)

These complete v1's providers (section 12b-12h): list each feature in `hello 1 ...` (the SDK's
run call) and the matching `[provides]` key with file patterns; rhun asks only when both are there.
Spec: https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md, part
"Language features" ("Manifest keys", "Queries: kinds, time and caps", one "Feature: `NAME`" section
each), plus "Feature: `diagnostic-tags`" and "Single-provider selection". Requests keep v1 framing:
rhun sends `ID VERB ...`, you answer once with `ok ID LEN` + body or `error ID CODE TEXT`, rhun may
send `0 cancel ID` and drops late answers. Positions are 1-based lines and byte columns. Model
extensions, on their branch rhun-0.18: `rhun-editor/lsp` (Go, every feature here),
`rhun-editor/format` (Go, `partial-format`), `rhun-editor/words` (C++, `complete-items` with
resolve).

## Features, keys and handlers

| Feature | `[provides]` key | Rust `Handler::` | Go interface | C `rx_handlers.` |
| --- | --- | --- | --- | --- |
| `complete-items` | v1 `complete` | `complete_resolve` → `Resolution` | `CompletionResolver` | `complete_resolve` |
| `signature-list` | v1 `signature` | `signatures` → `Option<SignatureList>` | `SignatureLister` | `signatures` |
| `hover-query` | `hover` | `hover` → `Option<Hover>` | `HoverProvider` | `hover` |
| `navigation` | `declaration`, `type_definition`, `implementation` | `declaration`, `type_definition`, `implementation` (and `*_stream`) | `Declarer`, `TypeDefiner`, `Implementer` (or `StreamingLocator`) | same names, with an `rx_stream` |
| `selection-ranges` | `selection_ranges` | `selection_ranges` → `Vec<Vec<Range>>` | `SelectionRanger` | `selection_ranges` |
| `hierarchy` | `call_hierarchy`, `type_hierarchy` | `call_hierarchy`, `calls_in`, `calls_out`, `type_hierarchy`, `supertypes`, `subtypes` | `CallHierarchyProvider`, `TypeHierarchyProvider` | same names |
| `workspace-symbols` | `workspace_symbols` | `workspace_symbols` | `WorkspaceSymbolProvider` | `workspace_symbols` |
| `prepare-rename` | v1 `rename` | `prepare_rename` | `RenamePreparer` | `prepare_rename` |
| `partial-format` | `range_format`, `type_format`, `type_format.triggers` | `range_format`, `type_format` | `RangeFormatter`, `TypeFormatter` | `range_format`, `type_format` |
| `code-actions` | v1 `actions` | `code_actions`, `code_action_resolve` | `CodeActionProvider2`, `CodeActionResolver` | `code_actions`, `code_action_resolve` |
| `document-links` | `document_links` | `document_links` | `DocumentLinker` | `document_links` |
| `query-stream` | | `complete_stream`, `definition_stream`, `references_stream`, `Stream` | `StreamingCompleter`, `StreamingLocator`, `Stream` | `complete_stream`, `definition_stream`, `references_stream`, `rx_stream` |
| `provider-scope` | (narrows any key) | `Ext::provides`, `provides_manifest`, `withdraw` | `Provides`, `ProvidesManifest`, `Withdraw` | `rx_provides` |
| `file-diagnostics` | (needs `documents = read`) | `Ext::file_diagnostics`, `reset_diagnostics` | `FileDiagnostics`, `ResetDiagnostics` | `rx_file_diagnostics`, `rx_reset_diagnostics` |
| `diagnostic-tags` | | `Diagnostic.tags` on `Ext::diagnostics` | `Diagnostic.Tags` on `Diagnostics` | `rx_tagged_severity` |

Feature constants: Rust `Feature::CompleteItems`, `HoverQuery`, `CodeActions`, ... (each name in
CamelCase); Go `rhunext.FeatureCompleteItems`, `FeatureHoverQuery`, ...; C the names as a
space-separated string to `rx_run`. Every new `[provides]` key, like v1's, sends you `opened` and
`edits` for matching files and starts you when the first one opens. Add `markdown` to `hello` to
have hover text, completion documentation and signature documentation drawn as Markdown.

## Time and caps (rhun withdraws with `0 cancel ID` at the limit and keeps what came)

| Request | Parts | Limit | One answer |
| --- | --- | --- | --- |
| `complete` | yes | the list's session | 4096 items, 1 MiB (whole query 8192, 2 MiB) |
| `complete-resolve`, `selection-ranges` | no | 1 s | 64 KiB |
| `hover-query` | no | shown at 1 s, 3 s | 64 KiB |
| `definition`, `declaration`, `type-definition` | yes | 5 s, up to 30 s with progress | 10000, 1 MiB |
| `implementation`, `references` | yes | 10 s, up to 60 / 120 s | 10000, 1 MiB |
| `workspace-symbols` | yes | 5 s / 30 s | 10000, 1 MiB |
| `call-hierarchy`, `type-hierarchy` / `calls-*`, `*types` | no / yes | 5 s / 5 s up to 30 s | 64 items / 1000 |
| `code-actions` | no | 3 s invoked, 1 s auto | 1000, 4 MiB |
| `prepare-rename` | no | 2 s | 4 KiB |
| `rename` | no | 15 s, up to 120 s | v1's edit caps |
| `format`, `range-format` | no | 10 s, up to 30 s | v1's edit caps |
| `type-format` | no | 500 ms | 64 KiB |
| `signature`, `signatures` | no | the help's session | 64 KiB |
| `symbols` | no | 5 s | 10000, 1 MiB |
| `code-action-resolve` | no | 5 s, up to 60 s | 4 MiB |
| `document-links` | no | 2 s | 10000, 1 MiB |

Whole-query caps for kinds with parts: definition, declaration and type definition 10000 and
4 MiB; implementation 20000, 8 MiB; references 100000, 16 MiB; workspace symbols 20000, 4 MiB;
calls and sub/supertypes 10000, 4 MiB; hover-query 256 KiB in all.

Automatic requests (hover, the lightbulb, links, resolve, the Outline) are not sent while 48 of
rhun's 64 outstanding requests are out. Answer fast or stream; cancellation is advisory for you.

## Wire, feature by feature

- **query-stream**: `ID query-part REQ LEN` + a body in REQ's answer grammar (count line and
  records), `ID query-progress REQ PERCENT LEN` + one line (`-` for no percent); each waits for
  `ok ID` (that is the flow control); `error ID cancelled` means stop. The final `ok REQ LEN` holds
  the rest (`0` LF when nothing remains). Rust `Stream::part`, `part_locations`, `part_items`,
  `part_calls`, `part_hierarchy_items`, `part_workspace_symbols`, `progress(Option<u8>, text)`,
  `is_cancelled`; Go `Stream.Part`, `PartLocations`, `PartItems`, `PartCalls`,
  `PartHierarchyItems`, `PartWorkspaceSymbols`, `Progress(percent or -1, text)`, `Stream.Context`;
  C `rx_stream_part`, `rx_stream_locations`, `rx_stream_items`, `rx_stream_calls`,
  `rx_stream_hierarchy`, `rx_stream_workspace_symbols`, `rx_stream_progress`, `rx_stream_cancelled`.
- **provider-scope**: `ID provides KEY VALUES`: VALUES a subset of the manifest's own patterns for
  KEY, `*` the manifest's, `-` withdraws the kind, until the process stops. It only narrows (a
  language server that registers capabilities later). `print-provides OWNER/NAME`.
- **complete-items**: item EXTRA records `resolve EDITS LEN`, `replace L1 C1 L2 C2 0` (the header's
  range becomes the insert range; both start at the same place), `commit LEN`, `filter LEN`,
  `suffix LEN`, `preselect 0`, `deprecated 0`, `adjust 0`, `after signature 0`, `after complete 0`.
  rhun asks `ID complete-resolve DOC VERSION LEN` + the data for the selected item; the answer is
  EXTRA records only (`doc`, `detail`, `edit`, `after`). Rust `CompletionItem` builders `.resolve(data,
  edits)`, `.replace`, `.commit`, `.filter`, `.suffix` and fields `preselect`, `deprecated`,
  `adjust`, `after_signature`, `after_complete`; `Resolution { doc, detail, edits, after_signature,
  after_complete }`. Go `CompletionItem` fields `Resolve`, `ResolveEdits`, `Replace`, `Commit`,
  `Filter`, `Suffix`, `Preselect`, `Deprecated`, `Adjust`, `AfterSignature`, `AfterComplete`;
  `Resolution` (`HasDetail` with `Detail`). C `rx_item_extra` with `rx_list_item_extra`,
  `rx_resolve_answer`.
- **signature-list**: rhun sends `ID signatures DOC VERSION LINE COL KIND CHAR` instead of v1's
  `signature`; answer `N ACTIVE` LF then N `FROM TO SIG_LEN DOC_LEN` LF + SIG DOC (N 1-32, `ok ID 0`
  hides). Rust `SignatureList { signatures: Vec<SignatureInfo { label, active, doc }>, active }`;
  Go `SignatureList{Signatures: []SignatureInfo{{Label, ActiveFrom, ActiveTo, Doc}}, Active}`
  (set `ActiveFrom` and `ActiveTo` to -1 for no active parameter: the zero value is bytes 0-0);
  C `rx_signature_info` and `rx_signatures_answer`.
- **hover-query**: `ID hover-query DOC VERSION LINE COL pointer|invoked -` → `ok ID LEN` +
  `L1 C1 L2 C2` LF + text (`0 0 0 0`: the position only), `ok ID 0` for nothing. Every matching
  provider is asked; the card merges them after diagnostics. Rust `Hover::new(range, text)`; Go
  `Hover{Range, Text}`; C `rx_hover_answer`.
- **navigation**: `ID declaration|type-definition|implementation DOC VERSION LINE COL invoked -` →
  a v1 locations body; parts allowed. The peek commands (`peek_definition` alt+F12, ...) and Find
  All References (Results tab) need no new feature.
- **selection-ranges**: `ID selection-ranges DOC VERSION N LEN` + N `LINE COL` lines → N groups
  `M` LF + M `L1 C1 L2 C2`, innermost first, each containing the one before. Helpers: Rust
  `selection_chain`, Go `SelectionChain`, C `rx_selection_group`.
- **hierarchy**: roots `ID call-hierarchy|type-hierarchy DOC VERSION LINE COL invoked -`; then
  `ID calls-in|calls-out|supertypes|subtypes LEN` + an item's DATA (to the item's provider). Item:
  `KIND L1 C1 L2 C2 S1 SC1 S2 SC2 PATH_LEN NAME_LEN DETAIL_LEN DATA_LEN` LF + bytes; a call adds `R`
  and R site lines. Rust `HierarchyItem::new(kind, name, target, range).selection(r).data(b)`,
  `Call::new(item, sites)`; Go `HierarchyItem{Kind, Name, Detail, Target, Range, Selection, Data}`,
  `Call{Item, Sites}`, `HierarchyRequest`; C `rx_hierarchy_item`, `rx_hierarchy_add`, `rx_call_add`.
- **workspace-symbols**: `ID workspace-symbols MAX LEN` + query → `N` LF + `L1 C1 L2 C2 KIND
  PATH_LEN NAME_LEN DETAIL_LEN` records; parts allowed; a new query withdraws the old request.
  Rust `WorkspaceSymbol::new(target, range, kind, name).detail(..)`; Go `WorkspaceSymbol`; C
  `rx_workspace_symbol`.
- **prepare-rename**: `ID prepare-rename DOC VERSION LINE COL invoked -` → `L1 C1 L2 C2 PLEN` LF +
  placeholder, `ok ID 0` (the word), or `error ID refused TEXT` (no rename at all). Rust
  `Ok(Some(PreparedRename::new(range, ph)))` / `Ok(None)` / `Err(text)`; Go `*PreparedRename`, an
  error refuses (`ErrNothingToRename`); C `rx_prepare_rename_answer`, `return rx_refuse_answer(out, why)`.
- **partial-format**: `ID range-format DOC VERSION L1 C1 L2 C2 TAB_WIDTH SPACES TRIM FINAL` and
  `ID type-format DOC VERSION LINE COL CHAR TAB_WIDTH SPACES TRIM FINAL` (CHAR the typed character
  or `newline`) → a workspace edit for DOC only. `type_format.triggers = } newline`. Type and paste
  formatting are off unless the user sets `[editor] format_on_type` / `format_on_paste`. Rust
  `RangeFormatRequest { range, tab_width, spaces, trim, final_newline }`, `TypeFormatRequest { at,
  ch, .. }`; Go `RangeFormatRequest{Range, TabWidth, Spaces, Trim, Final}`, `TypeFormatRequest{At,
  Char, ..}`; C `rx_range_format_ask`, `rx_type_format_ask`.
- **code-actions** (replaces v1's `actions` request; `hello` names `code-actions`, the manifest key
  stays `actions`): `ID code-actions DOC VERSION L1 C1 L2 C2 TRIGGER KINDS DIAGS` (TRIGGER
  `invoked`/`auto`, KINDS `-` or `quickfix,refactor.extract`, DIAGS `-` or your diagnostic ids) →
  `N` LF + `KIND TITLE_LEN EDIT_LEN EXTRA_LEN` LF + TITLE EDIT EXTRA; EXTRA `preferred 0`,
  `disabled LEN`, `resolve LEN`, `command NAME ARGS_LEN`, `fixes LEN`. Choosing an action with
  resolve data and no edit sends `ID code-action-resolve DOC VERSION LEN` + data → `EDIT_LEN
  EXTRA_LEN` LF + EDIT + command records. Rust `Action::new(kind, title).edit(e).preferred()
  .disabled(why).resolve(data).command(CommandRef::new(name, args)).fixes(&[ids])`,
  `CodeActionsRequest::wants(kind)`, `ResolvedAction { edit, command }`; Go `Action{Kind, Title,
  Edit, Preferred, Disabled, Resolve, Command, Fixes}`, `CodeActionsRequest.Wants`, `ResolvedAction`;
  C `rx_code_action` with `rx_action_extra`, `rx_kind_wanted`, `rx_resolved` + `rx_command_ref`.
- **document-links**: `ID document-links DOC VERSION` → `N` LF + `L1 C1 L2 C2 TARGET_LEN TIP_LEN`
  LF + TARGET TIP; TARGET an http(s) URL, `/abs/path[:LINE[:COL]]` or `#DOC`. Rust
  `DocumentLink::new(range, LinkTarget::Url(..) | Path(p, Pos) | Doc(d)).tip(..)`; Go
  `DocumentLink{Range, Target: LinkURL(u) | LinkPath(p, at) | LinkDoc(d), Tip}`, `ValidLinkTarget`;
  C `rx_document_link`, `rx_link_target_valid`.
- **file-diagnostics** (needs `documents = read`): `ID file-diagnostics VERSION N TARGET_LEN LEN` +
  TARGET (`#DOC` with its current VERSION, or an absolute path with VERSION `-`) + N records
  `L1 C1 L2 C2 SEVERITY MSG_LEN EXTRA_LEN` LF + MESSAGE (may hold LF) + EXTRA (`id`, `code`,
  `source`, `href`, `tag unnecessary|deprecated 0`, `related ...`). It replaces your set for that
  target in the Problems store (`N` 0 clears); `file-diagnostics-reset` clears all. Ids come back
  in code-actions' DIAGS. Rust `Diagnostic { range, severity, message, id, code, source, href,
  tags, related, ..Default::default() }`; Go `Diagnostic{..., ID, Code, Source, Href, Tags,
  Related}`; C `rx_diagnostic`, `rx_related`.
- **diagnostic-tags**: v1 `diagnostics` lines may say `hint+unnecessary` or `warning+deprecated`
  (faded, struck through). Without the feature that is a `syntax` error: let the SDK add tags.

## Single-provider selection

Format (with range- and type-format), rename, document symbols and signature help use one
provider per language, saved in `extensions.ini` `[providers]` (`format.Go = rhun-editor/format`,
`format.* = ...`) or chosen by the user once; definitions, references and code actions merge every
provider. A request waits up to 5 s for the chosen extension to start. Nothing to declare: just do
not assume you are the only formatter. Headless: `provider-set format|rename|symbols|signature
LANGUAGE OWNER/NAME` (`-` clears), `print-providers`.

## Example (Rust)

```rust
use rhun_ext::{run, Action, CodeActionsRequest, Diagnostic, DiagnosticTag, Event, Ext, Feature,
    Handler, Hover, HoverRequest, Opened, Pos, Range, Severity, Target, TextEdit, WorkspaceEdit};

struct Lint;
impl Handler for Lint {
    fn event(&mut self, ext: &Ext, ev: &Event) {
        let Some(o) = Opened::parse(ev) else { return };
        let r = Range::new(Pos::new(1, 1), Pos::new(1, 4));
        let d = Diagnostic { range: r, severity: Severity::Warning, message: "unused".into(),
            id: "u1".into(), tags: vec![DiagnosticTag::Unnecessary], ..Default::default() };
        let _ = ext.file_diagnostics(&Target::Doc(o.doc), Some(o.version), &[d]);
    }
    fn hover(&mut self, _ext: &Ext, _req: &HoverRequest) -> Option<Hover> {
        // Range::default() (0 0 0 0): about the position only
        Some(Hover::new(Range::default(), "**unused**: nothing reads it"))
    }
    fn code_actions(&mut self, _ext: &Ext, req: &CodeActionsRequest) -> Vec<Action> {
        if !req.diagnostics.iter().any(|id| id == "u1") || !req.wants("quickfix") { return vec![] }
        let fix = WorkspaceEdit::new().doc(req.doc, req.version, vec![TextEdit::new(req.range, "")]);
        vec![Action::new("quickfix", "Remove it").edit(fix).preferred().fixes(&["u1"])]
    }
}
fn main() {
    let _ = run(&[Feature::FileDiagnostics, Feature::HoverQuery, Feature::CodeActions,
        Feature::Markdown], Lint);
}
```

Manifest: `[provides] hover = *.rs` and `actions = *.rs`; `[needs] documents = write`. Go: the
same methods on the handler (`Hover(ext, req rhunext.HoverRequest) *rhunext.Hover`,
`CodeActions(ext, req rhunext.CodeActionsRequest) []rhunext.Action`); C: `h.hover`,
`h.code_actions`.

## Testing

`rhun-ext-check` agrees every feature above but `diagnostic-tags` and `markdown`, asks each one your `[provides]` keys name and
checks the answers (kinds, extras, command names, links, chains, parts), sends
`complete-resolve` and `code-action-resolve` with your data, serves `query-part`,
`query-progress`, `provides`, `file-diagnostics` and `-reset`. Headless rhun:

| Feature | Drive | Print |
| --- | --- | --- |
| complete-items | `key ctrl+space`, `type`, `key Down` | `print-complete` (adds a `selected label= detail= doc= resolved= replace= commit=` line) |
| hover-query | `hover-at LINE COL`, `key ctrl+i` | `print-hover-card` |
| navigation, references, hierarchy | `cmd declaration`, `cmd implementation`, `key shift+F12`, `key shift+alt+h`, `cmd peek_definition` | `print-results`, `print-peek`, `print-palette` |
| selection-ranges | `key shift+alt+Right` | `print-selections`, `print-state` |
| workspace-symbols, symbols | `key ctrl+t`, `type` | `print-palette`, `print-outline` |
| prepare-rename, rename | `key F2` | `print-palette`, `print-doc` |
| partial-format | `cmd format_selection`, typing a trigger | `print-doc` |
| code-actions | `key ctrl+.`, `cmd quick_fix_auto`, `cmd organize_imports` | `print-palette`, `print-lightbulb` |
| file-diagnostics | `key F8` | `print-problems`, `print-file-diagnostics`, `print-marks` |
| document-links | `cmd open_link` | `print-doc-links` |
| any | | `print-langstats [OWNER/NAME]`, `print-query`, `print-provides OWNER/NAME`, `print-context editorProviders` |

`print-results`, `print-peek`, `print-outline`, `print-lightbulb`, `print-selections`,
`print-file-diagnostics` and `print-doc-links` are rhun's own test controls (not in the spec):
run them once and read their output before writing an expected file.

## Pitfalls

- A `[provides]` key without the feature in `hello` (or the feature without the key) gets nothing.
- `code-actions` replaces v1 `actions` requests: do not also implement only `actions`; drop
  actions whose kind is not wanted (`wants`) or rhun drops them. An action with no edit, resolve
  data or command is left out.
- Edits answer at the request's VERSION. A `range-format`/`type-format` edit naming another
  document rejects the whole edit; a late `type-format` edit (after 500 ms) is dropped.
- File diagnostics for `#DOC` need its current version (`stale V` otherwise); a path target needs
  read access to it (`needs`) and must be absolute. At most 2000 per target.
- With `hover-query` agreed you no longer get v1's `0 hover` event for that position.
- Streamed parts must follow the answer's grammar exactly; a bad part is dropped (`syntax`), a
  kind without parts answers `refused`.
