///|
/// Project version.
///
/// The single source of truth for the version the emulator reports at
/// runtime (`rv32mbt --version`). It must match the `version` field in
/// moon.mod; ci/run.sh fails the build when the two disagree.
pub const VERSION : String = "1.0.0"
