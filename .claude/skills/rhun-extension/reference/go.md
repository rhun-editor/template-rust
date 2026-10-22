# Go: rhunext

```go
import "github.com/rhun-editor/extension-protocol/go/rhunext"   // module v1.4.0: protocol 1.1 (rhun 0.18)
```

```go
type mine struct{}

func (m *mine) Ready(ext *rhunext.Ext, project string)                 {}
func (m *mine) Run(ext *rhunext.Ext, command string, doc rhunext.Doc)  {} // "NAME.key"
func (m *mine) Event(ext *rhunext.Ext, ev rhunext.Event)               {}

func main() { rhunext.Run(&mine{}) }                                    // or RunWith(features, h)
```

`go get github.com/rhun-editor/extension-protocol@v1.4.0`. With
`rhunext.RunWith([]string{rhunext.FeatureCommandArgs}, h)` (template-go does this) a handler that
also implements `Invoke(ext *rhunext.Ext, inv rhunext.Invocation)` gets every run with
`inv.Name()`, `inv.Doc`, `inv.From`, `inv.Body` and `inv.Target()` (`contributions.md`); `Run` stays
for hosts without the feature. `ext.Has(rhunext.FeatureX)` says whether rhun agreed a feature.
Most 1.1 requests have a `…Context(ctx, …)` form; cancelling the context releases the caller. Each
feature's page names its interfaces and calls (`features.md` is the index).

Requests: `Text`, `RangeText`, `Replace`, `Insert`, `Select`, `Open`, `Diagnostics`, `Hover`,
`Toast`, `Status`, `Choose`, `Ask`, `Register`, `Option`, `Term`, `Cmd`, `Request` (any).
Helpers: `ParseOpened`, `ParseEdits`, `ApplyEdits`, `ParseCursor`, `ParseHover`, `Settings`,
`WholeRange`, `WordStart`, `Cancelled(err)`, `Busy(err)`.

Section 12 (`rhunext.RunWith([]string{rhunext.FeatureViews, rhunext.FeatureComplete}, h)`):
- views: `ext.OpenView(title)`, `ext.Draw(view, &pic)`, `ext.CloseView(view)`; the handler
  implements `View(ext, view, ev ViewEvent)` (`ev.Kind`: size, metrics, hover, click, …);
  `rhunext.Picture` has `Rect`, `RRect`, `Line`, `Poly`, `Fill`, `Circle`, `Ring`, `Pie`, `Text`,
  `Clip`, `Unclip` with `rhunext.ColorAccent`, `rhunext.Series(n)`, `rhunext.RGB(…)`.
- completion: implement `Complete(ext, req rhunext.Request) rhunext.CompletionList` with
  `rhunext.CompletionItem{Range, Kind: rhunext.KindFunction, Label, Insert, Detail, Doc, Edits}`;
  `.WithCursor(n)` puts the cursor n bytes into Insert (a snippet's `$0`).
- signature: implement `Signature(ext, req rhunext.Request) *rhunext.SignatureHelp`
  (`{Signature, ActiveFrom, ActiveTo, Doc}`; nil hides it).
- definition, references (`FeatureDefinition`, `FeatureReferences`): implement
  `Definition(ext, req rhunext.PosRequest) []rhunext.Location` and `References(…)`;
  `rhunext.Location{Target: rhunext.Target{Path: abs}, Range, Text}` (`Target{Doc: id}` for an
  untitled document).
- symbols (`FeatureSymbols`): `Symbols(ext, req rhunext.PosRequest) []rhunext.Symbol` with
  `rhunext.Symbol{Range, Kind: rhunext.SymbolFunction, Depth, Name, Detail}`, in document order.
- code actions (`FeatureActions`): `Actions(ext, req rhunext.ActionsRequest) []rhunext.CodeAction`
  (`{Kind: rhunext.ActionQuickFix, Title, Edit: &edit, Data}`) and `Action(ext, data []byte)`, the
  chosen action's data after its edit.
- rename (`FeatureRename`): `Rename(ext, req rhunext.RenameRequest) (rhunext.WorkspaceEdit, error)`;
  an error is shown to the user. Format (`FeatureFormat`): `Format(ext, req rhunext.FormatRequest)
  rhunext.WorkspaceEdit` (`req.TabWidth`, `req.Spaces`).
- workspace edits: `var e rhunext.WorkspaceEdit; e.AddDoc(req.Doc, req.Version, edits...)`,
  `e.AddFile(path, version or rhunext.OnDisk, edits...)` with `rhunext.TextEdit{Range, Text}`;
  `ext.Apply(e)` applies one on your own (needs `documents = write`).

Build each target with `CGO_ENABLED=0 GOOS=… GOARCH=… go build -trimpath -ldflags=-s` (the
template's workflow).
