import Foundation

protocol MicCamSignalProtocol {
    func isMicrophoneInUseByAnotherApplication() -> Bool
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
}
