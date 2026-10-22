# AI: agents, reviews, tools (protocol 1.1)

rhun reads and reviews; it drives no agent itself. Features, each in `hello 1 ...`: `agents`
(rows in the Agents panel; `[provides] agents = yes`, optional `agents.title`), `agent-prompts`
(with `agents`: a prompt box, Stop and question cards), `edit-review` (edits the user accepts or
rejects file by file and hunk by hunk) and `tools` (`[tools]` other extensions and agents call
through rhun). Commit messages are a source control feature: see `scm.md`. Spec section "Agents,
proposals and tools" (Feature: `agents`, `edit-review`, `tools`, `agent-prompts`) of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. Example:
`rhun-editor/mcp` (Rust) bridges every tool to agents in a terminal over MCP.

## agents: sessions in the Agents panel

| Direction | Message | Answer |
| --- | --- | --- |
| ext → rhun | `ID agent-sessions LEN` + rows | `ok ID`; replaces all of the extension's rows |
| ext → rhun | `ID agent-changed SID TOTAL FIRST` | `ok ID`; the session has TOTAL messages, FIRST is the first changed (`refused no such session`) |
| rhun → ext | `ID agent-transcript SID FROM` | `ok ID LEN` + `TOTAL N` LF and N messages from FROM, or `error ID CODE TEXT` |

- Rows: `N` LF, then `UPDATED STATE SID_LEN TITLE_LEN MODEL_LEN CWD_LEN` LF + the four strings.
  UPDATED Unix seconds; STATE `idle`, `working`, `waiting` (for the user) or `error`; SID 1 to 128
  bytes of visible ASCII, unique; CWD absolute or empty. At most 1000 rows and 1 MB; malformed is
  `syntax` and changes nothing.
- A row shows when its CWD is empty, the project, a folder in it, or one of the repository's
  worktrees. Rows go when the extension stops. Settings > Agents switches a source off
  (`[agents] OWNER/NAME = false`).
- Messages: `ROLE NAME_LEN TEXT_LEN MODEL_LEN` LF + the three strings; ROLE `user`, `assistant`,
  `tool` (NAME the tool, TEXT a summary), `result`, `error`, `info`. Text cut at 70 KB; at most
  2000 messages and 4 MB an answer; rhun asks again from FROM + N while that is under TOTAL, and
  from FIRST after `agent-changed` while the session is open. 30 s per answer.

## agent-prompts: talking to the session

