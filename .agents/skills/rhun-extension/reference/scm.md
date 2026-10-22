# Source control (protocol 1.1)

Four features, each listed in `hello 1 ...` and used only after rhun says it back in
`0 features`: `git-data` (read the project's Git data through rhun; `[needs] git = read`),
`commit-message` (`[provides] commit_message = yes`), `quickdiff` (`[provides] quickdiff =
PATTERNS`) and `scm` (a version control panel of your own; no manifest key). Panel buttons and
clicks run command references, so a panel also wants `command-args`. Spec sections "Source
control", "Feature: `git-data`", "Feature: `commit-message`", "Feature: `quickdiff`", "Menus on
source control rows" and "Feature: `scm`" of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. Examples:
`rhun-editor/blame` (git-data, Rust), `rhun-editor/hg` (scm panel and quickdiff, Go).

## git-data: Git through rhun

Never run `git` yourself for status, blame or history: rhun runs it in the background, keeps the
trust pause of a folder a `rhun://` link opened, and answers every request below. Each needs
`git = read` (else `needs git=read`) and the agreed feature (else `unknown`).

| Request | Reply body |
| --- | --- |
| `ID git-repo` | `ROOT_LEN BRANCH_LEN UPSTREAM_LEN HEAD AHEAD BEHIND STATE` LF `<ROOT><BRANCH><UPSTREAM>` |
| `ID git-status` | `N` LF, then N × `XY PATH_LEN` LF `<PATH>` |
| `ID git-blame DOC` | `NC NR` LF, NC × `SHA TIME AUTHOR_LEN MAIL_LEN SUMMARY_LEN` LF + strings, NR × `SHA L1 L2 ORIG_L1` LF |
| `ID git-log MAX L1 L2 LEN` + path | `N` LF, then N × `SHA PARENTS TIME AUTHOR_LEN SUBJECT_LEN` LF `<AUTHOR><SUBJECT>` |
| `ID git-show REV LEN` + path | the file's stored bytes at REV (at most 4 MiB) |
| `ID git-diff-open REV1 REV2 LEN` + path | none (`ok ID`); rhun's read-only diff tab opens when git answers |
| event `0 git changed` | no data: the status, branch, HEAD, upstream or counts changed; ask again |

- HEAD is `branch`, `detached` or `unborn`; STATE `clean`, `dirty`, `merging` or `rebasing`.
  XY are porcelain's columns with `.` for an unchanged side (`.M`, `M.`, `??`, `UU`); PATH is
  relative to ROOT, an untracked folder ends in `/`.
- Blame is of the open document's **current text**: unsaved or uncommitted lines carry the zero
  SHA (all `0`s). A file not committed yet is `nofile`; over 100,000 lines or 16 MiB is `toobig`.
- `git-log`: `0 0` and a path: the file's commits (following renames); `L1 L2` (1 ≤ L1 ≤ L2):
  `git log -L` of those lines at HEAD; LEN 0 and `0 0`: the history of HEAD. MAX is 1 to 1000.
  PARENTS are SHAs joined by `,`, `-` for a root commit.
- REV: 1 to 200 bytes of letters, digits and `. _ / ~ ^ @ { } + -`, not starting with `-`
  (`HEAD~2`, a SHA, `main@{1}`); REV2 `-` is the work tree. A path is absolute inside the work
  tree or relative to ROOT, at most 4095 bytes; a `..` segment or a path outside is `nofile`.
- Errors: `refused git is paused in this folder`, `refused git is off`, `nofile not in a Git
  repository`, `busy too many Git requests` (16 waiting per extension, 64 in all), `cancelled git
  took longer than 15 seconds`, `cancelled the project changed`.

| | Rust (`Feature::GitData`) | Go (`FeatureGitData`) | C (`"git-data"`) |
| --- | --- | --- | --- |
| repo, status | `ext.git_repo()` → `GitRepo`, `ext.git_status()` → `Vec<GitStatusEntry>` | `ext.GitRepo(ctx)`, `ext.GitStatus(ctx)` | `rx_git_repo`, `rx_git_status` (`rx_git_repo_free`, `rx_git_status_free`) |
| blame | `ext.git_blame(doc)` → `Blame` (`.line(n)`), `scm::is_uncommitted` | `ext.GitBlame(ctx, doc)`, `Blame.Line`, `IsUncommitted` | `rx_git_blame` → `rx_blame` (`rx_blame_free`) |
| log | `ext.git_log(LogOf::Head \| File(p) \| Lines(p, l1, l2), max)` | `ext.GitLog(ctx, path, l1, l2, max)` | `rx_git_log(ext, path, l1, l2, max, &log)` (`rx_log_free`) |
| show, diff | `ext.git_show(rev, path)`, `ext.git_diff_open(rev1, Some(rev2) \| None, path)` | `ext.GitShow`, `ext.GitDiffOpen(ctx, rev1, rev2 or "", path)` | `rx_git_show`, `rx_git_diff_open` (rev2 NULL: work tree) |
| the event | `scm::is_git_changed(ev)` | `rhunext.IsGitChanged(ev)` | `rx_is_git_changed(ev)` |
| REV check | `scm::valid_rev` | `ValidRev` | `rx_valid_rev` |

`rhun-editor/blame` asks `git_blame` on `opened`/`changed` and the cursor, and shows the line's
author as a decoration's after-text (see `presentation.md`).

## commit-message: the Generate button

`[provides] commit_message = yes` and `commit-message` in hello; no `[needs]`. The user picks the
provider in Settings > Git > Commit message AI (`commit_ai = ext:OWNER/NAME`) and clicks Generate:

```
← ID commit-message LEN        body: BRANCH_LEN DIFF_LEN LF <BRANCH><DIFF>
→ ok ID LEN + the message      or  error ID CODE TEXT (TEXT shown to the user)
```

The diff is the staged changes (else what Commit All would take), at most 16,000 bytes, then
`[Diff truncated to 16000 bytes.]`. rhun trims the message; it must be 1 to 8192 bytes with no
control characters but tab, CR and LF, or it is refused and the draft stays. rhun waits 5 s for
the start and 180 s for the answer; Cancel sends `0 cancel ID`. Rust `Handler::commit_message(&
CommitMessageRequest) -> Result<String, String>` (`req.branch`, `req.diff`, `req.id`); Go
`CommitMessageProvider.CommitMessage(ext, req)` (`req.Context` ends on cancel); C
`rx_handlers.commit_message` (append to `out`, return 1; -1 with the reason). Check with
`scm::check_commit_message` / `CheckCommitMessage` / `rx_check_commit_message`.

## quickdiff: the base of the gutter marks

`[provides] quickdiff = PATTERNS` (it hears `opened` for them) and `quickdiff` in hello.

```
← ID quickdiff DOC VERSION        → ok ID LEN + the base's bytes (≤ 4 MiB, CRLF allowed) | ok ID 0 (none)
→ ID quickdiff-refresh LEN + an absolute path or "-" (every open file it matches)   ← ok ID
```

rhun asks when a document opens, after it is saved, once when the provider starts, and on
`quickdiff-refresh`. A provider's bases apply only to files under a root it registered with
`scm-register`, or else to files outside git's work tree (or every file while git is off or
paused). Rust `Handler::quickdiff(&QuickDiffRequest) -> Option<Vec<u8>>`,
`ext.quickdiff_refresh(Some(path) | None)`; Go `QuickDiffProvider.QuickDiff(ext, req) ([]byte,
bool)`, `ext.QuickDiffRefresh(ctx, path or "")`; C `rx_handlers.quickdiff`,
`rx_quickdiff_refresh(ext, path or NULL)`.

