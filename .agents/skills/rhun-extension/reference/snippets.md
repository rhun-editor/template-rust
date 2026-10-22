# Snippets: native editable fields (protocol 1.1)

Features for `hello 1 ...`: `snippets`, and with it optionally `snippet-variants` (mirrors that
start with different text) and `snippet-transforms` (regex transforms run when a field is left).
No new manifest key: completion snippets ride on v1's `[provides] complete`; explicit insertion
needs `documents = write`, the insertion context `documents = read`. Spec: "Feature: `snippets`"
and its subsections "Read-only insertion context", "Declared initial mirror variants", "Compiled
field transforms" and "Portable binary programs" of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md.

rhun never parses template syntax (`${1:x}`): the extension sends **prepared** text (the template
already expanded) plus byte ranges saying which parts are fields. Once inserted, the session is
rhun's: it keeps working after the extension stops.

## Wire

Completion items (12b) and the explicit request carry the same EXTRA records:

```text
field GROUP START END PARENT 0            an occurrence: INSERT bytes [START, END) on UTF-8 boundaries
choice GROUP COUNT LEN LF <COUNT x: OPTION_LEN LF <bytes>>      literal values of a primary
variant FIELD 0                           (snippet-variants) field record FIELD (1-based) may differ
transforms 0 LEN LF <Base64 of an SNTX program>                 (snippet-transforms), at most one
```

- GROUP 0 is the optional final selection (empty: a caret; without it the caret ends at INSERT's
  end). The first occurrence of a positive group is its **primary**; later ones are **mirrors**
  with identical initial bytes (unless declared a `variant`). Tab visits positive groups in
  increasing order, then 0.
- PARENT is 0 or the 1-based index of an earlier field record that is another group's primary
  containing this one. Overlapping ranges must follow the parent chain; mirrors cannot contain
  fields; same-group occurrences cannot overlap; group dependency cycles are invalid.
- A choice's first option must equal the primary's initial bytes; 1 to 256 options, each at most
  1 MiB, may be empty or multiline.
- Invalid metadata in a completion item is dropped as a whole: the item inserts its plain INSERT.
  An older host skips the records and inserts the text, so keep the prepared text sensible alone.

Explicit insertion (after agreement), replacing a range:

```text
ID snippet DOC VERSION L1 C1 L2 C2 LEN      -> ok ID NEW_VERSION
body:  0 0 0 0 snippet 0 INSERT_LEN 0 EXTRA_LEN LF <INSERT><EXTRA>
       EXTRA: field and choice records (variant, transforms with their features); nothing else
```

VERSION must be exact (`stale` otherwise); the whole request is validated before anything
changes; success selects the first positive field without switching tabs.

Insertion context (`snippets` agreed, `documents = read`; no cursor or selection change):

```text
ID snippet-context DOC VERSION L1 C1 L2 C2  -> ok ID VERSION LEN + body
body:  context 1 LINE COL TABWIDTH SPACES CRLF SELECTED_LEN LINE_LEN PATH_LEN WORKSPACE_LEN INDENT_LEN COMMENT_LEN LF
       <selected text><current line><path><workspace><indentation><line comment token>
```

It never holds the clipboard, environment, time or random data: supply those yourself. Insert
with the same VERSION and range; an edit in between makes the insert `stale`.

Limits: 512 field records, 256 positive groups, nesting 32, 4 MiB per explicit record (Base64
included); completion lists keep their 1 MiB cap (an item over it is left out and the list marked
incomplete). Transforms: one batch per Tab, 16,777,216 work units, 50 ms, 4 MiB inserted.

## SDK

| | Rust | Go | C |
| --- | --- | --- | --- |
| prepared text | `PreparedSnippet { text, fields: vec![Field { group, start, end, parent }] }`, `.validate()` | `PreparedSnippet{Text, Fields: []Field{{Group, Start, End, Parent}}}`, `Validate()` | `rx_snippet` (`text`, `len`, `fields`, `nfields`) of `rx_snippet_field`, `rx_snippet_validate` |
| with choices, variants, transforms | `SnippetProgram { snippet, choices: vec![SnippetChoice { group, options }], initial_variants, transforms }` | `SnippetProgram{Snippet, Choices, InitialVariants, Transforms}` | `rx_snippet_program` (`choices`, `initial_variants`, `transforms`) with `rx_snippet_choice`, `rx_snippet_option` |
| completion item | `CompletionItem::new(r, Kind::Snippet, "for").snippet(s)` / `.snippet_program(p)` | `item.WithSnippet(s)` / `item.WithSnippetProgram(p)` | `rx_list_item_snippet`, `rx_list_item_snippet_program` |
| explicit insert | `ext.insert_snippet(doc, v, span, &s)`, `ext.insert_snippet_program(doc, v, span, &p)` | `InsertSnippet`, `InsertSnippetProgram` (and `…Context`) | `rx_insert_snippet`, `rx_insert_snippet_program` |
| context | `ext.snippet_snapshot(doc, v, span)` -> `SnippetSnapshot` | `ext.SnippetSnapshot(doc, v, span)`, `SnippetSnapshotContext` | `rx_get_snippet_snapshot`, `rx_snippet_snapshot_free` |
| templates (`${1:x}`, choices, variables, transforms) | none yet: build `Field`s yourself | `PrepareSnippetTemplate(src, SnippetContext{Variables})`, `PrepareSnippetTemplateWithSnapshot(src, snap, SnippetVariableOptions{})`, `ParseSnippetTemplate(src)` then `t.Prepare(ctx)` | none yet |
| compiled transforms | `CompiledSnippetTransform::from_programs(regex, repl)`, `SnippetFieldTransform { field, transform }` | `CompileSnippetTransform(regex, format, options)`, `SnippetFieldTransform{Field, Transform}`, `DecodeSnippetTransforms` | `rx_snippet_transform_program`, `rx_snippet_field_transform`, `rx_snippet_transform_validate` |

