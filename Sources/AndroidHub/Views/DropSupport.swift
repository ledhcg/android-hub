import AppKit
import Foundation

/// Resolves dropped file URLs in the order they were dropped. `loadObject` calls back on arbitrary
/// threads, so results are stored by index under a lock instead of appended racily (order matters for
/// split-APK sets, where the base APK must come first).
func loadDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var results = [URL?](repeating: nil, count: providers.count)
    let lock = NSLock()
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            lock.withLock { results[index] = url }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(results.compactMap { $0 }) }
}
