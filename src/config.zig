//! Shared paths and constants for ZNotebook.

pub const port: u16 = 8000;
pub const host = "127.0.0.1";

pub const notebooks_dir = "notebooks";
pub const temp_dir = "temp";

/// Primary notebook file extension.
pub const ext = ".zignb";
/// Legacy extension accepted on load only (Phase 1 migration).
pub const legacy_ext = ".znb";

pub const format_name = "zignb";
pub const format_version: u32 = 1;
