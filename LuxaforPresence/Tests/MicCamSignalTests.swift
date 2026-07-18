import Darwin
import XCTest
@testable import LuxaforPresence

final class MicCamSignalTests: XCTestCase {
    func test_coreAudioActivityReduction_excludesOnlyTheCurrentSampler() {
        let activities = [
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 123,
                isRunningInput: true
            ),
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 456,
                isRunningInput: false
            ),
        ]

        XCTAssertFalse(
            CoreAudioInputProcessActivityProvider.hasExternalInput(
                activities,
                excluding: 123
            )
        )
    }

    func test_coreAudioActivityReduction_detectsAnyOtherRunningInput() {
        let activities = [
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 123,
                isRunningInput: true
            ),
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 456,
                isRunningInput: true
            ),
        ]

        XCTAssertTrue(
            CoreAudioInputProcessActivityProvider.hasExternalInput(
                activities,
                excluding: 123
            )
        )
    }

    func test_coreAudioActivityReduction_ignoresCoreSpeechVoiceTrigger() {
        let activities = [
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 123,
                bundleIdentifier: "com.jdegregorio.LuxaforPresence",
                isRunningInput: true
            ),
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 456,
                bundleIdentifier: "com.apple.CoreSpeech",
                isRunningInput: true
            ),
        ]

        XCTAssertFalse(
            CoreAudioInputProcessActivityProvider.hasExternalInput(
                activities,
                excluding: 123
            )
        )
    }

    func test_coreAudioActivityReduction_detectsUserAppAlongsideCoreSpeech() {
        let activities = [
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 123,
                bundleIdentifier: "com.jdegregorio.LuxaforPresence",
                isRunningInput: true
            ),
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 456,
                bundleIdentifier: "com.apple.CoreSpeech",
                isRunningInput: true
            ),
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 789,
                bundleIdentifier: "com.goodsnooze.MacWhisper",
                isRunningInput: true
            ),
        ]

        XCTAssertTrue(
            CoreAudioInputProcessActivityProvider.hasExternalInput(
                activities,
                excluding: 123
            )
        )
    }

    func test_coreAudioActivityReduction_unknownBundleFailsOpen() {
        let activities = [
            CoreAudioInputProcessActivityProvider.ProcessActivity(
                processIdentifier: 456,
                bundleIdentifier: nil,
                isRunningInput: true
            ),
        ]

        XCTAssertTrue(
            CoreAudioInputProcessActivityProvider.hasExternalInput(
                activities,
                excluding: 123
            )
        )
    }

    func test_coreAudioReportsOtherInputActive_returnsTrue() {
        let provider = FakeAudioInputProcessActivityProvider(result: true)
        let signal = MicCamSignal(
            inputActivityProvider: provider,
            processIdentifier: 123,
            legacyExternalUse: { false }
        )

        XCTAssertTrue(signal.isMicrophoneInUseByAnotherApplication())
        XCTAssertEqual(provider.excludedProcessIdentifiers, [123])
    }

    func test_coreAudioReportsNoOtherInput_doesNotUseLegacyFalsePositive() {
        let provider = FakeAudioInputProcessActivityProvider(result: false)
        var legacyProbeCount = 0
        let signal = MicCamSignal(
            inputActivityProvider: provider,
            processIdentifier: 123,
            legacyExternalUse: {
                legacyProbeCount += 1
                return true
            }
        )

        XCTAssertFalse(signal.isMicrophoneInUseByAnotherApplication())
        XCTAssertEqual(legacyProbeCount, 0)
    }

    func test_coreAudioUnavailable_usesLegacyDeviceOwnershipFallback() {
        let provider = FakeAudioInputProcessActivityProvider(result: nil)
        let signal = MicCamSignal(
            inputActivityProvider: provider,
            processIdentifier: 123,
            legacyExternalUse: { true }
        )

        XCTAssertTrue(signal.isMicrophoneInUseByAnotherApplication())
    }
}

private final class FakeAudioInputProcessActivityProvider: AudioInputProcessActivityProviding {
    private let result: Bool?
    private(set) var excludedProcessIdentifiers: [pid_t] = []

    init(result: Bool?) {
        self.result = result
    }

    func isInputActive(excluding processIdentifier: pid_t) -> Bool? {
        excludedProcessIdentifiers.append(processIdentifier)
        return result
    }
}
