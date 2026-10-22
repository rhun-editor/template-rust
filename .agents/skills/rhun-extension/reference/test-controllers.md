# Test controllers (protocol 1.1)

A test controller publishes a tree of test items; rhun keeps it, shows it in the Testing section
and the gutter, starts the runs the user asks for and stores their results, failure messages
(with expected and actual values), output and line coverage. The controller runs its tests by
asking rhun to start a program as the user (`test-exec`). `hello 1 tests` (plus `debug` for the
debug profile); manifest `[provides] tests`, `tests.profiles`, `[needs] tests`. Spec: v1.1.md
"Feature: `tests`" ("Manifest", "Items", "Messages", "Results body", "Coverage body", "Running
programs as the user: `test-exec`"),
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. Example:
`rhun-editor/tests` (Go, branch rhun-0.18): Go and Rust tests, `go test -json` and `cargo test`
through `test-exec`, coverage, and Debug through its own `[debugger.go-test]` (debug.md). This
file is about writing a controller; `testing.md` is about testing your extension.

## Manifest

```ini
[provides]
# files it has tests in: it gets opened/edits for them as a provider, and starts when one opens,
# when Testing is shown, or when a test command runs
tests = *_test.go *.rs
# run kinds besides run: debug, coverage
tests.profiles = run debug coverage

[needs]
documents = read
project = read
# programs rhun may start as the user during runs the user started: bare names, at most 16
tests = go cargo
```

## Items

```
PARENT_LEN N LF <PARENT>
N items: KIND L1 C1 L2 C2 FLAGS ID_LEN LABEL_LEN PATH_LEN EXTRA_LEN LF <ID><LABEL><PATH><EXTRA>
```

PARENT empty: the roots. KIND `group` (module, package, crate, folder), `file`, `suite`, `test`.
`0 0 0 0` for no range; a range needs a PATH (absolute, or `#DOC`). FLAGS `-` or a comma list of
`lazy` (rhun asks `tests-resolve` when it is expanded) and `nodebug`. ID: 1-512 bytes, no LF, CR
or NUL, unique in the extension and **stable across sessions** (results and expansion follow it).
LABEL one line, 200 bytes. EXTRA: `desc LEN` (dim text), `error LEN` (a discovery problem on the
row). A body applies whole or not at all; at most 10,000 items and 4 MiB a body, 50,000 per
extension.

## Messages

| Direction | Message | Reply |
| --- | --- | --- |
| rhun → ext | `ID tests-resolve LEN` + PARENT id (empty: the roots) | `ok ID LEN` + items for PARENT (replaces its children, clears `lazy`); an error's TEXT shows on the row; 30 s |
| ext → rhun | `ID test-items replace\|add LEN` + items | `ok ID` |
| ext → rhun | `ID test-remove N LEN` + N ids, each + LF | `ok ID` |
| rhun → ext | `ID test-run RUN PROFILE N LEN` + N ids + LF (N 0: everything) | `ok ID 0` at once, or `error ID busy\|refused TEXT` |
| ext → rhun | `ID test-update RUN LEN` + results | `ok ID`; `error ID stale run over` once it ended |
| ext → rhun | `ID test-coverage RUN LEN` + coverage | `ok ID` (merged; a new run's first replaces old coverage) |
| ext → rhun | `ID test-end RUN` | `ok ID` |
| rhun → ext | `0 test-cancel RUN` | stop, then send `test-end` |
| ext → rhun | `ID test-exec RUN LEN` + command | `ok ID EXEC` |
| rhun → ext | `0 test-out EXEC out\|err LEN` + bytes, `0 test-exit EXEC CODE` | CODE an exit status, `signal N` or `killed` |

Results body (1 MiB, 2,000 records): `N` LF, then `STATE MS ITEM_LEN EXTRA_LEN` LF + ITEM +
EXTRA. STATE `queued started passed failed errored skipped` or `-` (output only); MS or `-`;
ITEM empty is the run itself (`-` or `errored`, a failed build). EXTRA in order: `message LEN`
(starts a message, 8,000 bytes, 16 per item), `location L1 C1 L2 C2 LEN` + PATH, `expected LEN`,
`actual LEN` (64 KiB each: rhun shows a diff), `output LEN` (appended). Coverage body: `N` LF,
then per file `PATH_LEN M` LF + PATH and M lines `L1 L2 COUNT` (one-based, inclusive, as the file
was when the run started).

Command body for `test-exec` (256 KiB, no NUL): `PROGRAM_LEN CWD_LEN ARGC ENVC` LF + PROGRAM +
CWD, then ARGC `LEN` LF + argument and ENVC `LEN` LF + `NAME=VALUE`. rhun checks, in order: the
folder is trusted (`refused folder not trusted`), the body (`syntax`, `toobig`: 1,000 arguments,
64 variables), PROGRAM a bare name (`refused the program must be a bare name`), a word of
`[needs] tests` (`needs tests=NAME`), fewer than 4 live processes in the run and 8 in all
(`busy`), the user's one-time approval per extension and project (`cancelled`), PROGRAM on the
user's PATH (`nofile`), CWD inside the project (`refused`). The program gets the user's
environment plus ENV, input from the null device, its own process group; Cancel stops it after
2 s.

## SDK

| | Rust | Go | C |
| --- | --- | --- | --- |
| feature | `Feature::Tests` | `FeatureTests` | `"tests"` |
| handler | `Handler::resolve_tests(&ext, parent) -> Result<Vec<TestItem>, Error>`, `run_tests(&ext, &TestRun) -> Result<(), Error>`, `cancel_tests(&ext, run)` | `TestController`: `ResolveTests`, `RunTests`, `CancelTests` | `rx_handlers.resolve_tests` (`rx_test_item`, `rx_test_refuse`), `run_tests` (NULL or `"CODE TEXT"`), `cancel_tests`, `test_out`, `test_exit` |
| items | `TestItem::new(TestKind::Test, id, label).at(path, Some(range)).lazy()`; fields `nodebug`, `desc`, `error` | `TestItem{ID, Label, Kind: TestCase, Path, Range, Lazy, NoDebug, Desc, Error}` | `rx_test_item(l, kind, id, label, path, &range, flags, desc, error)` |
| publish | `ext.set_test_items(parent, &items, replace)`, `remove_test_items(&ids)` | `SetTestItems(parent, items, replace)`, `RemoveTestItems(ids...)` | `rx_test_items_send`, `rx_test_remove` |
| results | `TestReporter::new(&ext, run)` (`add`, `add_items`, `flush`, `close`); `TestResult::new(item, TestState::Failed).took(d).message(TestMessage::new(t).at(path, range).values(exp, act))`, `TestResult::output(item, bytes)`; `ext.report_tests` | `NewTestReporter(ext, run)` (`Add`, `AddItems`, `Flush`, `Close`); `TestResult{Item, State, Duration, Messages, Output}` (`NoDuration`); `ReportTests` | `rx_test_result`, `rx_test_message`, `rx_test_location`, `rx_test_expected`, `rx_test_actual`, `rx_test_output`, `rx_test_update` |
| coverage | `ext.report_coverage(run, &[FileCoverage{path, ranges: vec![CoverageRange{from, to, count}]}])` | `ReportCoverage(run, []FileCoverage)` | `rx_coverage_file`, `rx_coverage_lines`, `rx_test_coverage_send` |
| end | `ext.end_test_run(run)` | `EndTestRun(run)` | `rx_test_end` |
| exec | `ext.test_exec(run, &TestCommand::new("cargo").args([...]).dir(d).env("K=V"))` → `TestProcess{stdout, stderr}` (`Read`), `wait()`, `exit_code()` | `TestExec(run, TestCommand{Program, Dir, Args, Env})` → `*TestProcess{Stdout, Stderr}`, `Wait`, `ExitCode` | `rx_test_exec` → EXEC; output in `test_out`, end in `test_exit` |
| values | `expected_actual(text)`, `unquote` | `ExpectedActual(text)`, `Unquote` | |

`TestReporter` batches results and sends them from a thread of its own every 100 ms, so the code
reading a test program's output never waits for rhun.

```rust
use std::io::{BufRead, BufReader};
use rhun_ext::{run, Error, Ext, Feature, Handler, Pos, Range, TestCommand, TestItem, TestKind,
    TestMessage, TestReporter, TestResult, TestRun, TestState};

struct Tests;
impl Handler for Tests {
    fn resolve_tests(&mut self, _ext: &Ext, parent: &str) -> Result<Vec<TestItem>, Error> {
        if !parent.is_empty() { return Ok(Vec::new()); }
        let range = Range::new(Pos::new(3, 1), Pos::new(6, 2));
        Ok(vec![TestItem::new(TestKind::Test, "add", "test_add").at("/abs/project/src/lib.rs", Some(range))])
    }
    fn run_tests(&mut self, ext: &Ext, run: &TestRun) -> Result<(), Error> {
        let (ext, id) = (ext.clone(), run.run); // return at once; work on a thread
        std::thread::spawn(move || {
            let rep = TestReporter::new(&ext, id);
            rep.add(TestResult::new("add", TestState::Started));
            match ext.test_exec(id, &TestCommand::new("cargo").args(["test", "--", "test_add"])) {
                Ok(mut p) => {
                    std::thread::scope(|s| {
                        // drain stderr too: an unread stream stalls everything rhun sends
                        s.spawn(|| std::io::copy(&mut p.stderr, &mut std::io::sink()));
                        for line in BufReader::new(&mut p.stdout).lines().map_while(Result::ok) {
                            rep.add(TestResult::output("add", format!("{line}\n")));
                        }
                    });
                    let ok = p.exit_code() == 0;
                    rep.add(TestResult::new("add", if ok { TestState::Passed } else { TestState::Failed }));
                }
                Err(e) => rep.add(TestResult::new("", TestState::Errored).message(TestMessage::new(e.text))),
            }
            let _ = rep.close();
            let _ = ext.end_test_run(id);
        });
        Ok(())
    }
}
fn main() { let _ = run(&[Feature::Tests], Tests); }
```

## Testing it

The checker resolves the roots and one lazy level, runs each profile the manifest offers and
cancels a run, checking every body as rhun reads it. It refuses `test-exec` unless given
`-test-exec-script FILE` (lines `out TEXT`, `err TEXT`, `sleep MS`, `exit CODE`); `-test-timeout`
bounds a run (default 60s): `rhun-ext-check -test-exec-script play.txt DIR`.

Headless rhun: `cmd testing`, `cmd test_run_all`, `cmd test_coverage_all` (and the other `test_*`
commands), `wait-test-items N`, `wait-tests`, `test-select OWNER/NAME [ID]`, `test-expand` /
`test-collapse OWNER/NAME [ID]`, `test-action run|debug|coverage|cancel|goto|failure|diff|output`,
`print-tests [all]`, `print-test-result OWNER/NAME ID`, `print-test-runs`, `print-coverage PATH`,
`print-testing`, `print-gutter`, `test-gutter LINE [right]`, `print-problems`. The first
`test-exec` in a project asks: answer with `print-dialog` / `dialog yes`.

## Pitfalls

- `run_tests` / `RunTests` must return at once: report from a thread or goroutine, and always
  end with `test-end`, also after an error or a cancel (rhun ends a cancelled run itself after
  5 s). Results after the end are `stale run over`.
- Read **both** `stdout` and `stderr` of a `TestProcess`: rhun stops sending output that is not
  read, and the reader thread waits while a stream holds 1 MiB.
- IDs must be stable across sessions and edits (package path plus test name), never line
  numbers; ranges are the file as you read it (rhun moves them through later edits).
- `test-exec` takes a bare program name listed in `[needs] tests`, never a path or a shell line;
  pass flags as arguments. A folder opened from a `rhun://` link runs nothing until trusted.
- The debug profile starts a session with `debug-start` (needs `debug` agreed and `[needs]
  debug = yes`); its `debug-ended` exit code is the test's result. Refuse the profile when
  `debug` was not agreed (`rhun-editor/tests` does).
- Runs are concurrent (4 per extension, 8 in all) and may share items; key state by RUN.
