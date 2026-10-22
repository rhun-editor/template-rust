# Resources, workspaces and sign-in (protocol 1.1)

What an extension reaches beyond the open documents: the workspace's files and their changes,
several workspace folders, settings per folder and language, the system keychain, virtual
documents by URI, web pages and links back from the browser, and staying alive while it works.
Features for `hello 1 ...`: `workspace_watch` (an underscore, unlike every other name), `files`,
`workspace-folders`, `scoped-settings`, `secrets`, `uris`, `urls`, `idle`. Manifest: `[needs]
project = read` (watch, files), `[needs] secrets = yes`, `[provides] schemes`, `idle = stop`,
`idle.after`, `on = contains:…`, `[settings] KEY.scope` and `KEY.languages`. Spec sections
"Feature: `workspace_watch`", "Feature: `files` (finding files and searching their text)",
"Feature: `workspace-folders` (several folders in a window)", "Feature: `scoped-settings`
(settings per workspace, folder and language)", "Feature: `secrets`", "Feature: `uris` (URIs and
virtual documents)", "Feature: `urls` (opening URLs, link callbacks)", "Lifecycle: `idle = stop`
and feature `idle`" of https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md.

## Wire

| Feature | Request (extension to rhun) | Reply | Events |
| --- | --- | --- | --- |
| `workspace_watch` | `ID watch-workspace`, `ID unwatch-workspace HANDLE` | `ok ID HANDLE`, `ok ID` | `0 watch HANDLE changed`, `0 watch HANDLE rescan` |
| `files` | `ID find-files FOLDER MAX FLAGS LEN` + globs | batches `0 found ID LEN`, then `ok ID COUNT STATUS` | |
| `files` | `ID search-text FOLDER MAX FLAGS LEN` + `PATTERN_LEN GLOBS_LEN` LF, pattern, globs | batches, then `ok ID MATCHES FILES SKIPPED STATUS` | |
| `workspace-folders` | `ID folder-of PATH` | `ok ID FOLDER` (0: none) | `0 folders LEN` + `N` LF, `FOLDER LOCATION FLAGS NAME_LEN PATH_LEN` LF + NAME PATH |
| `scoped-settings` | `ID setting-get KEY FOLDER LANG` | `ok ID LEN` + value | `0 setting-changed KEY` |
| `secrets` | `secret-get KEY`, `secret-set KEY LEN` + value, `secret-delete KEY`, `secret-keys` | `ok ID 1 LEN` + value or `ok ID 0 0`; `ok ID`; `ok ID LEN` + keys LF-ended | |
| `uris` | `ID open LINE COL URI`, `ID content-changed URI` | `ok ID DOC`, `ok ID` | rhun asks `ID content URI`; `0 content-closed URI`; `0 opened DOC VERSION LANG URI` |
| `urls` | `ID open-url LEN` + URL, `ID external-uri LEN` + URI, `ID link` | `ok ID opened\|copied`; `ok ID LEN` + URI; `ok ID LEN` + `rhun://ext/OWNER/NAME/TOKEN` | `0 link ID LEN` + the link as it arrived |
| `idle` | `ID busy yes`, `ID busy no` | `ok ID` | |

- **watch**: events carry no paths; reconcile with disk (or `find-files`). Handles belong to one
  runtime; subscribe again after a restart or a project change. Never infer deletions from a
  partial scan.
- **files**: FOLDER `0` is every folder; FLAGS bits 1 ignored files too, 2 skip hidden, 4 follow
  folder links, 8 folders too (find), 16 ignore case, 32 whole words, 64 regex (an RNRX program,
  compiled by Go's `CompileSearchRegex`). Globs: lines `+GLOB` / `-GLOB` (`*`, `**`, `?`, `[a-z]`,
  `{a,b}`; no `/` means the base name at any depth). Batch records: find `FOLDER PATH_LEN` LF +
  PATH; search `FOLDER DOC VERSION PATH_LEN M` LF + PATH, then M `LINE COL END PRE TEXT_LEN` LF +
  TEXT. STATUS `complete`, `limit` or `partial`. One run per extension at a time (`busy`).
  `ID2 cancel ID` ends a run. Where git runs, `.gitignore` applies exactly as git applies it;
  unsaved text is searched instead of the file.
- **folders**: FLAGS 1 the primary, 2 trusted. `0 folders` comes after `0 features`, before
  `ready`. Adding a folder restarts an extension that has `project` access; `on =
  contains:Cargo.toml contains:*.cabal` starts one when a folder has such a file.
- **scoped settings**: `KEY.scope = user|workspace|folder`, `KEY.languages = yes`; values in
  `[owner/name]` sections of `.rhun/extensions.ini` as `setting.KEY` and `setting.KEY@LANG`.
  `0 setting KEY VALUE` keeps carrying the window value; ask `setting-get` for a folder or a
  language. FOLDER `0` is the window, LANG `-` none.
