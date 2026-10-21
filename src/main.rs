//! hello: a starting point for a rhun extension in Rust. Commands: a toast, an edit that
//! upper-cases the document as one undo step, and greet, which knows where it was run from (a
//! key, a menu item, the status bar) and gets that place's arguments; extension.ini declares its
//! key, menu item, status item and language keys. The protocol: https://rhun.app/extensions/v1/
//! and v1.1/; the SDK: rhun-ext (rust/rhun-ext in rhun-editor/extension-protocol). AGENTS.md says
//! how to grow it.

use rhun_ext::{run, whole_range, Doc, Ext, Feature, Handler, Invocation};

#[derive(Default)]
struct Hello;

impl Handler for Hello {
    /// Every run of a command, with where it came from (`inv.from`: palette, key, menu, ref) and
    /// what that place passes (`inv.body`): a key binding's arguments, a menu item's target and
    /// arguments, a command reference's arguments (the status item). Needs `Feature::CommandArgs`
    /// (main); without it the default calls `command`.
    fn invoke(&mut self, ext: &Ext, inv: &Invocation) {
        match inv.name.as_str() {
            "say" => {
                let _ = ext.toast("Hello from an extension");
            }
            "upper" => upper(ext, inv.doc),
            "greet" => {
                let mut who = if inv.body.is_empty() {
                    "you".to_string()
                } else {
                    String::from_utf8_lossy(&inv.body).into_owned()
                };
                if let Some((target, args)) = inv.target() {
                    // a menu item: the target line ("editor VERSION L1 C1 L2 C2" here), then its args
                    who = String::from_utf8_lossy(args).into_owned();
                    if target.kind == "editor" && target.fields.len() > 1 {
                        who += &format!(" at line {}", target.fields[1]);
                    }
                }
                let _ = ext.toast(&format!("Hello, {who} (from {})", inv.from));
            }
            _ => {}
        }
    }
}

fn upper(ext: &Ext, doc: Doc) {
    if doc == 0 {
        return;
    }
    // an edit names the version it was made against: when the user typed meanwhile, rhun refuses
    // it as stale and nothing changes
    let Ok((text, version)) = ext.text(doc) else {
        return;
    };
    let upper = String::from_utf8_lossy(&text).to_uppercase();
    if let Err(e) = ext.replace(doc, version, whole_range(&text), &upper) {
        eprintln!("hello: upper: {e}");
    }
}

fn main() {
    if let Err(e) = run(&[Feature::CommandArgs], Hello) {
        eprintln!("hello: {e}");
    }
}
