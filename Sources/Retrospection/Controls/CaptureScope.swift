import Foundation

/// Decides whether a given app should be captured.
///
/// Two modes, allow-list taking precedence:
///   - If `allowOnly` is non-empty, capture *only* those apps (everything else is ignored).
///   - Otherwise capture everything *except* the `ignore` set.
///
/// v0 runs in allow-only mode seeded to the Claude app, so capture is scoped to one app.
struct CaptureScope {
    let allowOnly: Set<String>
    let ignore: Set<String>

    func shouldCapture(bundleID: String?) -> Bool {
        if !allowOnly.isEmpty {
            guard let bundleID else { return false }
            return allowOnly.contains(bundleID)
        }
        guard let bundleID else { return true }
        return !ignore.contains(bundleID)
    }
}
