# Presentation (protocol 1.1)

How an extension styles the text: `decorations` (your own styled ranges and virtual text, pushed
whenever you like) and the presentation providers rhun asks about the **active document only**
(`folding-ranges`, `semantic-tokens`, `inlay-hints`, `code-lens`, `document-highlights`,
`document-colors`, `inline-complete`). List each in `hello 1 ...`; a provider also needs its
`[provides]` key with file patterns; `decorations` needs `[needs] documents = read` and no key.
Spec: https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md, sections
"Feature: `decorations`", "Presentation providers" (with one "Feature: `NAME`" each) and "Feature:
`diagnostic-tags`". Model extensions (branch rhun-0.18): `rhun-editor/lsp` (Go: every provider),
`rhun-editor/blame` (Rust: a decoration type with after-text that follows the cursor's line).

## Providers at a glance

| Feature | `[provides]` | Who is asked | Asked | Gives up after |
| --- | --- | --- | --- | --- |
| `folding-ranges` | `folding` | one: the language's | on activation, 500 ms after edits | 30 s |
| `semantic-tokens` | `semantic_tokens` | one | on activation, 150 ms after edits | 30 s |
| `document-highlights` | `highlights` | one | caret rests 250 ms in or at the end of a word | 5 s |
| `inline-complete` | `inline_complete` | one | a typing pause (`inline_complete` on), or alt+\ | |
| `inlay-hints` | `inlay_hints` | every match, merged | activation, 250 ms after edits, 100 ms after a scroll | 10 s |
| `code-lens` | `code_lens` | every match | activation, 500 ms after edits, 100 ms after a scroll | 10 s |
| `document-colors` | `colors` | every match | activation, 500 ms after edits, after a scroll | 10 s |

"One" is the language's provider of Single-provider selection (the saved `[providers]` choice;
the spec says never a chooser for these kinds). rhun 0.18 keys these choices
`folding`, `tokens`, `highlights` and `inline` (`provider-set folding Go OWNER/NAME` works
headless). At most one request per document, feature and provider is out: a newer one sends
`0 cancel ID` for the older, and requests about a document that stopped being active are
withdrawn. They leave the last 16 of rhun's 64 outstanding requests to the user. Answers name a
VERSION; an answer about an older version is moved onto the current text (dropped when the edits
since are no longer kept). A malformed or over-cap answer is dropped whole.

## Wire

| Request (rhun) | Answer body |
| --- | --- |
| `ID folding-ranges DOC VERSION` | `N` LF, N × `START END KIND TEXT_LEN` LF + TEXT (KIND `region comment imports -`; lines START+1..END hide; TEXT ≤ 80 bytes or empty for ` ⋯ `) |
| `ID semantic-tokens DOC VERSION PREV` | `RESULT LEGEND full N` LF + 5N ints, or `RESULT LEGEND delta K` LF + K × (`START DEL N` LF + N ints) |
| `ID semantic-tokens-range DOC VERSION L1 L2` | `RESULT LEGEND range N` LF + 5N ints (documents over 200,000 lines or 8 MB) |
| `ID inlay-hints DOC VERSION L1 L2` | `N` LF, N × `LINE COL before\|after NPARTS EXTRA_LEN` LF, NPARTS × (`LABEL_LEN TIP_LEN PEXTRA_LEN` LF + LABEL TIP PEXTRA), then EXTRA |
| `ID code-lens DOC VERSION L1 L2` | `N` LF, N × `LINE TITLE_LEN EXTRA_LEN` LF + TITLE EXTRA (every lens of the document) |
| `ID highlights DOC VERSION LINE COL` | `N` LF, N × `L1 C1 L2 C2 text\|read\|write` LF |
| `ID colors DOC VERSION L1 L2` | `N` LF, N × `L1 C1 L2 C2 RRGGBBAA` LF |
| `ID color-edit DOC VERSION L1 C1 L2 C2 RRGGBBAA` | a workspace edit for DOC (the user picked a new color on the swatch) |
| `ID inline-complete DOC VERSION LINE COL typed\|invoked` | `N` LF (≤ 8), N × `L1 C1 L2 C2 TEXT_LEN EXTRA_LEN` LF + TEXT EXTRA |

| Request (extension) | Effect |
| --- | --- |
| `ID semantic-legend LEGEND LEN` + `TYPES` LF `MODIFIERS` | names a legend (≤ 8, 256 types, 64 modifiers); a name may be `NAME=EFFECT` |
| `ID decoration-type NAME LEN` + `KEY ARGS` lines | registers or restyles your type NAME (`[a-z0-9_-]`, 1-40) |
| `ID decorate DOC VERSION NAME FROM TO N LEN` + N records | replaces your ranges of NAME whose first line is in FROM..TO (`0 0`: all) |
| event `0 visible DOC L1 L2` | the active document's lines on screen (`0 0 0`: none), at most every 100 ms |

