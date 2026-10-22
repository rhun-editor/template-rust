# Every feature, and where it is described

A feature is a name in `hello 1 NAME…` (the SDK's run call takes them: Rust `run(&[Feature::X],
…)`, Go `rhunext.RunWith([]string{rhunext.FeatureX}, h)`, C `rx_run("x y", &h, NULL)`). rhun says
back the ones it agrees in `0 features …` before `ready`; send a feature's requests only when
it was agreed (Rust `ext.has(Feature::X)`, Go `ext.Has(rhunext.FeatureX)`, C `rx_has(ext, "x")`;
the SDKs check it and fail locally with `unknown`). rhun 0.18 sets `RHUN_PROTOCOL=1.1` in the
extension's environment; an older host ignores names it does not know, so an extension that asks
for 1.1 features still has to work, more plainly, without them. A provider also needs its
`[provides]` key: rhun asks only when both are there.

Specs: v1 (frozen) https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1/v1.md
and 1.1 https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md (the
manifest schema `v1.1/v1.1.json`, the grammar `v1.1/v1.1.abnf`).

## v1 section 12

| Feature | Manifest | Reference |
| --- | --- | --- |
| `views` (pictures in tabs, 12a) | | `rust.md`, `go.md`, `c.md`; `views.md` for picture views in places |
| `complete`, `signature` | `[provides] complete`, `complete.triggers`, `signature`, `signature.triggers` | language SDK pages; `language.md` |
| `definition`, `references`, `symbols`, `actions`, `rename`, `format` | `[provides]` the same keys | language SDK pages; `language.md` |

## Protocol 1.1

| Feature | Manifest | Reference |
| --- | --- | --- |
| `command-args`, `commands`, `context-keys`, `status-items` | `[command-options]`, `[keys]`, `[menu.*]`, `[submenu.*]`, `[status]`, `[context]`, `[icons]` | `contributions.md` |
| (none: data) | `[language.NAME]`, `syntax/*.syn`, `icon-themes/*.icons` | `contributions.md` |
| `workspace-edits`, `file-operations`, `selections`, `reveal`, `diff`, `linked-editing` | `[provides] linked`; `[needs] documents = write`, `project = write` | `editing.md` |
| `save-actions` | `[provides] save_actions` | `editing.md` |
| `snippets`, `snippet-variants`, `snippet-transforms` | | `snippets.md` |
| `view-tree`, `view-log`, `view-form`, `view-table`, `view-doc`, `view-keys`, `view-images` | `[views]` | `views.md` |
| `notify`, `progress`, `quick-input`, `markdown` | | `ui.md` |
| `query-stream`, `provider-scope`, `complete-items`, `signature-list`, `hover-query`, `navigation`, `selection-ranges`, `hierarchy`, `workspace-symbols`, `prepare-rename`, `partial-format`, `code-actions`, `file-diagnostics`, `document-links`, `diagnostic-tags` | `[provides] hover`, `declaration`, `type_definition`, `implementation`, `selection_ranges`, `call_hierarchy`, `type_hierarchy`, `workspace_symbols`, `range_format`, `type_format`, `type_format.triggers`, `document_links` | `language.md` |
| `decorations`, `folding-ranges`, `semantic-tokens`, `inlay-hints`, `code-lens`, `document-highlights`, `document-colors`, `inline-complete` | `[provides] folding`, `semantic_tokens`, `inlay_hints`, `code_lens`, `highlights`, `colors`, `inline_complete` | `presentation.md` |
| `terminals`, `tasks` | `[needs] terminal = run\|input\|output` | `tasks.md` |
| `debug` | `[needs] debug = yes`, `[debugger.TYPE]` | `debug.md` |
| `tests` | `[provides] tests`, `tests.profiles`; `[needs] tests` | `test-controllers.md` |
| `git-data`, `commit-message`, `quickdiff`, `scm` | `[needs] git = read`; `[provides] commit_message`, `quickdiff` | `scm.md` |
| `notebooks` | `[provides] notebook`, `notebook.title`, `notebook.kernel`; `[needs] kernels` | `notebooks.md` |
| `custom-editors` | `[provides] editor`, `editor.title`, `editor.model`, `editor.priority` | `custom-editors.md` |
| `agents`, `agent-prompts`, `edit-review`, `tools` | `[provides] agents`, `agents.title`; `[tools]` | `ai.md` |
| `workspace_watch`, `files`, `workspace-folders`, `scoped-settings`, `secrets`, `uris`, `urls`, `idle` | `[needs] secrets`; `[provides] schemes`; `idle`, `idle.after`; `on = contains:…`; `[settings] KEY.scope`, `KEY.languages` | `resources.md` |
| (none: manifest) | `where`, `run.wasm32-wasip1`, `pack` | `distribution.md` |

Feature names are exact: `workspace_watch` has an underscore; Go names two constants differently
from their wire names' shape (`FeatureHighlights` is `document-highlights`, `FeatureColors` is
`document-colors`); Rust has `Feature::Named("x")` for a name the enum lacks, but every name above
has a variant.

## What the conformance checker agrees

`rhun-ext-check` (v1.4.0) agrees and exercises: the v1 features, `commands`, `save-actions`, the
snippet features, the source control features, `view-tree`, `view-log`, `view-keys`,
`view-images`, `notify`, `progress`, the resources features except `workspace_watch`, the AI
features, the editing features, `notebooks`, `custom-editors`, the language features above,
`command-args`, `context-keys`, `status-items`, `tests`, `terminals`, `tasks` and `debug`. It does
**not** agree `workspace_watch`, `view-form`, `view-table`, `view-doc`, `quick-input`,
`markdown`, `decorations`, `diagnostic-tags` or the presentation providers: against the checker
the extension runs as on a host without them (which it must survive). Test those headlessly
against rhun (`testing.md`). Like rhun, it agrees `tasks` only together with `terminals` and
`file-operations` only together with `workspace-edits`.