## scm: a panel for another version control system

| Request | Reply |
| --- | --- |
| `ID scm-register LEN` + `ROOT_LEN LABEL_LEN` LF `<ROOT><LABEL>` | `ok ID SCM` (the same root again: the same SCM) |
| `ID scm-update SCM LEN` + body | `ok ID`; replaces everything the section shows |
| `ID scm-input SCM` | `ok ID LEN` + the message box's text |
| `ID scm-input-set SCM LEN` + text | `ok ID` (LEN 0 clears; at most 65,536 bytes) |

The `scm-update` body (its exact grammar is in the spec; let the SDK encode it):

```
STATUS_LEN PLACEHOLDER_LEN NACT NGROUP LF <STATUS><PLACEHOLDER>
NACT ×   action ICON NAME ARGS_LEN LABEL_LEN LF <ARGS><LABEL>          buttons (≤ 4; Ctrl+Enter runs the first)
NGROUP × group ID LABEL_LEN NACT NRES LF <LABEL>, its actions, its resources
res CODE COLOR PATH_LEN NREC LF <PATH>, then NREC records: command NAME ARGS_LEN LF <ARGS>
         (the click, first), action ... (its menu), tip LEN LF <TEXT>
```

An action or click sends `0 run EXT.NAME DOC ref LEN` + ARGS (with `command-args`), so NAME must
be one of the extension's own commands (`hg` hides them from the palette with
`[command-options] NAME.palette = no`). A resource without a `command` record opens a diff
against its quick-diff base. A placeholder shows the message box; CODE is one letter (`M A D ? !`),
COLOR `added modified deleted conflict untracked ignored -`. Limits: 4 buttons, 64 groups, 8
actions per group or resource, 10,000 resources, 4 MB, 4 providers per extension; a bad body is
`syntax` and the section keeps what it had. Its sections go when the extension stops.