Go is the only SDK that parses templates and compiles transforms from source; Rust and C import
programs Go compiled (`CompiledSnippetTransform.Programs()` in Go exports the RNRX/RNRF bytes).
Never hand-assemble SNTX/RNRX bytes. The SDKs validate whole programs before sending; the explicit
helpers refuse variants or transforms whose feature was not agreed (`unknown`). Go's
`SnippetVariableOptions` takes `Variables`, `Time` (`SnippetTimeFromTime`), `Random` (16 bytes),
`Clipboard`, block comment tokens and `KeepWhitespace`; preparation reads nothing on its own.

```go
// Go: a template from the user's snippet file, as the completion item and on a command
// (rhunext.RunWith([]string{FeatureComplete, FeatureSnippets, FeatureSnippetVariants,
// FeatureSnippetTransforms}, h); [provides] complete = *.go)
const src = "for ${1:i} := 0; $1 < ${2:n}; $1++ {\n\t$0\n}"
p, err := rhunext.PrepareSnippetTemplate(src, rhunext.SnippetContext{})
if snap, e := ext.SnippetSnapshot(req.Doc, req.Version, word); e == nil {
	p, err = rhunext.PrepareSnippetTemplateWithSnapshot(src, snap, rhunext.SnippetVariableOptions{})
}
if err != nil { return rhunext.CompletionList{} }
it := rhunext.CompletionItem{Range: word, Kind: rhunext.KindSnippet, Label: "for"}
return rhunext.CompletionList{Items: []rhunext.CompletionItem{it.WithSnippetProgram(p)}}
// on a command: ext.InsertSnippetProgram(doc, version, span, p)
```

```rust
// Rust: "add(a, b)" with fields a (group 1), b (group 2) and the caret after ")" (group 0)
let s = PreparedSnippet {
    text: "add(a, b)".into(),
    fields: vec![
        Field { group: 1, start: 4, end: 5, parent: 0 },
        Field { group: 2, start: 7, end: 8, parent: 0 },
        Field { group: 0, start: 9, end: 9, parent: 0 },
    ],
};
let item = CompletionItem::new(Range::new(req.at, req.at), Kind::Snippet, "add").snippet(s);
```

```c
/* C: the same item */
static const rx_snippet_field f[] = {{1, 4, 5, 0}, {2, 7, 8, 0}, {0, 9, 9, 0}};
rx_snippet s = {"add(a, b)", 9, f, 3};
rx_list_item_snippet(&l, r, "snippet", "add", &s, "add(a, b)", NULL, NULL, NULL, 0);
```

Example extension: `rhun-editor/snippets` (Go: `PrepareSnippetTemplateWithSnapshot` for
completion, `InsertSnippetProgram` for Expand Snippet); `rhun-editor/lsp` turns a server's
`insertTextFormat = Snippet` items into programs the same way.

## The session (what users get, what to test)

Tab and Shift+Tab move between fields, Escape ends the session; a completion list takes Tab first.
Typing in a primary updates its mirrors in one undo step. A choice list opens on its field (Up,
Down, Enter keeps the field active, Tab applies and moves on); Snippet: Choose Value reopens it.
A snippet inserted inside an active field nests (at most 32 levels): its final Tab returns to the
enclosing field. Undo, reload, moving the selection outside the active field or an outside edit
ends the session. Commands: `snippet_next`, `snippet_previous`, `snippet_cancel`,
`snippet_choose`; when-clause key `snippetActive`.

## Headless

There is no `print-snippet`: test through the document and the selection. `print-doc` after the
insert, `print-state` (`sel=` shows the selected field), `key Tab` / `key shift+Tab` / `type X`
then `print-doc` again (mirrors), `print-complete` while a choice list shows (then `key Down`,
`key Return`), `print-context snippetActive` or `when snippetActive`. `cmd-args NAME ARGS` invokes
an insert command with arguments. See `rhun-editor/snippets` `tests/fields.txt`.

## Pitfalls

- Offsets are **bytes** into the prepared text, half-open, on UTF-8 boundaries, never characters.
- A mirror whose initial text differs from its primary invalidates the whole item unless
  `snippet-variants` is agreed and the field is declared; check `ext.has`/`Has`/`rx_has` first.
- An empty prepared text stays empty: the label is not inserted in its place.
- Field metadata is not allowed in a `complete-resolve` answer; send it with the list.
- Nested `${1:${2:x}}` needs PARENT set to the outer primary's record index (1-based); the Go
  template helpers do this for you.
- The explicit request needs the exact current VERSION; get it from `snippet-context` or `text`
  and do not await user input in between.
