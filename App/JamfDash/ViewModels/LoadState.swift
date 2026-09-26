import Foundation

enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// True when no data has been fetched yet (idle or actively loading).
    var isPending: Bool {
        switch self {
        case .idle, .loading: return true
        default: return false
        }
    }

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var errorMessage: String? {
        if case .failed(let msg) = self { return msg }
        return nil
    }
}