```rust
use rhun_ext::{run, Ext, Feature, Handler, Invocation, QuickDiffRequest, ScmAction, ScmGroup, ScmPanel, ScmResource};

#[derive(Default)]
struct Vcs { scm: u64 }

impl Handler for Vcs {
    fn ready(&mut self, ext: &Ext, project: Option<&str>) {
        let Some(root) = project else { return };
        self.scm = ext.scm_register(root, "Mercurial").unwrap_or(0);
        let mut res = ScmResource { path: "a.txt".into(), code: b'M', color: "modified".into(), ..Default::default() };
        res.actions.push(ScmAction::new("revert", "Revert File").icon("discard").args(b"a.txt"));
        let panel = ScmPanel {
            status: "default".into(),
            placeholder: "Message (Ctrl+Enter to commit)".into(),
            actions: vec![ScmAction::new("commit", "Commit").icon("check")],
            groups: vec![ScmGroup { id: "changes".into(), label: "Changes".into(), resources: vec![res], ..Default::default() }],
        };
        if let Err(e) = ext.scm_update(self.scm, &panel) { eprintln!("scm-update: {e}"); }
    }
    fn invoke(&mut self, ext: &Ext, inv: &Invocation) {
        match inv.name.as_str() {
            "commit" => { let msg = ext.scm_input(self.scm).unwrap_or_default(); let _ = ext.scm_input_set(self.scm, ""); eprintln!("commit {msg}"); }
            "revert" => eprintln!("revert {}", String::from_utf8_lossy(&inv.body)), // ARGS: a.txt
            _ => {}
        }
    }
    fn quickdiff(&mut self, _ext: &Ext, _req: &QuickDiffRequest) -> Option<Vec<u8>> { Some(b"base\n".to_vec()) }
}

fn main() {
    let _ = run(&[Feature::Scm, Feature::CommandArgs, Feature::QuickDiff], Vcs::default());
}
```

Manifest: `[commands] commit = Commit`, `revert = Revert File`, `[provides] quickdiff = *`,
`[needs] run = hg` (the panel's tool runs as the extension, in its sandbox). Go: `ext.ScmRegister
(ctx, root, label)`, `ext.ScmUpdate(ctx, scm, ScmPanel{...})` (`ScmAction{Icon, Command, Args,
Label}`, `ScmResource{Path, Code, Color, Click, Actions, Tip}`, `ScmGroup{ID, Label, Actions,
Resources}`), `ext.ScmInput`, `ext.ScmInputSet`. C: `rx_scm_register`, then a body built in order
with `rx_scm_head`, `rx_scm_action`, `rx_scm_group`, `rx_scm_res`, `rx_scm_click`, `rx_scm_tip`,
sent with `rx_scm_update`; `rx_scm_input`, `rx_scm_input_set`.

## Menus on source control rows

Manifest `[menu.history_commit]`, `[menu.history_file]`, `[menu.scm_resource]`,
`[menu.scm_group]` and `[menu.scm_title]` (header icon buttons, at most 3 then `…`), as in
`contributions.md`. With `command-args` the body's first line is the target:

| Location | TARGET |
| --- | --- |
| `history_commit` | `commit SHA` |
| `history_file` | `commit SHA PATH` |
| `scm_resource` | `resource GROUP PATH` (git's GROUP: `merge`, `staged`, `changes`) |
| `scm_group` | `group GROUP` |
| `scm_title` | `scm OWNER/NAME ROOT` or `scm git ROOT` (`targetKind` `scm`) |

When clauses read `scmProvider` (`git` or `OWNER/NAME`), `scmResourceGroup`,
`scmResourceStatus` (`M A D R C U`) and `gitTrusted`: `when = scmProvider == git` puts a
`scm_title` button on git's header only. PATH is relative to the work tree.

## Testing headless

`print-git-data` (`git-data pending=N`), `wait-git`, `print-scm-ext` (each provider: `scm SCM
OWNER/NAME ROOT label=… status=… input=… actions=…` and its rows; the commit-message provider and
the last source control menu's target), `scm-click SCM GROUP PATH`, `scm-action SCM N` (from 0),
`scm-menu SCM GROUP [PATH]` then `menu-pick LABEL`, `scm-focus SCM` then `type`, `print-vcs PATH`
(`vcs=LETTER dir=0|1 color=RRGGBB`), `wait-scm SCM [TEXT]`, `wait-quickdiff`. The checker plays
`git-data` and `scm` requests and asks `commit-message` and `quickdiff`; it fails `git-data`
without `git = read`.

## Pitfalls

- `0 git changed` carries nothing and is sent only to running extensions: ask `git-repo` and
  `git-status` again, and once at start.
- A git-data request waits while a status refresh runs; do not ask per keystroke.
- Quick-diff bases for files inside git's work tree are ignored unless you registered a root
  that holds them.
- `scm-update` replaces the whole section; resend everything, not a delta.
- Without `command-args` a button runs v1's `0 run EXT.NAME DOC` without its ARGS.
- `rhun-ext-check` 1.4.0 failed a manifest with `[menu.scm_title]` ("unknown menu location");
  1.4.1 accepts it, as rhun 0.18 does.
