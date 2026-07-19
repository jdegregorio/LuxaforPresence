import Foundation

struct MicrophoneActivitySnapshot: Equatable {
    let isActiveByAnotherApplication: Bool
    let activeBundleIdentifiers: Set<String>?

    init(
        isActiveByAnotherApplication: Bool,
        activeBundleIdentifiers: Set<String>? = nil
    ) {
        self.isActiveByAnotherApplication = isActiveByAnotherApplication
        self.activeBundleIdentifiers = activeBundleIdentifiers
    }

    func isActive(forBundleIdentifiers bundleIdentifiers: Set<String>) -> Bool {
        guard isActiveByAnotherApplication,
              let activeBundleIdentifiers else {
            return false
        }
        let normalizedTargets = Set(bundleIdentifiers.map { $0.lowercased() })
        return activeBundleIdentifiers.contains {
            normalizedTargets.contains($0.lowercased())
        }
    }
}

protocol MicCamSignalProtocol {
    func isMicrophoneInUseByAnotherApplication() -> Bool
    func microphoneActivity() -> MicrophoneActivitySnapshot
}

extension MicCamSignalProtocol {
    func microphoneActivity() -> MicrophoneActivitySnapshot {
        MicrophoneActivitySnapshot(
            isActiveByAnotherApplication: isMicrophoneInUseByAnotherApplication()
        )
    }
}

protocol FrontmostAppSignalProtocol {
    func isFrontmostIn(allowlist: Set<String>) -> Bool
}

protocol CalendarSignalProtocol {
    func requestAccess(completion: @escaping (Bool) -> Void)
    func hasOngoingMeetingEvent() -> Bool
}

protocol MeetingDetectorProtocol {
    var name: String { get }
    func isMeetingActive() -> Bool
    func isMeetingActive(
        microphoneActivity: MicrophoneActivitySnapshot
    ) -> Bool
}

extension MeetingDetectorProtocol {
    func isMeetingActive(
        microphoneActivity: MicrophoneActivitySnapshot
    ) -> Bool {
        isMeetingActive()
    }
}
