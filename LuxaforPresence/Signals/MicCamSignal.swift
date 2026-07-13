import AVFoundation
import Foundation
import OSLog

/// Reports external microphone use without requesting privacy permissions.
///
/// `VoiceActivitySignal` is the sole microphone permission owner. This signal
/// only reads the system's external-use property after that request has been
/// made, and never opens an additional capture session.
final class MicCamSignal: MicCamSignalProtocol {
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "MicrophoneUseSignal"
    )
    private let lock = NSLock()
    private var lastReportedState: Bool?

    func isMicrophoneInUseByAnotherApplication() -> Bool {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices
        let inUse = devices.contains { $0.isInUseByAnotherApplication }
        lock.lock()
        let stateChanged = lastReportedState != inUse
        lastReportedState = inUse
        lock.unlock()
        if stateChanged {
            logger.debug("External microphone use changed active=\(inUse, privacy: .public) devices=\(devices.count, privacy: .public)")
        }
        return inUse
    }
}
