//! hello: a starting point for a rhun extension in Rust. Two commands: a toast, and an edit that
//! upper-cases the document as one undo step. The protocol: https://rhun.app/extensions/v1/; the
//! SDK: rhun-ext (rust/rhun-ext in rhun-editor/extension-protocol). AGENTS.md says how to grow it.

use rhun_ext::{run, whole_range, Doc, Ext, Handler};

#[derive(Default)]
struct Hello;

impl Handler for Hello {
    fn command(&mut self, ext: &Ext, name: &str, doc: Doc) {
        match name {
            "say" => {
                let _ = ext.toast("Hello from an extension");
            }
            "upper" => {
                if doc == 0 {
                    return;
                }
                // an edit names the version it was made against: when the user typed meanwhile,
                // rhun refuses it as stale and nothing changes
                let Ok((text, version)) = ext.text(doc) else { return };
                let upper = String::from_utf8_lossy(&text).to_uppercase();
                if let Err(e) = ext.replace(doc, version, whole_range(&text), &upper) {
                    eprintln!("hello: upper: {e}");
                }
            }
            _ => {}
        }
    }
}

fn main() {
    if let Err(e) = run(&[], Hello) {
        eprintln!("hello: {e}");
    }
}
