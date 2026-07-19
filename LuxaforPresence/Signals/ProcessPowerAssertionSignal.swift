import AppKit
import Darwin
import Foundation
import IOKit.pwr_mgt

struct ProcessPowerAssertion: Equatable {
    let processIdentifier: pid_t
    let assertionType: String
    let level: Int
}

protocol ProcessPowerAssertionProviding {
    /// Returns `nil` when the operating system cannot provide assertion data.
    func activeAssertions() -> [ProcessPowerAssertion]?
}

struct IOKitProcessPowerAssertionProvider: ProcessPowerAssertionProviding {
    func activeAssertions() -> [ProcessPowerAssertion]? {
        var unmanagedAssertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanagedAssertions) == kIOReturnSuccess,
              let assertionsByProcess = unmanagedAssertions?.takeRetainedValue()
                as? [NSNumber: [[String: Any]]] else {
            return nil
        }

        return assertionsByProcess.flatMap { process, assertions in
            assertions.compactMap { assertion in
                guard let assertionType = assertion["AssertType"] as? String,
                      let level = assertion["AssertLevel"] as? NSNumber else {
                    return nil
                }
                return ProcessPowerAssertion(
                    processIdentifier: pid_t(process.int32Value),
                    assertionType: assertionType,
                    level: level.intValue
                )
            }
        }
    }
}

struct ZoomPowerAssertionSignal {
    // Zoom holds a display-sleep assertion for an active call even when its
    // microphone input is muted or temporarily closed. This keeps Zoom Quiet
    // stable for listening-only calls without treating an idle client as active.
    private static let meetingAssertionTypes: Set<String> = [
        "NoDisplaySleepAssertion",
        "PreventUserIdleDisplaySleep",
    ]
    private static let zoomBundleIdentifiers: Set<String> = [
        "us.zoom.caphost",
        "us.zoom.cpthost",
        "us.zoom.xos",
    ]

    private let provider: ProcessPowerAssertionProviding
    private let bundleIdentifier: (pid_t) -> String?

    init(
        provider: ProcessPowerAssertionProviding = IOKitProcessPowerAssertionProvider(),
        bundleIdentifier: @escaping (pid_t) -> String? = {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
    ) {
        self.provider = provider
        self.bundleIdentifier = bundleIdentifier
    }

    func isMeetingActive() -> Bool {
        guard let assertions = provider.activeAssertions() else { return false }
        return Self.containsZoomMeetingAssertion(
            assertions,
            bundleIdentifier: bundleIdentifier
        )
    }

    static func containsZoomMeetingAssertion(
        _ assertions: [ProcessPowerAssertion],
        bundleIdentifier: (pid_t) -> String?
    ) -> Bool {
        assertions.contains { assertion in
            assertion.level > 0
                && meetingAssertionTypes.contains(assertion.assertionType)
                && bundleIdentifier(assertion.processIdentifier).map {
                    zoomBundleIdentifiers.contains($0.lowercased())
                } == true
        }
    }
}
