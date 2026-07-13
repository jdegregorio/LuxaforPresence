import Foundation

protocol LightOutputTimerProtocol: AnyObject {
    /// Replaces any existing schedule with one repeating callback.
    func schedule(every interval: TimeInterval, handler: @escaping () -> Void)
    func cancel()
}

/// A reusable dispatch timer. Cancellation parks the source instead of creating
/// another timer, so one controller owns one timer for its entire lifetime.
final class LightOutputTimer: LightOutputTimerProtocol {
    private let source: DispatchSourceTimer

    init(queue: DispatchQueue = .main) {
        source = DispatchSource.makeTimerSource(queue: queue)
        source.setEventHandler {}
        source.schedule(deadline: .distantFuture)
        source.resume()
    }

    func schedule(every interval: TimeInterval, handler: @escaping () -> Void) {
        source.setEventHandler(handler: handler)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(25)
        )
    }

    func cancel() {
        source.setEventHandler {}
        source.schedule(deadline: .distantFuture)
    }

    deinit {
        source.setEventHandler {}
        source.cancel()
    }
}
