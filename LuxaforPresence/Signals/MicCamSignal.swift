import AVFoundation
import CoreAudio
import Darwin
import Foundation
import OSLog

protocol AudioInputProcessActivityProviding {
    /// Returns `nil` when the installed macOS audio HAL does not expose process
    /// input activity and the caller should use its compatibility fallback.
    func isInputActive(excluding processIdentifier: pid_t) -> Bool?
}

/// Reads the Core Audio process list instead of inferring microphone ownership
/// from capture-device exclusivity. Modern meeting and browser apps share input
/// devices, so `AVCaptureDevice.isInUseByAnotherApplication` can remain false
/// even while those apps are actively receiving microphone samples.
struct CoreAudioInputProcessActivityProvider: AudioInputProcessActivityProviding {
    struct ProcessActivity: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let isRunningInput: Bool

        init(
            processIdentifier: pid_t,
            bundleIdentifier: String? = nil,
            isRunningInput: Bool
        ) {
            self.processIdentifier = processIdentifier
            self.bundleIdentifier = bundleIdentifier
            self.isRunningInput = isRunningInput
        }
    }

    /// CoreSpeech keeps an always-on voice-trigger stream after some dictation
    /// sessions even when no user-facing client is listening. Treating that
    /// system service as an external app makes LuxaforPresence start its own
    /// sampler and prevents the sampler from ever becoming idle again.
    private static let nonUserInputBundleIdentifiers: Set<String> = [
        "com.apple.CoreSpeech",
    ]

    func isInputActive(excluding processIdentifier: pid_t) -> Bool? {
        guard let processObjects = processObjectIDs() else { return nil }

        var activities: [ProcessActivity] = []
        for processObject in processObjects {
            guard let pid = processID(for: processObject),
                  let isRunningInput = isRunningInput(for: processObject) else {
                continue
            }
            activities.append(
                ProcessActivity(
                    processIdentifier: pid,
                    bundleIdentifier: bundleIdentifier(for: processObject),
                    isRunningInput: isRunningInput
                )
            )
        }
        guard processObjects.isEmpty || !activities.isEmpty else { return nil }
        return Self.hasExternalInput(
            activities,
            excluding: processIdentifier
        )
    }

    static func hasExternalInput(
        _ activities: [ProcessActivity],
        excluding processIdentifier: pid_t
    ) -> Bool {
        activities.contains {
            $0.processIdentifier != processIdentifier
                && $0.isRunningInput
                && !nonUserInputBundleIdentifiers.contains($0.bundleIdentifier ?? "")
        }
    }

    private func processObjectIDs() -> [AudioObjectID]? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(systemObject, &address) else {
            return nil
        }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var processObjects = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: count
        )
        let status = processObjects.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        return status == noErr ? processObjects : nil
    }

    private func processID(for processObject: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObject, &address) else { return nil }

        var value: pid_t = 0
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(
            processObject,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func bundleIdentifier(for processObject: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObject, &address) else { return nil }

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            processObject,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func isRunningInput(for processObject: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObject, &address) else { return nil }

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            processObject,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value != 0 : nil
    }
}

/// Reports microphone input activity in any other process without opening an
/// audio stream or requesting an additional privacy permission.
///
/// `VoiceActivitySignal` is the sole microphone permission owner. This signal
/// reads Core Audio process activity and never opens an additional capture
/// session. AVFoundation device ownership remains a compatibility fallback for
/// systems where the process-level HAL property is unavailable.
final class MicCamSignal: MicCamSignalProtocol {
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "MicrophoneUseSignal"
    )
    private let inputActivityProvider: AudioInputProcessActivityProviding
    private let processIdentifier: pid_t
    private let legacyExternalUse: () -> Bool
    private let lock = NSLock()
    private var lastReportedState: Bool?

    init(
        inputActivityProvider: AudioInputProcessActivityProviding = CoreAudioInputProcessActivityProvider(),
        processIdentifier: pid_t = getpid(),
        legacyExternalUse: (() -> Bool)? = nil
    ) {
        self.inputActivityProvider = inputActivityProvider
        self.processIdentifier = processIdentifier
        self.legacyExternalUse = legacyExternalUse ?? Self.avFoundationExternalUse
    }

    func isMicrophoneInUseByAnotherApplication() -> Bool {
        let processActivity = inputActivityProvider.isInputActive(
            excluding: processIdentifier
        )
        let inUse = processActivity ?? legacyExternalUse()
        let source = processActivity == nil ? "avFoundationFallback" : "coreAudioProcesses"

        lock.lock()
        let stateChanged = lastReportedState != inUse
        lastReportedState = inUse
        lock.unlock()
        if stateChanged {
            logger.log(
                "External input activity changed active=\(inUse, privacy: .public) source=\(source, privacy: .public)"
            )
        }
        return inUse
    }

    private static func avFoundationExternalUse() -> Bool {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices
        return devices.contains { $0.isInUseByAnotherApplication }
    }
}
