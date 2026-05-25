public enum AppState: Equatable {
    case sandboxed
    case obtainingOffsets
    case exploiting
    case exploitFailed(String)
    case patched
    case panicRecovery
}
