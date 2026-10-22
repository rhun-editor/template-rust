# Terminals and tasks (protocol 1.1)

Programs in terminal tabs of rhun's panel (feature `terminals`) and published tasks that rhun
lists, runs with their dependencies and turns into problems (feature `tasks`, agreed only together
with `terminals`): `hello 1 terminals tasks`. Manifest: `[needs] terminal = run` (or `input`,
`output`). Spec: v1.1.md "Terminals and tasks" ("Manifest: `terminal`", "Definitions", "Feature:
`terminals`", "Feature: `tasks`", "Problem patterns and matchers", "Errors and limits"),
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. Example:
`rhun-editor/tasks` (Go, branch rhun-0.18): finds make targets, npm scripts, Cargo and Go builds
and `.rhun/tasks.ini`, publishes them with built-in matchers.

## Permission and approval

`[needs] terminal` is a ladder; each level includes the ones before it:

| Value | Grants |
| --- | --- |
| `no` (default) | nothing |
| `suggest` (= v1's `yes`) | `term`: propose a line the user runs with Enter |
| `run` | also start programs in terminal tabs (`terminal-*`, `tasks-set`, `task-*`); v1's `cmd` also takes `run_task`, `run_build_task`, `run_test_task`, `rerun_last_task`, `restart_task`, `stop_task`, `show_task` |
| `input` | also `terminal-input` into its own terminals |
| `output` | also `terminal-screen` and `terminal-output` events (the user's typing included) |

Programs run as the user, outside the sandbox, with the user's environment (rhun's own, or the
login shell's) plus `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=rhun` and the
definition's `env`/`unset`. The first start in a project (`terminal-open`, `terminal-restart`,
`task-start`, `task-run`, or the user picking one of its tasks) asks "Let TITLE run programs in
PROJECT?" showing the command; the request's reply waits for the answer (Cancel: `cancelled`).
Allow is remembered per extension and project (`allow_run` in `extensions.ini`, Forget on its
page); `test-exec` and debug adapters share it. A 1.0 host reads `run`, `input`, `output` as `no`.

## Definitions

`terminal-open`, `tasks-set` and `task-run` carry definitions:

```
TASK_ID FORM LABEL_LEN CMD_LEN CWD_LEN EXTRA_LEN LF <LABEL><CMD><CWD><EXTRA>
```

- `TASK_ID`: `[a-z0-9_.-]{1,64}` from a letter or digit, unique in a list; `-` in `terminal-open`.
- `FORM shell`: CMD (1-4096 bytes) runs as `/bin/sh -c CMD` or `powershell.exe -NoLogo -NoProfile
  -Command CMD`; empty only in `terminal-open` (the user's shell). `FORM argv`: 1-64 arguments,
  each followed by a NUL, 32768 bytes in all; the first is looked up on PATH without a slash.
- `LABEL` 1-128 bytes (tab title, list label). `CWD` empty: the project (home without one);
  relative: inside the project; absolute as given; it must exist.
- EXTRA records `NAME ARGS LEN LF` + bytes, any order, unknown skipped: `detail LEN`, `env NAME
  LEN`, `unset NAME 0`, `reveal show|focus|silent 0`, `output 0` (needs `output`), `location local
  0`; tasks only: `group build|test 0`, `default 0`, `depends sequence|parallel LEN` (1-16 ids of
  the same list), `matcher NAME 0` / `matcher - LEN` (at most 4), `ready LEN` and `busy LEN` (1-8
  patterns, one a line: a background task is done for its dependents when a line matches
  `ready`; `busy`, which needs `ready`, starts a new cycle and clears its problems).

## Feature `terminals`

| Request | Reply | Needs |
| --- | --- | --- |
| `ID terminal-open LEN` + definition | `ok ID TERM` | run |
| `ID terminal-stop TERM` | `ok ID` (Ctrl+C; the tree killed 2 s later) | run |
| `ID terminal-restart TERM` / `terminal-close TERM` | `ok ID` | run |
| `ID terminal-show TERM show\|focus` | `ok ID` | run |
| `ID terminal-input TERM LEN` + bytes | `ok ID` (as typed, LF is Enter, 64 KiB) | input |
| `ID terminal-screen TERM` | `ok ID LEN` + `ROWS COLS CURSOR_ROW CURSOR_COL` LF + rows | output |

Events: `0 terminal-started TERM PID TASK_ID` (`-` for a terminal; again at each restart), `0
terminal-ended TERM REASON CODE ERRORS WARNINGS` (REASON `exit`, `stopped`, `failed` with CODE
`-`), `0 terminal-output TERM DROPPED LEN` + finished lines (only with `output 0`), `0
terminal-closed TERM`. A TERM is never reused; a task keeps its TERM across runs while its tab is
open. An extension addresses only terminals it opened or that run its tasks, in its current
runtime (else `noterm`).

## Feature `tasks`

| Request | Reply | Effect |
| --- | --- | --- |
| `ID tasks-set LEN` + `N` LF + N definitions | `ok ID` | replaces its published tasks, checked whole first |
| `ID task-start TASK_ID` | `ok ID TERM` | runs a published task after its dependencies (`notask`) |
| `ID task-run LEN` + definition | `ok ID TERM` | runs an unpublished task; `busy` while one with its id runs |

Events: `0 task-ready TERM ERRORS WARNINGS`, `0 task-busy TERM`. `sequence a b` runs a, then b,
then the task; `parallel a b` runs them together. A dependency is done at exit 0 (a background
task: when ready); a failure marks dependents `── not run: build failed ──`. Published tasks stay
across a crash and an idle stop; they go when the user stops, disables or removes the extension
or the project changes. rhun's commands: Run Task, Run Build Task (ctrl+shift+B: the build
group's `default`), Run Test Task, Re-run Last Task, Restart Task, Stop Task, Show Task, Clear
Task Problems. Launch configurations run tasks by label or id (`before = TASK`, debug.md).

## Problem patterns and matchers

A pattern is one line (1-512 bytes) matched against a whole terminal line: fields `{file}`
`{line}` `{col}` `{endline}` `{endcol}` `{severity}` `{code}` `{message}` (each at most once) and
`{_}` (any text); `{{` `}}` are braces; a run of spaces matches one or more blanks. `{severity}`
takes `error`, `fatal error`, `fatal`, `warning`, `warn`, `info`, `note`, `hint`, `help`. An inline
matcher (at most 4096 bytes):

```
severity error
columns bytes
1 {file}:{line}:{col}: {message}
2  at {_}
loop
```

Step 1 is tried on every line; step k+1 must match the next line. The last step makes a problem
when `{file}` and `{message}` were captured. Built-ins: `go`, `gcc` (gcc, clang), `rustc` (rustc,
cargo), `tsc`, `msbuild`. Problems go to the Problems tab with the task's label as source; a run
replaces its task's problems.

## SDK

| | Rust (`rhun_ext::tasks`) | Go (`rhunext`) | C (`rhunext.h`) |
| --- | --- | --- | --- |
| feature | `Feature::Terminals`, `Feature::Tasks` | `FeatureTerminals`, `FeatureTasks` | `"terminals tasks"` |
| what runs | `Program::shell`, `Program::argv` (`cwd`, `env`, `unset`) | `Program{Shell or Argv, Cwd, Env []EnvVar, Unset}` | `rx_program` (`shell` or NULL-terminated `argv`) |
| a task | `Task::new(id, label, program)`; fields `group`, `default`, `depends`, `parallel`, `matchers` (`Matcher::Builtin`/`Text`), `ready`, `busy`, `reveal`, `output` | `Task{ID, Label, Program, Group, Default, Depends, Parallel, Matchers []Matcher{Builtin, Text}, Ready, Busy, Reveal, Output}` | `rx_task` (`is_default`, `builtin_matchers`, `matcher_texts`) |
| publish, run | `ext.set_tasks(&[Task])`, `start_task(id)`, `run_task(&Task)` | `SetTasks`, `StartTask`, `RunTask` (and `…Context`) | `rx_set_tasks`, `rx_start_task`, `rx_run_task` |
| terminals | `open_terminal(&TerminalSpec)`, `stop_terminal`, `restart_terminal`, `close_terminal`, `show_terminal(t, focus)`, `terminal_input`, `terminal_screen` → `Screen` | `OpenTerminal(TerminalSpec)`, `StopTerminal`, `RestartTerminal`, `CloseTerminal`, `ShowTerminal`, `TerminalInput`, `TerminalScreen` | `rx_open_terminal`, `rx_stop_terminal`, …, `rx_terminal_input`, `rx_terminal_screen` |
| events | `tasks::parse_terminal_event(&ev)` → `TerminalEvent::{Started, Ended, Output, Closed, Ready, Busy}` | `ParseTerminalEvent(ev)` → `TerminalEvent{Kind, Term, Reason, Code, …}` | `rx_parse_terminal_event` → `rx_terminal_event` |
| patterns | `check_pattern`, `match_pattern`, `check_matcher`, `builtin_matcher` | `CheckPattern`, `MatchPattern`, `CheckMatcher`, `BuiltinMatchers` | `rx_check_pattern`, `rx_match_pattern`, `rx_check_matcher`, `rx_builtin_matcher` |

Every SDK checks a definition as rhun reads it before sending (a `syntax` error names the task and
record: `syntax task 3: depends: no task "lint"`). The Go `…Context` forms send `cancel` when the
context ends while the approval dialog is open. The matchers pass `v1.1/patterns.txt`.

```rust
use rhun_ext::tasks::{self, Matcher, Program, Task, TerminalEvent};
use rhun_ext::{run, Event, Ext, Feature, Handler};

struct Build;
impl Handler for Build {
    fn ready(&mut self, ext: &Ext, _project: Option<&str>) {
        if !ext.has(Feature::Tasks) { return; } // an older rhun
        let mut build = Task::new("build", "cargo build", Program::argv(&["cargo", "build"]));
        build.group = "build".into();
        build.default = true;
        build.matchers = vec![Matcher::Builtin("rustc".into())];
        let mut test = Task::new("test", "cargo test", Program::shell("cargo test 2>&1"));
        test.group = "test".into();
        test.depends = vec!["build".into()];
        if let Err(e) = ext.set_tasks(&[build, test]) { eprintln!("tasks: {e}"); }
    }
    fn event(&mut self, _ext: &Ext, ev: &Event) {
        if let Some(TerminalEvent::Ended { term, reason, code, errors, .. }) = tasks::parse_terminal_event(ev) {
            eprintln!("terminal {term}: {reason} {code:?}, {errors} errors");
        }
    }
}
fn main() { let _ = run(&[Feature::Terminals, Feature::Tasks], Build); }
```

## Headless

`print-tasks`, `print-task-status`, `print-terminals`, `print-terminal-records`, `print-problems`,
`print-problems-tab`, `print-term`, `wait-terminal TERM running|waiting|exited|stopped|failed|ended
[RUNS]`, `term-run [--cwd D] [--env N=V] [--unset N] [--title T] [--task] [--silent] [--matcher
NAME] [--matcher-file PATH] [--sh] -- ARGV`, `term-stop`, `term-restart`, `term-close`,
`term-select TERM`, `print-pattern`, `print-uproc`, `run-approve OWNER/NAME COMMAND`,
`print-approve`, `print-allowed`. The approval dialog: `print-dialog`, then `dialog yes`
(`rhun-editor/tasks`' `tests/basic.txt` does this before `wait-terminal 1 ended`). The checker
validates `tasks-set` and every definition as rhun does and plays a run's events.

## Pitfalls

- Send `tasks-set` only after `0 features` agreed `tasks` (and `terminals`); without them every
  verb is `unknown`. Check `ext.has`/`Has` and fall back to v1's `term`.
- `tasks-set` replaces the whole list and is checked whole: one bad `depends`, a cycle or a bad
  pattern refuses everything. Use the SDK's check (`check_matcher`) on user-written matchers.
- The first start waits for the user's approval: never call it from a handler that must answer
  quickly; `busy` while another question is open.
- A relative `{file}` resolves against the task's folder (else the project's): set the task's
  `cwd` to where the tool prints paths from. `{col}` counts characters unless the matcher says
  `columns bytes` (the `go` and `gcc` built-ins do); without `{col}` the column is the line's first
  non-blank.
- A background task without `ready` never counts as done: its dependents wait for its exit.
- Limits: 1000 tasks and 1 MiB per extension; 32 tabs (a new one replaces the oldest ended task
  tab, else `busy`); `terminal-output` 64 KiB an event, 256 KiB/s per extension.