Extra records: hint parts take `command NAME LEN` (click runs it) or `goto LINE COL LEN` + path
(click opens it; empty path: this document); a hint's EXTRA takes up to 16 `edit L1 C1 L2 C2 LEN`
(a double click applies them); a lens takes `command` and `tip LEN`; an inline item `command` (run
after it is taken) and `edit` records. Commands are command references (contributions.md:
`command-args` delivers `0 run EXT.NAME DOC ref LEN` + ARGS).

**Semantic tokens.** Ints are LSP's layout with byte columns: per token `DLINE DCOL LEN TYPE MODS`
(the first DLINE counts from line 1; MODS a 64-bit set over the legend's modifiers). RESULT is
your id for this answer (`-` for none); rhun sends it back as PREV so you may answer a delta
against it. Classes come from the type's EFFECT, else rhun's table (`function method` →
function, `parameter variable property` → variable, `macro` → preproc, `keyword modifier` →
keyword, ...), else the grammar's class stays. EFFECT is a class name, `strike`, `underline`,
`faded` or `-`; without one, the modifier `deprecated` strikes and `defaultLibrary` makes
function/type/variable builtin. Tokens are single-line; the later of two overlapping wins.

**Decoration types** (one line each): `color C`, `background C`, `line-background C`,
`border W C`, `underline solid|double|dotted|dashed|squiggle C`, `strike C|-`, `faded`,
`before C BG|-`, `after C BG|-`, `width CELLS`, `gutter SHAPE C` (`dot circle ring square diamond
triangle bar check cross plus minus arrow`), `scrollbar C`, `grow none|start|end|both`,
`priority 0-100`. A color is a theme name (`warning`, `keyword`, `git_added`), `NAME/PCT`,
`#rrggbb[aa]`, or `DARK|LIGHT`. A range record is `L1 C1 L2 C2 BEFORE_LEN AFTER_LEN TIP_LEN
EXTRA_LEN` LF + BEFORE AFTER TIP EXTRA (no LF after the texts); BEFORE/AFTER are virtual text:
drawn in the line, never in the document, copy or search; EXTRA may hold a `command` record run by
a click on that text. VERSION may be up to 256 edits old: rhun moves the ranges. Limits: 64 types,
20,000 records per message and per document, 4 MB a body.

## SDK

| Feature | Rust | Go | C |
| --- | --- | --- | --- |
| decorations | `Ext::decoration_type(name, body)`, `Ext::decorate(doc, version, name, from, to, &[DecorationRange])`, `parse_visible(ev)` → `Visible { doc, first, last }` | `ext.DecorationType`, `ext.Decorate(..., []DecorationRange)`, `ParseVisible(ev)` | `rx_decoration_type`, `rx_decorate(..., const rx_decoration *, n)`, `rx_visible` |
| folding-ranges | `Handler::folding_ranges(&DocRequest)` → `Vec<FoldingRange { start, end, kind, text }>` | `FoldingRangeProvider` | `folding_ranges` + `rx_folding_range` |
| semantic-tokens | `Ext::semantic_legend(name, &types, &mods)`; `Handler::semantic_tokens(&SemanticTokensRequest { prev, range, .. })` → `Option<SemanticTokens { result, legend, data, delta, edits }>` | `ext.SemanticLegend`; `SemanticTokensProvider` (`SemanticTokens{Result, Legend, Data, Edits, Delta}`) | `rx_semantic_legend`; `semantic_tokens` + `rx_semantic_full`, `rx_semantic_delta`, `rx_semantic_edit` |
| inlay-hints | `Handler::inlay_hints(&LinesRequest { first, last, .. })` → `Vec<InlayHint { at, before, parts: Vec<InlayHintPart>, edits }>` | `InlayHintProvider` (`InlayHint`, `InlayHintPart`, `InlayGoto`, `InlayEdit`) | `inlay_hints` + `rx_inlay_hint` (`rx_hint_part`) |
| code-lens | `Handler::code_lenses` → `Vec<CodeLens { line, title, tip, command }>` | `CodeLensProvider` (`CodeLenses`) | `code_lenses` + `rx_code_lens` |
| document-highlights | `Handler::highlights(&PosRequest)` → `Vec<Highlight { range, kind: "write" }>` | `HighlightProvider` (`Highlight{Range, Read, Write}`) | `highlights` + `rx_highlight` |
| document-colors | `Handler::colors` → `Vec<DocumentColor { range, rgba }>`, `Handler::color_edit(&ColorEditRequest)` | `ColorProvider` (`Colors`, `ColorEdit`; `R, G, B, A`) | `colors` + `rx_document_color`, `color_edit` |
| inline-complete | `Handler::inline_complete(&InlineRequest)` → `Vec<InlineItem { range, text, command, edits }>` | `InlineCompleter` | `inline_complete` + `rx_inline_item` |

Feature constants: Rust `Feature::Decorations`, `FoldingRanges`, `SemanticTokens`, `InlayHints`,
`CodeLens`, `DocumentHighlights`, `DocumentColors`, `InlineComplete`; Go `FeatureDecorations`,
`FeatureFoldingRanges`, `FeatureSemanticTokens`, `FeatureInlayHints`, `FeatureCodeLens`,
`FeatureHighlights` (`"document-highlights"`), `FeatureColors` (`"document-colors"`),
`FeatureInlineComplete`. A command in Rust is `CommandLink::new(name, args)`, in Go a
`*CommandRef{Name, Args}`, in C a NAME, args and length. C's `rx_inline_item` takes no edit records.

## Example (Rust)

```rust
use rhun_ext::{run, CodeLens, CommandLink, DecorationRange, Event, Ext, Feature, FoldingRange,
    Handler, InlayHint, InlayHintPart, LinesRequest, DocRequest, Opened, Pos, Range};

struct Show;
impl Handler for Show {
    fn ready(&mut self, ext: &Ext, _project: Option<&str>) {
        let _ = ext.decoration_type("todo", "after warning -\nbackground warning/15\ngutter dot warning\n");
    }
    fn event(&mut self, ext: &Ext, ev: &Event) {
        let Some(o) = Opened::parse(ev) else { return };
        let r = Range::new(Pos::new(1, 1), Pos::new(1, 5));
        let _ = ext.decorate(o.doc, o.version, "todo", 0, 0, &[DecorationRange {
            range: r, after: " TODO".into(), tip: "a task".into(), ..Default::default() }]);
    }
    fn folding_ranges(&mut self, _ext: &Ext, _req: &DocRequest) -> Vec<FoldingRange> {
        vec![FoldingRange { start: 1, end: 9, kind: "region".into(), text: "header".into() }]
    }
    fn inlay_hints(&mut self, _ext: &Ext, req: &LinesRequest) -> Vec<InlayHint> {
        let part = InlayHintPart { label: ": i32".into(), tip: "inferred".into(), ..Default::default() };
        vec![InlayHint { at: Pos::new(req.first, 10), parts: vec![part], ..Default::default() }]
    }
    fn code_lenses(&mut self, _ext: &Ext, _req: &LinesRequest) -> Vec<CodeLens> {
        vec![CodeLens { line: 1, title: "Run".into(), command: Some(CommandLink::new("run", b"main")),
            ..Default::default() }]
    }
}
fn main() {
    let _ = run(&[Feature::Decorations, Feature::FoldingRanges, Feature::InlayHints,
        Feature::CodeLens, Feature::CommandArgs], Show);
}
```

Manifest: `[provides] folding = *.rs`, `inlay_hints = *.rs`, `code_lens = *.rs`; `[subscribe]
opened = *.rs`; `[needs] documents = read`; a `[commands] run = Run` for the lens (it arrives as
`invoke` with `from == "ref"` and the body `main`).

## Testing

`rhun-ext-check` knows these `[provides]` keys but does not agree the features (nor
`decorations`): it only shows your extension works without them, so check `has(Feature::...)`
before sending `decoration-type` or `semantic-legend`. Test them in headless rhun with rhun's own
controls (not in the spec; read their output once before writing an expected file):

| Print | Shows |
| --- | --- |
| `print-present deco` / `types` / `ranges` / `glyphs` | decorations and their types, gutter icons |
| `print-present folds` | folding ranges (drive with `cmd fold`, `cmd unfold`, `cmd fold_all`, `cmd unfold_all`) |
| `print-present tokens`, `print-classes LINE` | semantic tokens; the classes drawn on a line after the overlay |
| `print-present hints`, `print-present lenses` | inlay hints, code lenses |
| `print-present highlights` | highlights (rest the caret: `wait 400`) |
| `print-present colors` | color swatches |
| `print-present ghost` | the inline completion shown (`cmd inline_complete`, then `key Tab`) |
| `print-hit X Y`, `print-xy LINE COL` | what a pixel hits (`text L C`, `inlay KIND L C` with KIND `ghost fold hint deco swatch lens`, `left-lane L`, `digits L`, `fold-lane L`, `git L`, `none`); where a text position is drawn, for `click` |
| `print-tip` | a decoration's or hint's tip |

## Pitfalls

- Presentation requests come only for the active document; do not push work for every open file.
  Use the `visible` event (decorations) or L1..L2 (hints, lens, colors) to limit work to the view.
- Code lens answers hold every lens of the document and replace all of yours; unresolved titles
  may be empty (`…`) but keep their rows. Inlay hints replace yours only on the lines asked.
- Register the legend (`semantic-legend`) before rhun asks: an answer's LEGEND names one of yours.
  A delta needs the PREV rhun sent; answer `full` when unsure. Columns are bytes, not UTF-16.
- Decorations are yours until you change them or stop: re-`decorate` with `0 0` and no records to
  clear a type on a document. A type name that was never registered is `syntax unknown decoration
  type`; `readonly` for a diff view.
- Users can turn providers off (`[editor] semantic_highlighting`, `inlay_hints`, `code_lens`,
  `color_swatches = false`): rhun then never asks. `inline_complete` off only stops asking as
  the user types (alt+\ still asks, KIND `invoked`); `highlight_occurrences` governs rhun's own
  word marks when no provider answers, not yours.
- Folding, tokens, highlights and inline completion ask one provider and never show a chooser:
  with several matching extensions, save the choice (`[providers]`, or `provider-set` in a test).