- **secrets**: KEY `[a-z0-9_.-]{1,64}`, a value 0-8192 bytes, 64 keys. Without `secrets = yes`:
  `needs secrets=yes`. Replies may wait for an unlock dialog.
- **uris**: `[provides] schemes = NAME NAME-x` (your extension's name or `NAME-something`; never
  `file untitled rhun http https mailto data git remote`). Virtual documents are read-only; the
  answer to `content` is `LANG_LEN TITLE_LEN TEXT_LEN` LF + the three (text at most 4 MiB).
- **urls**: `open-url` takes `http(s)` only and the user sees it; pass every URL the browser
  must reach (a loopback redirect, a page you serve) through `external-uri` first, so a remote
  window forwards it. A `link` is one-shot, ten minutes, at most 4 pending; append a path and
  query (`…/TOKEN/callback`). On Windows a link reaches only the rhun that made it: use a
  loopback redirect there.
- **idle**: with `idle = stop`, rhun stops the extension after `idle.after` seconds (10 to
  86400; 300 by default) without messages, unless it holds a prompt, a view, marks, status text,
  an unanswered request or `busy yes`. It starts again on its next command, provider request or
  `lang:`/`open:`/`contains:` activation; `on = startup` and `on = project` do not fire again.

## SDK

| Feature | Rust (`rhun_ext`) | Go (`rhunext`) | C (`rhunext.h`) |
| --- | --- | --- | --- |
| watch | `Ext::watch_workspace`, `unwatch_workspace`, `parse_workspace_watch(ev)` → `(WorkspaceWatch, WorkspaceWatchEvent::Changed\|Rescan)` | `WatchWorkspace[Context]`, `UnwatchWorkspace[Context]`, `ParseWorkspaceWatch(ev)` → `(watch, "changed"\|"rescan", ok)` | `rx_watch_workspace`, `rx_unwatch_workspace`, `rx_parse_workspace_watch(ev, &watch, &rescan)` |
| files | `Ext::find_files(&FileQuery, \|batch\| bool)`, `Ext::search_text(&Pattern, &FileQuery, \|batch\| bool)` → `files::Finished`; `files::{FileQuery, Pattern::Literal\|Program, FoundPath, FoundFile, SearchMatch}` | `FindFilesContext(ctx, FileQuery, func([]FoundPath) bool)`, `SearchTextContext(ctx, Pattern{Literal \| Program}, q, func([]FoundFile) bool)` → `Finished`; `CompileSearchRegex(source, options)` | `rx_find_files(ext, &q, batch, user, &fin)`, `rx_search_text(ext, pat, len, regex, &q, batch, user, &fin)`; `rx_file_query`, `RX_FILES_*`, `RX_SEARCH_*` |
| folders | `parse_folders(ev)` → `Vec<Folder>`, `Ext::folder_of(path)` | `ParseFolders(ev)`, `FolderOfContext(ctx, path)` | `rx_parse_folders(ev, out, max)`, `rx_folder_of(ext, path)` |
| scoped settings | `Ext::setting_get(key, folder, lang)` | `SettingGetContext(ctx, key, folder, lang)`, `ParseSettingChanged(ev)` | `rx_setting_get(ext, key, folder, lang)` (malloc'd) |
| secrets | `Ext::secret_get` → `Option<Vec<u8>>`, `secret_set`, `secret_delete`, `secret_keys` | `SecretGetContext` → `(value, found, err)`, `SecretSetContext`, `SecretDeleteContext`, `SecretKeysContext` | `rx_secret_get(ext, key, &value, &len)`, `rx_secret_set`, `rx_secret_delete`, `rx_secret_keys` |
| uris | `Handler::content(ext, uri)` → `Result<Content{lang, title, text}, String>`, `Handler::content_closed`, `Ext::open_uri(uri, Pos)`, `Ext::content_changed(uri)`, `rhun_ext::resources::valid_uri` | a handler implementing `ContentProvider` (`Content(ext, uri) (Content, error)`), `OpenURIContext`, `ContentChangedContext`, `ParseContentClosed(ev)`, `ValidURI` | `rx_handlers.content` (fills `rx_content`), `rx_handlers.content_closed`, `rx_open(ext, uri, at)`, `rx_content_changed`, `rx_uri_valid` |
| urls | `Ext::open_url` → `UrlOpened::Opened\|Copied`, `external_uri`, `link`, `parse_link(ev)`; `rhun_ext::auth::{Pkce, Loopback, random_hex, percent_encode, parse_query}` | `OpenURLContext` → `(copied, err)`, `ExternalURIContext`, `LinkContext`, `ParseLink(ev)`; `NewPKCE()`, `ListenLoopback()` (`RedirectURI`, `Wait(ctx, state)`), `RandomHex` | `rx_open_url`, `rx_external_uri`, `rx_link`, `rx_parse_link`, `rx_handlers.link`; with `#define RHUNEXT_AUTH`: `rx_pkce_new`, `rx_loopback_listen`, `rx_loopback_wait`, `rx_query_get`, `rx_random_hex` |
| idle | `Ext::busy(bool)` | `BusyContext(ctx, bool)` | `rx_busy(ext, 1\|0)` |

Features: Rust `Feature::WorkspaceWatch`, `Files`, `WorkspaceFolders`, `ScopedSettings`,
`Secrets`, `Uris`, `Urls`, `Idle`; Go `FeatureWorkspaceWatch`, `FeatureFiles`,
`FeatureWorkspaceFolders`, `FeatureScopedSettings`, `FeatureSecrets`, `FeatureURIs`,
`FeatureURLs`, `FeatureIdle`; C the names as strings in `rx_run`. Every call checks agreement
first and fails with `unknown` locally when rhun did not agree.

## Example (Rust): a token kept in the keychain, a project scan

```rust
use rhun_ext::files::{FileQuery, Pattern};
use rhun_ext::{parse_workspace_watch, run, Event, Ext, Feature, Handler};

struct Todo;
impl Handler for Todo {
    fn ready(&mut self, ext: &Ext, _project: Option<&str>) {
        let _ = ext.watch_workspace();
        if ext.secret_get("token").ok().flatten().is_none() {
            let _ = ext.secret_set("token", b"from a sign-in");
        }
        scan(ext);
    }
    fn event(&mut self, ext: &Ext, ev: &Event) {
        if parse_workspace_watch(ev).is_some() {
            scan(ext); // changed or rescan: no paths, reconcile
        }
    }
}

fn scan(ext: &Ext) {
    let q = FileQuery { folder: 0, max: 2000, include: vec!["*.rs".into()], ..Default::default() };
    let mut hits = 0;
    let done = ext.search_text(&Pattern::Literal("TODO".into()), &q, |files| {
        hits += files.iter().map(|f| f.matches.len()).sum::<usize>();
        true // false cancels the run
    });
    eprintln!("todo: {hits} matches, {:?}", done.map(|f| f.status));
}

fn main() {
    let f = [Feature::WorkspaceWatch, Feature::Files, Feature::Secrets];
    if let Err(e) = run(&f, Todo) { eprintln!("todo: {e}"); }
}
```

Manifest: `[needs] project = read` and `secrets = yes`. Real extension: `rhun-editor/lsp`
(branch rhun-0.18) agrees `workspace_watch` (for its servers' file watchers) and
`workspace-folders`.

## Signing in (OAuth with PKCE)

Listen on `127.0.0.1:0` (`Loopback::bind` / `ListenLoopback` / `rx_loopback_listen`), pass its
redirect URI through `external-uri`, open the provider's authorize URL (with `state`,
`code_challenge`, `code_challenge_method=S256`) with `open-url`, wait for the redirect's `code`
and `state`, exchange the code with the verifier and keep the token with `secret-set`. The
listener and the exchange need `[needs] network = yes`. A provider that cannot redirect to a
loopback address takes a `link` instead.

## Headless

| Control | Shows or does |
| --- | --- |
| `secret-backend system\|memory\|file` | where this session keeps secrets: use `memory` in tests, never the user's keychain |
| `print-secrets OWNER/NAME` | `backend=B keys=a,b` (never values); `secrets-refresh`, `secret-forget OWNER/NAME [KEY]` |
| `print-vdocs` | `vdoc doc=ID uri=URI provider=OWNER/NAME state=S name=N` per virtual document |
| `link-deliver URL`, `print-links` | a `rhun://ext/…` link as if the system opened it; the links pending |
| `folder-add PATH`, `folder-remove ID\|PATH`, `print-folders` | workspace folders: `folder=ID name=N path=P flags=F` per line |
| `print-ext-setting OWNER/NAME KEY FOLDER LANG` | what `setting-get` answers |
| `print-file-runs` | the find-files and search-text runs going on |
| `print-ext-cost OWNER/NAME`, `ext-set NAME stop\|restart` | messages, CPU, memory, state; idle stops |

In a `--extensions` session `RHUN_IDLE_SCALE=N` divides `idle.after` by N (1 to 100000), so a
test sees an idle stop in milliseconds; `RHUN_OPEN_URL=PROGRAM` runs that program with the URL
instead of the browser. The checker serves `find-files` from its scratch project (RNRX searches
find nothing), keeps secrets in memory, sends its project as the one folder and answers the
other requests of these features.

## Pitfalls

- `workspace_watch` is the only feature name with an underscore; `workspace-watch` is not agreed.
- Watch events say only that something may have changed: no paths, and they may repeat.
- `find-files` and `search-text` report through batches before the final `ok`; a Go or Rust
  callback that blocks on another request to rhun is fine (they are framed), but keep it short.
- A `rhun://` folder that is not trusted contributes no workspace settings and pauses git;
  never give `workspace` or `folder` scope to a setting that names a program, a path or arguments.
- A secret's value never goes to a log, a toast or a test's output.
- `idle = stop` without `busy yes` around invisible work (indexing, a download) gets the
  extension stopped mid-way.