| Direction | Message | Answer |
| --- | --- | --- |
| rhun → ext | `ID agent-prompt SID LEN` + text | `ok ID LEN` + the session id (SID `-`: a new session from the header's `+ TITLE`) |
| rhun → ext | `0 agent-stop SID` | the user's Stop; say what changed with `agent-sessions`/`agent-changed` |
| ext → rhun | `ID agent-ask SID LEN` + a prompt line and 1 to 16 option lines | `ok ID N` (N from 1), or `error ID cancelled` |

The prompt is at most 64 KB; an error or 30 s without an answer puts the text back in the box. A
new card on a session replaces the old one (answered `cancelled`); `cancel ID` withdraws it.

## edit-review: proposals

| Direction | Message | Answer |
| --- | --- | --- |
| ext → rhun | `ID propose LEN` + `LABEL_LEN SID_LEN` LF `<LABEL><SID>` + a 12g workspace edit | `ok ID PROPOSAL` at once |
| ext → rhun | `ID unpropose PROPOSAL` | `ok ID`; the Review tab closes, no more events |
| rhun → ext | `0 proposal PROPOSAL INDEX accepted\|rejected\|stale\|partial A N` | one per file (INDEX from 1, the edit's order), once all its hunks are decided |
| rhun → ext | `0 proposal PROPOSAL done ACCEPTED REJECTED` | every file decided |

Needs `documents = read`, plus `project`/`home` read for files that are not open. rhun checks it as
`apply` would (versions, ranges, no overlaps, no file twice; a file not open: an existing text file
of at most 4 MB); an edit that changes nothing is `refused`; at most 8 proposals wait. The edit is
always v1 12g's grammar: no hashes, label, `confirm` or file operations. Accepting applies hunks
through the ordinary edit path, one undo step per decision, unsaved. Closing the tab rejects the
rest.

## tools: tools between extensions

```ini
[tools]
# NAME = Title | one-line description for the model
search_docs = Search Docs | Searches the project's documentation index
search_docs.input = query=TEXT (one line); limit=N (optional, at most 50)
# changes nothing: called without asking the user
search_docs.readonly = yes
```

| Direction | Message | Answer |
| --- | --- | --- |
| ext → rhun | `ID tools` | `ok ID LEN` + `N` LF, N × `TOOL FLAGS TITLE_LEN DESC_LEN INPUT_LEN` LF + texts (TOOL `rhun.NAME` or `OWNER/NAME.TOOL`, FLAGS `ro`/`rw`) |
| ext → rhun | `ID tool-call TOOL LEN` + input | when done: `ok ID LEN` + output, or `error ID …` |
| rhun → owner | `ID tool NAME CALLER LEN` + input | `ok ID LEN` + output, or `error ID CODE TEXT` (back to the caller unchanged) |

NAME is 1 to 40 of `[a-z0-9_]`, at most 64 tools. Input and output are opaque (4 MB each). A tool
without `readonly = yes` asks the user before each call (Allow once, Allow for this session, Deny:
`refused denied by the user`); calls queue, 256 at most. rhun starts an idle owner (10 s, else
`busy`). Errors: `refused no such tool`, `refused the tool's extension is not running`, `refused
the tool's extension does not take tool calls` (it did not agree `tools`), `cancelled the tool's
extension stopped`. A caller withdraws a call with `cancel ID`.

rhun's own tools run with the **caller's** `[needs]`; input is `KEY VALUE` lines, and `KEY LEN`
LF + bytes for `text` and `edit`:

| Tool | Input | Output | Needs |
| --- | --- | --- | --- |
| `rhun.editors` | | `DOC DIRTY LANG PATH` per document, then `active DOC` | documents read |
| `rhun.selection` | | `DOC L1 C1 L2 C2` LF + the selected text | documents read |
| `rhun.read` | `path P` or `doc DOC`; `from L`, `to L` | the text (unsaved text for an open document) | documents read; a closed file `project`/`home` read |
| `rhun.diagnostics` | `path P` (optional) | `PATH L1 C1 L2 C2 SEVERITY OWNER/NAME MESSAGE` per mark | documents read |
| `rhun.open` | `path P`, `line L`, `col C` | `DOC` | a closed file `project`/`home` read |
| `rhun.propose` | `edit LEN` + a workspace edit, or `path P` + `text LEN`; `label TEXT` | `accepted A rejected R` once decided | documents read |
| `rhun.run` | `command TEXT` | `ok` once Enter put it in the terminal, else `cancelled` | terminal |

`rhun.propose` and `rhun.run` ask no dialog: the Review tab and the terminal prompt are the user's
confirmation. An extension may listen on a Unix socket in its own state folder whatever `network`
says; `rhun-editor/mcp` does that (`$RHUN_STATE/mcp/mcp-PID.sock`, a loopback port with a token on
Windows): an agent's `mcp --stdio` connects to it, and each MCP call becomes a `tool-call` run with
the bridge's `[needs]` (`documents = read`, `project = read`, `terminal = yes`).

## SDK

| | Rust (`rhun_ext::ai`) | Go | C |
| --- | --- | --- | --- |
| features | `Feature::Agents`, `AgentPrompts`, `EditReview`, `Tools` | `FeatureAgents`, `FeatureAgentPrompts`, `FeatureEditReview`, `FeatureTools` | `"agents agent-prompts edit-review tools"` |
| rows | `ext.agent_sessions(&[Session::new(id, title).model(m).cwd(c).state(SessionState::Working)])`, `ext.agent_changed(sid, total, first)` | `ext.AgentSessions([]Session)`, `NewSession`, `SessionWorking`…, `ext.AgentChanged` | `rx_agent_sessions(ext, rx_session*, n)`, `rx_agent_changed` |
| transcript | `Handler::agent_transcript(sid, from) -> Result<Transcript, Refusal>`; `Transcript::page(&all, from)`, `Message::new(Role::Assistant, text).model(m)` | `TranscriptProvider.AgentTranscript`, `TranscriptPage`, `Message{Role, Name, Text, Model}`, `RoleUser`… | `agent_transcript` handler, `rx_transcript_add`, `rx_transcript_finish` |
| prompts | `Handler::agent_prompt(Option<&str>, text) -> Result<String, Refusal>`, `agent_stop`; `ext.agent_ask(sid, prompt, &opts)` → index **from 0** | `Prompter` (`AgentPrompt` with sid `""` for new, `AgentStop`); `ext.AgentAsk` → from 0 | `agent_prompt`, `agent_stop`; `rx_agent_ask` → from 0, -1 cancelled |
| proposals | `ext.propose(label, sid, &WorkspaceEdit)`, `unpropose`; `Handler::proposal(ProposalEvent)` | `ext.Propose(label, sid, edit)`, `Unpropose`, `ParseProposal(ev)` | `rx_propose`, `rx_unpropose`, `proposal` handler (`rx_proposal_event`) |
| tools | `ext.tools()` → `Vec<ToolInfo>`, `ext.tool_call(tool, &input)`, `ToolInput::new().set(k, v).bytes(k, b).into_bytes()`; `Handler::tool(&ToolCall { name, caller, input })` | `ext.Tools()`, `ext.CallTool(tool, input)`, `ToolInput.Set/Bytes/Encode`; `ToolProvider.Tool(ext, ToolCall)` | `rx_tools` (`rx_tools_free`), `rx_tool_call`, `tool` handler |

The wire's `agent-ask` answer counts options from 1; all three SDKs return them from 0.

```rust
use rhun_ext::ai::{Message, ProposalEvent, Refusal, Role, Session, SessionState, ToolCall, ToolInput, Transcript};
use rhun_ext::{run, Ext, Feature, Handler};

#[derive(Default)]
struct Echo { messages: Vec<Message> }

impl Echo {
    fn rows(&self, ext: &Ext) {
        let s = Session::new("echo-1", "Echo").model("echo-0").state(SessionState::Idle);
        let _ = ext.agent_sessions(&[s]);
    }
}

impl Handler for Echo {
    fn ready(&mut self, ext: &Ext, _project: Option<&str>) { self.rows(ext); }
    // the user opened the session, or it changed: messages from `from` on
    fn agent_transcript(&mut self, _ext: &Ext, sid: &str, from: u64) -> Result<Transcript, Refusal> {
        if sid != "echo-1" { return Err(Refusal::new("refused", "no such session")); }
        Ok(Transcript::page(&self.messages, from))
    }
    // the prompt box (feature agent-prompts): sid None starts a session
    fn agent_prompt(&mut self, ext: &Ext, _sid: Option<&str>, text: &str) -> Result<String, Refusal> {
        self.messages.push(Message::new(Role::User, text));
        self.messages.push(Message::new(Role::Assistant, text).model("echo-0"));
        self.rows(ext);
        let _ = ext.agent_changed("echo-1", self.messages.len() as u64, self.messages.len() as u64 - 2);
        Ok("echo-1".into())
    }
    // another extension (or the MCP bridge) calls one of this extension's [tools]
    fn tool(&mut self, _ext: &Ext, call: &ToolCall) -> Result<Vec<u8>, Refusal> {
        match call.name.as_str() {
            "count_words" => Ok(String::from_utf8_lossy(&call.input).split_whitespace().count().to_string().into_bytes()),
            _ => Err(Refusal::new("refused", "no such tool")),
        }
    }
    fn proposal(&mut self, _ext: &Ext, ev: ProposalEvent) { eprintln!("{ev:?}"); }
}

// calling rhun's own tools: from a thread of your own, since tool_call waits for the user
fn selection(ext: &Ext) -> Option<Vec<u8>> {
    ext.tool_call("rhun.selection", &ToolInput::new().into_bytes()).ok()
}

fn main() {
    let f = [Feature::Agents, Feature::AgentPrompts, Feature::Tools, Feature::EditReview];
    if let Err(e) = run(&f, Echo::default()) { eprintln!("echo: {e}"); }
    let _ = selection;
}
```

Manifest: `[provides] agents = yes`, `agents.title = Echo`, `[tools] count_words = Count Words |
Counts the words of its input`, `count_words.readonly = yes`, `[needs] documents = read`.

## Testing headless

`print-agents` (sessions), `agent-new OWNER/NAME`, `agent-prompt TEXT` (types it in the box and
presses Enter), `agent-stop`, `agent-card N`, `print-agent-input`; `print-review`, `review
accept|reject FILE|all [HUNK]`; `print-tools` (the list, then each call in flight),
`tool-confirm once|session|deny`. The conformance checker answers `agent-sessions`, `agent-changed`,
`propose`, `unpropose`, `tools`, `tool-call` and `agent-ask` as rhun does (denying the first
`rhun.propose` call; unknown tools are `refused no such tool`), and asks for a transcript, each tool's output and a prompt.

## Pitfalls

- `agent-sessions` replaces every row: always send the whole list, and keep SIDs stable.
- Handlers run one at a time: a long `tool` answer holds up the events behind it, and
  `tool_call` blocks until the tool (and maybe the user) answers; call it from a thread.
- A tool that changes anything without `readonly = yes` makes the user confirm every call; a
  read-only tool that does change something breaks the user's trust: mark it honestly.
- `propose` takes 12g's grammar only: file operations fail as `unknown`; build edits against
  the versions the user has now.
- `[provides] agents = yes` is required, or `agent-sessions` is refused.
