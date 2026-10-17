# Go: rhunext

```go
import "github.com/rhun-editor/extension-protocol/go/rhunext"   // v1.1.0 or later for section 12
```

```go
type mine struct{}

func (m *mine) Ready(ext *rhunext.Ext, project string)                 {}
func (m *mine) Run(ext *rhunext.Ext, command string, doc rhunext.Doc)  {} // "NAME.key"
func (m *mine) Event(ext *rhunext.Ext, ev rhunext.Event)               {}

func main() { rhunext.Run(&mine{}) }                                    // or RunWith(features, h)
```

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
  `rhunext.CompletionItem{Range, Kind: rhunext.KindFunction, Label, Insert, Detail, Doc, Edits}`.
- signature: implement `Signature(ext, req rhunext.Request) *rhunext.SignatureHelp`
  (`{Signature, ActiveFrom, ActiveTo, Doc}`; nil hides it).

Build each target with `CGO_ENABLED=0 GOOS=… GOARCH=… go build -trimpath -ldflags=-s` (the
template's workflow).
