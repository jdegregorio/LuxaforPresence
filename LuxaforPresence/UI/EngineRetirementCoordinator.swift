import Foundation

protocol PresenceEngineOutputRetiring: AnyObject {
    func suspendOutput()
    func shutdownOutput()
}

extension PresenceEngine: PresenceEngineOutputRetiring {}

enum EngineRetirementAction {
    case suspend
    case shutdown
}

/// Retires audio and transport resources away from the main thread, then returns
/// to the main queue so a replacement engine can start in deterministic order.
final class EngineRetirementCoordinator {
    private let queue: DispatchQueue
    private let completionQueue: DispatchQueue

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.jdegregorio.LuxaforPresence.engine-retirement",
            qos: .utility
        ),
        completionQueue: DispatchQueue = .main
    ) {
        self.queue = queue
        self.completionQueue = completionQueue
    }

    func retire(
        _ engine: PresenceEngineOutputRetiring,
        action: EngineRetirementAction,
        completion: @escaping () -> Void
    ) {
        queue.async {
            switch action {
            case .suspend:
                engine.suspendOutput()
            case .shutdown:
                engine.shutdownOutput()
            }
            self.completionQueue.async(execute: completion)
        }
    }
}
