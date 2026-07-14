import XCTest
@testable import LuxaforPresence

final class PresenceEngineTests: XCTestCase {
    func test_zoomActiveWithoutVoice_returnsZoomQuietAndYellow() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.zoomQuiet])
        XCTAssertEqual(harness.luxafor.actions, [.yellow(harness.config.remoteWebhookUserId)])
        XCTAssertEqual(harness.outputs, [.solid(.yellow)])
        XCTAssertEqual(engine.desiredOutput, .solid(.yellow))
        XCTAssertEqual(harness.snapshots.last?.decisionPath, .zoomQuiet)
    }

    func test_noCommunicationContext_returnsAvailableAndOff() {
        let harness = PresenceEngineHarness()
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-1)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available])
        XCTAssertEqual(harness.luxafor.actions, [.off(harness.config.remoteWebhookUserId)])
        XCTAssertEqual(harness.outputs, [.off])
        XCTAssertEqual(harness.snapshots.last?.decisionPath, .noCommunicationContext)
    }

    func test_microphoneActiveWithoutVoice_returnsAvailableAndOff() {
        let harness = PresenceEngineHarness()
        harness.micCam.microphoneActive = true
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available])
        XCTAssertEqual(harness.luxafor.actions, [.off(harness.config.remoteWebhookUserId)])
        XCTAssertEqual(harness.snapshots.last?.decisionPath, .available)
    }

    func test_externalMicrophoneContext_startsAndStopsVoiceSampling() {
        let harness = PresenceEngineHarness()
        let engine = harness.makeEngine()

        tickAndWait(engine)
        harness.micCam.microphoneActive = true
        tickAndWait(engine)
        harness.micCam.microphoneActive = false
        tickAndWait(engine)

        XCTAssertEqual(
            harness.voiceActivity.captureContextRequests,
            [false, true, false]
        )
        XCTAssertEqual(
            harness.snapshots.map(\.voiceSamplingActive),
            [false, true, false]
        )
        XCTAssertFalse(harness.voiceActivity.isCapturing)
    }

    func test_zoomWithoutExternalMicrophone_doesNotStartVoiceSampling() throws {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.zoomQuiet])
        XCTAssertEqual(harness.voiceActivity.captureContextRequests, [false])
        XCTAssertFalse(try XCTUnwrap(harness.snapshots.last).voiceSamplingActive)
    }

    func test_voiceOneSecondAgoWithZoom_returnsVoiceRecentAndRed() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-1)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceRecent])
        XCTAssertEqual(harness.luxafor.actions, [.red(harness.config.remoteWebhookUserId)])
        XCTAssertEqual(harness.outputs, [.blink(color: .red, interval: 0.75)])
        XCTAssertEqual(harness.outputTimer.scheduledIntervals, [0.75])
        XCTAssertEqual(harness.snapshots.last?.decisionPath, .recentVoice)
    }

    func test_voiceOneSecondAgoWithMicrophoneOnly_returnsVoiceRecentAndRed() {
        let harness = PresenceEngineHarness()
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-1)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceRecent])
        XCTAssertEqual(harness.luxafor.actions, [.red(harness.config.remoteWebhookUserId)])
    }

    func test_recentVoiceWithoutCommunicationContext_returnsAvailable() {
        let harness = PresenceEngineHarness()
        harness.voiceActivity.active = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available])
        XCTAssertEqual(
            harness.snapshots.last?.lastVoiceActivityDate,
            harness.currentDate
        )
    }

    func test_voiceImmediatelyBeforeRecentBoundary_returnsVoiceRecent() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-299.999)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceRecent])
    }

    func test_voiceAtRecentBoundary_returnsVoiceCooldown() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-300)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceCooldown])
        XCTAssertEqual(harness.outputs, [.solid(.red)])
        XCTAssertEqual(harness.snapshots.last?.decisionPath, .voiceCooldown)
    }

    func test_voiceImmediatelyBeforeCooldownBoundary_returnsVoiceCooldown() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-599.999)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceCooldown])
    }

    func test_voiceAtCooldownBoundaryWithZoom_returnsZoomQuiet() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-600)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.zoomQuiet])
        XCTAssertEqual(harness.luxafor.actions, [.yellow(harness.config.remoteWebhookUserId)])
    }

    func test_voiceAfterCooldownWithMicrophoneOnly_returnsAvailable() {
        let harness = PresenceEngineHarness()
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-601)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available])
        XCTAssertEqual(harness.luxafor.actions, [.off(harness.config.remoteWebhookUserId)])
    }

    func test_zeroVoiceDurations_skipBothTimedStates() {
        let harness = PresenceEngineHarness { config in
            config.recentVoiceBlinkSeconds = 0
            config.voiceCooldownSeconds = 0
        }
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.zoomQuiet])
    }

    func test_microphoneEndingWhileZoomRemainsActive_preservesRecentVoiceState() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)
        harness.micCam.microphoneActive = false
        harness.currentDate = harness.currentDate.addingTimeInterval(120)
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceRecent])
        XCTAssertEqual(harness.snapshots.map(\.state), [.voiceRecent, .voiceRecent])
        XCTAssertEqual(harness.luxafor.actions, [.red(harness.config.remoteWebhookUserId)])
    }

    func test_communicationContextEndingDuringRedTimeline_turnsOffImmediately() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)
        harness.meetingDetector.isActive = false
        harness.micCam.microphoneActive = false
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceRecent, .available])
        XCTAssertEqual(
            harness.luxafor.actions,
            [.red(harness.config.remoteWebhookUserId), .off(harness.config.remoteWebhookUserId)]
        )
        XCTAssertEqual(harness.voiceActivity.lastVoiceActivityDate, harness.currentDate)
        XCTAssertEqual(harness.voiceActivity.captureContextChanges, [true, false])
    }

    func test_newCommunicationContext_doesNotReusePriorSessionVoice() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let firstVoiceDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)
        harness.meetingDetector.isActive = false
        harness.micCam.microphoneActive = false
        tickAndWait(engine)
        harness.currentDate = harness.currentDate.addingTimeInterval(60)
        harness.meetingDetector.isActive = true
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceRecent, .available, .zoomQuiet])
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .red(harness.config.remoteWebhookUserId),
                .off(harness.config.remoteWebhookUserId),
                .yellow(harness.config.remoteWebhookUserId),
            ]
        )
        XCTAssertEqual(harness.snapshots.last?.lastVoiceActivityDate, firstVoiceDate)
        XCTAssertEqual(harness.snapshots.last?.decisionPath, .zoomQuiet)
    }

    func test_qualifiedVoiceObservedAfterContextEnds_isDiagnosticOnlyForLaterZoomSession() {
        let harness = PresenceEngineHarness()
        let qualifiedVoiceDate = harness.currentDate
        harness.voiceActivity.lastActivityDate = qualifiedVoiceDate
        let engine = harness.makeEngine()

        tickAndWait(engine)
        harness.currentDate = harness.currentDate.addingTimeInterval(1)
        harness.meetingDetector.isActive = true
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available, .zoomQuiet])
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .off(harness.config.remoteWebhookUserId),
                .yellow(harness.config.remoteWebhookUserId),
            ]
        )
        XCTAssertEqual(
            harness.snapshots.last?.lastVoiceActivityDate,
            qualifiedVoiceDate
        )
    }

    func test_newVoiceDuringCooldown_returnsToVoiceRecent() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-301)
        let engine = harness.makeEngine()

        tickAndWait(engine)
        harness.voiceActivity.lastActivityDate = harness.currentDate
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.voiceCooldown, .voiceRecent])
        XCTAssertEqual(
            harness.luxafor.actions,
            [.red(harness.config.remoteWebhookUserId)]
        )
        XCTAssertEqual(
            harness.outputs,
            [.solid(.red), .blink(color: .red, interval: 0.75)]
        )
    }

    func test_vadDisabledWithZoom_returnsZoomQuietAndHidesVoiceDiagnostics() throws {
        let harness = PresenceEngineHarness { config in
            config.vadEnabled = false
        }
        harness.meetingDetector.isActive = true
        harness.voiceActivity.active = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.zoomQuiet])
        XCTAssertFalse(try XCTUnwrap(harness.snapshots.last).voiceCurrentlyAboveThreshold)
        XCTAssertFalse(try XCTUnwrap(harness.snapshots.last).voiceSamplingActive)
        XCTAssertNil(harness.snapshots.last?.lastVoiceActivityDate)
        XCTAssertTrue(harness.voiceActivity.captureContextRequests.isEmpty)
    }

    func test_vadDisabledWithMicrophoneOnly_returnsAvailable() {
        let harness = PresenceEngineHarness { config in
            config.vadEnabled = false
        }
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available])
    }

    func test_snapshot_containsSignalsTimestampAndDecisionPath() throws {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.active = true
        harness.voiceActivity.lastActivityDate = harness.currentDate.addingTimeInterval(-12)
        let engine = harness.makeEngine()

        tickAndWait(engine)

        let snapshot = try XCTUnwrap(harness.snapshots.last)
        XCTAssertEqual(snapshot.state, .voiceRecent)
        XCTAssertTrue(snapshot.zoomActive)
        XCTAssertTrue(snapshot.microphoneActive)
        XCTAssertTrue(snapshot.voiceSamplingActive)
        XCTAssertTrue(snapshot.voiceCurrentlyAboveThreshold)
        XCTAssertEqual(snapshot.lastVoiceActivityDate, harness.currentDate.addingTimeInterval(-12))
        XCTAssertEqual(snapshot.evaluatedAt, harness.currentDate)
        XCTAssertEqual(snapshot.secondsSinceVoiceActivity, 12)
        XCTAssertEqual(snapshot.decisionPath, .recentVoice)
    }

    func test_unchangedAutomaticState_emitsSnapshotsWithoutDuplicateOutput() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        let engine = harness.makeEngine()

        tickAndWait(engine)
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.zoomQuiet])
        XCTAssertEqual(harness.snapshots.count, 2)
        XCTAssertEqual(harness.luxafor.actions, [.yellow(harness.config.remoteWebhookUserId)])
    }

    func test_manualOverride_bypassesSignalsAndDoesNotDuplicateOutput() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        engine.force(.available)
        tickAndWait(engine)

        XCTAssertEqual(harness.states, [.available])
        XCTAssertEqual(harness.meetingDetector.callCount, 0)
        XCTAssertEqual(harness.micCam.microphoneReadCount, 0)
        XCTAssertTrue(harness.snapshots.isEmpty)
        XCTAssertEqual(harness.luxafor.actions, [.off(harness.config.remoteWebhookUserId)])
    }

    func test_manualOverride_stopsVoiceSamplingUntilAutomaticModeReturns() {
        let harness = PresenceEngineHarness()
        harness.micCam.microphoneActive = true
        let engine = harness.makeEngine()

        tickAndWait(engine)
        engine.force(.available)

        XCTAssertEqual(harness.voiceActivity.captureContextChanges, [true, false])
        XCTAssertFalse(harness.voiceActivity.isCapturing)
    }

    func test_supersededQueuedManualOverride_discardsStaleCommand() {
        let harness = PresenceEngineHarness()
        let engine = harness.makeEngine()
        let mainQueueDrained = expectation(description: "main queue drained")
        let backgroundForceReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            engine.force(.voiceRecent)
            backgroundForceReturned.signal()
        }
        XCTAssertEqual(backgroundForceReturned.wait(timeout: .now() + 1), .success)
        engine.force(.available)
        DispatchQueue.main.async {
            mainQueueDrained.fulfill()
        }

        wait(for: [mainQueueDrained], timeout: 1)
        XCTAssertEqual(harness.states, [.available])
        XCTAssertEqual(harness.luxafor.actions, [.off(harness.config.remoteWebhookUserId)])
    }

    func test_clearForce_immediatelyReevaluatesAutomaticState() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        let engine = harness.makeEngine()
        let automaticStateApplied = expectation(description: "automatic state applied")
        engine.onStateChange = { state in
            harness.states.append(state)
            if state == .zoomQuiet {
                automaticStateApplied.fulfill()
            }
        }

        engine.force(.available)
        engine.clearForce()

        wait(for: [automaticStateApplied], timeout: 2)
        XCTAssertEqual(harness.states, [.available, .zoomQuiet])
        XCTAssertEqual(
            harness.luxafor.actions,
            [.off(harness.config.remoteWebhookUserId), .yellow(harness.config.remoteWebhookUserId)]
        )
        XCTAssertEqual(harness.meetingDetector.callCount, 1)
    }

    func test_forceSelectedDuringAutomaticPoll_discardsStaleAutomaticResult() {
        let harness = PresenceEngineHarness()
        harness.micCam.microphoneActive = true
        let blockingDetector = BlockingMeetingDetector(result: true)
        let engine = harness.makeEngine(meetingDetector: blockingDetector)
        let tickCompleted = expectation(description: "tick completed")

        engine.tick { tickCompleted.fulfill() }
        XCTAssertEqual(blockingDetector.waitUntilStarted(), .success)
        engine.force(.available)
        blockingDetector.resume()

        wait(for: [tickCompleted], timeout: 2)
        XCTAssertEqual(harness.states, [.available])
        XCTAssertTrue(harness.snapshots.isEmpty)
        XCTAssertEqual(harness.luxafor.actions, [.off(harness.config.remoteWebhookUserId)])
        XCTAssertEqual(harness.voiceActivity.captureContextChanges, [true, false])
        XCTAssertFalse(harness.voiceActivity.isCapturing)
    }

    func test_tickCoalescesRequestWhileSignalPollIsInFlight() {
        let harness = PresenceEngineHarness()
        let blockingDetector = BlockingMeetingDetector(result: false)
        let engine = harness.makeEngine(meetingDetector: blockingDetector)
        let firstTickCompleted = expectation(description: "first tick completed")
        let coalescedTickCompleted = expectation(description: "coalesced tick completed")

        engine.tick { firstTickCompleted.fulfill() }
        XCTAssertEqual(blockingDetector.waitUntilStarted(), .success)
        engine.tick { coalescedTickCompleted.fulfill() }
        blockingDetector.resume()

        wait(for: [firstTickCompleted, coalescedTickCompleted], timeout: 2)
        XCTAssertEqual(blockingDetector.callCount, 1)
    }

    func test_tickReadsSignalsOffMainAndDeliversCallbacksOnMain() {
        let harness = PresenceEngineHarness()
        let detector = ThreadRecordingMeetingDetector()
        let engine = harness.makeEngine(meetingDetector: detector)
        let stateChanged = expectation(description: "state delivered")
        let snapshotDelivered = expectation(description: "snapshot delivered")
        engine.onStateChange = { state in
            harness.states.append(state)
            XCTAssertTrue(Thread.isMainThread)
            stateChanged.fulfill()
        }
        engine.onSnapshot = { snapshot in
            harness.snapshots.append(snapshot)
            XCTAssertTrue(Thread.isMainThread)
            snapshotDelivered.fulfill()
        }

        tickAndWait(engine)

        wait(for: [stateChanged, snapshotDelivered], timeout: 1)
        XCTAssertFalse(detector.wasCalledOnMainThread)
    }

    func test_reassertOutput_forcesConfirmedPhysicalPhase() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        let engine = harness.makeEngine()

        tickAndWait(engine)
        engine.reassertOutput()

        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .yellow(harness.config.remoteWebhookUserId),
                .forced(.yellow, harness.config.remoteWebhookUserId),
            ]
        )
        XCTAssertEqual(harness.outputs, [.solid(.yellow)])
    }

    func test_localHeartbeat_reassertsBlinkPhaseWithoutRestartingCadence() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        engine.prepare()
        tickAndWait(engine)
        let blinkHandler = harness.outputTimer.handler
        harness.localOutputHeartbeat.fire()

        XCTAssertEqual(harness.outputTimer.scheduledIntervals, [0.75])
        XCTAssertEqual(harness.localOutputHeartbeat.startCount, 1)
        XCTAssertNotNil(blinkHandler)
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .red(harness.config.remoteWebhookUserId),
                .forced(.red, harness.config.remoteWebhookUserId),
            ]
        )
    }

    func test_captureTimeQualifiedVoice_isAcceptedAfterMicrophoneMutesBeforePoll() throws {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = false
        let engine = harness.makeEngine()
        let recentVoiceApplied = expectation(description: "recent voice applied")
        engine.onStateChange = { state in
            harness.states.append(state)
            if state == .voiceRecent {
                recentVoiceApplied.fulfill()
            }
        }

        harness.voiceActivity.emitQualifyingActivity(at: harness.currentDate)

        wait(for: [recentVoiceApplied], timeout: 2)
        XCTAssertEqual(harness.states, [.voiceRecent])
        XCTAssertFalse(try XCTUnwrap(harness.snapshots.last).microphoneActive)
    }

    func test_resetVoiceTimer_withActiveZoom_returnsToYellow() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()
        tickAndWait(engine)
        let resetStateApplied = expectation(description: "reset state applied")
        engine.onStateChange = { state in
            harness.states.append(state)
            if state == .zoomQuiet {
                resetStateApplied.fulfill()
            }
        }

        engine.resetVoiceTimer()

        wait(for: [resetStateApplied], timeout: 2)
        XCTAssertEqual(harness.states, [.voiceRecent, .zoomQuiet])
        XCTAssertNil(harness.snapshots.last?.lastVoiceActivityDate)
    }

    func test_resetVoiceTimer_withMicrophoneOnly_returnsToOff() {
        let harness = PresenceEngineHarness()
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()
        tickAndWait(engine)
        let resetStateApplied = expectation(description: "reset state applied")
        engine.onStateChange = { state in
            harness.states.append(state)
            if state == .available, harness.states.count > 1 {
                resetStateApplied.fulfill()
            }
        }

        engine.resetVoiceTimer()

        wait(for: [resetStateApplied], timeout: 2)
        XCTAssertEqual(harness.states, [.voiceRecent, .available])
    }

    func test_resetDuringInFlightPoll_discardsPreResetVoiceResult() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        let blockingVoice = BlockingVoiceActivitySignal(
            lastActivityDate: harness.currentDate
        )
        let engine = harness.makeEngine(voiceActivity: blockingVoice)
        tickAndWait(engine)
        harness.currentDate = harness.currentDate.addingTimeInterval(301)
        blockingVoice.blockNextRead()
        let staleTickCompleted = expectation(description: "stale tick completed")
        let resetStateApplied = expectation(description: "reset state applied")
        engine.onStateChange = { state in
            harness.states.append(state)
            if state == .zoomQuiet {
                resetStateApplied.fulfill()
            }
        }

        engine.tick { staleTickCompleted.fulfill() }
        XCTAssertEqual(blockingVoice.waitUntilBlocked(), .success)
        engine.resetVoiceTimer()
        blockingVoice.resumeRead()

        wait(for: [staleTickCompleted, resetStateApplied], timeout: 2)
        XCTAssertEqual(harness.states, [.voiceRecent, .zoomQuiet])
        XCTAssertFalse(harness.states.contains(.voiceCooldown))
    }

    func test_sleepWake_reevaluatesBeforeRestartingAndReassertingOutput() {
        let harness = PresenceEngineHarness { config in
            config.recentVoiceBlinkSeconds = 5
            config.voiceCooldownSeconds = 5
        }
        harness.meetingDetector.isActive = true
        harness.micCam.microphoneActive = true
        harness.voiceActivity.lastActivityDate = harness.currentDate
        let engine = harness.makeEngine()

        tickAndWait(engine)
        let staleBlinkHandler = harness.outputTimer.handler
        harness.outputTimer.fire()
        engine.suspendOutput()
        staleBlinkHandler?()

        harness.currentDate = harness.currentDate.addingTimeInterval(6)
        harness.micCam.microphoneActive = false
        let wakeCompleted = expectation(description: "wake reevaluation completed")
        engine.resumeOutput { wakeCompleted.fulfill() }
        wait(for: [wakeCompleted], timeout: 2)

        XCTAssertEqual(harness.states, [.voiceRecent, .voiceCooldown])
        XCTAssertEqual(engine.desiredOutput, .solid(.red))
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .red(harness.config.remoteWebhookUserId),
                .off(harness.config.remoteWebhookUserId),
                .forced(.red, harness.config.remoteWebhookUserId),
            ]
        )
        XCTAssertGreaterThanOrEqual(harness.outputTimer.cancelCount, 3)
        XCTAssertEqual(harness.voiceActivity.resumeCount, 1)
        XCTAssertEqual(harness.localServiceRecoveryMonitor.startCount, 1)
        XCTAssertEqual(harness.localOutputHeartbeat.startCount, 1)
    }

    func test_wakeDuringPreSleepPoll_waitsForDistinctFreshEvaluationBeforeReasserting() {
        let harness = PresenceEngineHarness()
        let detector = OneShotBlockingMeetingDetector(initialResult: true)
        let engine = harness.makeEngine(meetingDetector: detector)

        tickAndWait(engine)
        detector.blockNextCall()
        let stalePollCompleted = expectation(description: "stale pre-sleep poll completed")
        engine.tick { stalePollCompleted.fulfill() }
        XCTAssertEqual(detector.waitUntilBlocked(), .success)

        engine.suspendOutput()
        detector.result = false
        let wakeCompleted = expectation(description: "fresh wake evaluation completed")
        engine.resumeOutput { wakeCompleted.fulfill() }
        detector.resumeBlockedCall()

        wait(for: [stalePollCompleted, wakeCompleted], timeout: 2)
        XCTAssertEqual(detector.callCount, 3)
        XCTAssertEqual(harness.states, [.zoomQuiet, .available])
        XCTAssertEqual(engine.desiredOutput, .off)
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .yellow(harness.config.remoteWebhookUserId),
                .forced(.off, harness.config.remoteWebhookUserId),
            ]
        )
    }

    func test_secondSleepDuringWakePoll_doesNotResumeOutputOrRecovery() {
        let harness = PresenceEngineHarness()
        let detector = OneShotBlockingMeetingDetector(initialResult: true)
        let engine = harness.makeEngine(meetingDetector: detector)
        tickAndWait(engine)
        engine.suspendOutput()
        detector.blockNextCall()
        let wakeCompleted = expectation(description: "stale wake completion")
        engine.resumeOutput { wakeCompleted.fulfill() }
        XCTAssertEqual(detector.waitUntilBlocked(), .success)

        engine.suspendOutput()
        detector.resumeBlockedCall()

        wait(for: [wakeCompleted], timeout: 2)
        XCTAssertEqual(
            harness.luxafor.actions,
            [.yellow(harness.config.remoteWebhookUserId)]
        )
        XCTAssertEqual(harness.voiceActivity.suspendCount, 2)
        XCTAssertEqual(harness.voiceActivity.resumeCount, 0)
        XCTAssertEqual(harness.localOutputHeartbeat.startCount, 0)
        XCTAssertEqual(harness.localOutputHeartbeat.stopCount, 0)
    }

    func test_clearForceDuringWakePoll_waitsForFinalAutomaticEvaluationBeforeReasserting() {
        let harness = PresenceEngineHarness()
        let detector = OneShotBlockingMeetingDetector(initialResult: true)
        let engine = harness.makeEngine(meetingDetector: detector)

        tickAndWait(engine)
        engine.suspendOutput()
        detector.blockNextCall()
        let wakeCompleted = expectation(description: "wake reevaluation completed")
        engine.resumeOutput { wakeCompleted.fulfill() }
        XCTAssertEqual(detector.waitUntilBlocked(), .success)

        engine.force(.voiceCooldown)
        engine.clearForce()
        detector.result = false
        detector.resumeBlockedCall()

        wait(for: [wakeCompleted], timeout: 2)
        XCTAssertEqual(detector.callCount, 3)
        XCTAssertEqual(
            harness.states,
            [.zoomQuiet, .voiceCooldown, .zoomQuiet, .available]
        )
        XCTAssertEqual(engine.desiredOutput, .off)
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .yellow(harness.config.remoteWebhookUserId),
                .forced(.off, harness.config.remoteWebhookUserId),
            ]
        )
    }

    func test_recoveryLifecycle_startsReassertsSuspendsResumesAndRejectsShutdownCallbacks() {
        let harness = PresenceEngineHarness()
        harness.meetingDetector.isActive = true
        let engine = harness.makeEngine()

        engine.prepare()
        tickAndWait(engine)
        harness.localServiceRecoveryMonitor.reconnect()
        engine.suspendOutput()

        let wakeCompleted = expectation(description: "wake recovery resumed")
        engine.resumeOutput { wakeCompleted.fulfill() }
        wait(for: [wakeCompleted], timeout: 2)
        engine.shutdownOutput()
        harness.localServiceRecoveryMonitor.reconnect()
        harness.localOutputHeartbeat.fire()

        XCTAssertEqual(harness.localServiceRecoveryMonitor.startCount, 2)
        XCTAssertEqual(harness.localServiceRecoveryMonitor.stopCount, 2)
        XCTAssertEqual(harness.localOutputHeartbeat.startCount, 2)
        XCTAssertEqual(harness.localOutputHeartbeat.stopCount, 2)
        XCTAssertEqual(
            harness.luxafor.actions,
            [
                .yellow(harness.config.remoteWebhookUserId),
                .forced(.yellow, harness.config.remoteWebhookUserId),
                .forced(.yellow, harness.config.remoteWebhookUserId),
                .forced(.off, harness.config.remoteWebhookUserId),
            ]
        )
    }

    func test_localWebhookReachability_isExposedForMenuDiagnostics() {
        let harness = PresenceEngineHarness()
        let engine = harness.makeEngine()
        var observedReachability: [Bool] = []
        engine.onLocalWebhookReachabilityChange = {
            observedReachability.append($0)
        }

        harness.localServiceRecoveryMonitor.reportReachability(false)
        harness.localServiceRecoveryMonitor.reportReachability(true)

        XCTAssertEqual(observedReachability, [false, true])
    }

    private func tickAndWait(
        _ engine: PresenceEngine,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tickCompleted = expectation(description: "tick completed")
        engine.tick { tickCompleted.fulfill() }
        wait(for: [tickCompleted], timeout: 2)
    }
}

// MARK: - Harness

private final class PresenceEngineHarness {
    var config: PresenceEngine.Config
    let micCam = FakeMicCamSignal()
    let meetingDetector = FakeMeetingDetector()
    let voiceActivity = FakeVoiceActivitySignal()
    let luxafor = FakeLuxaforClient()
    let outputTimer = FakeLightOutputTimer()
    let localServiceRecoveryMonitor = FakeLocalServiceRecoveryMonitor()
    let localOutputHeartbeat = FakeLocalOutputHeartbeat()
    var currentDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var states: [PresenceState] = []
    var snapshots: [PresenceSnapshot] = []
    var outputs: [LightOutput] = []

    init(configure: (inout PresenceEngine.Config) -> Void = { _ in }) {
        var config = PresenceEngine.Config(values: [:])
        configure(&config)
        self.config = config
    }

    func makeEngine(
        meetingDetector: MeetingDetectorProtocol? = nil,
        voiceActivity: VoiceActivitySignalProtocol? = nil
    ) -> PresenceEngine {
        let engine = PresenceEngine(
            config: config,
            micCam: micCam,
            meetingDetector: meetingDetector ?? self.meetingDetector,
            voiceActivity: voiceActivity ?? self.voiceActivity,
            luxafor: luxafor,
            outputTimer: outputTimer,
            localServiceRecoveryMonitor: localServiceRecoveryMonitor,
            localOutputHeartbeat: localOutputHeartbeat,
            now: { [unowned self] in currentDate }
        )
        engine.onStateChange = { [weak self] state in
            self?.states.append(state)
        }
        engine.onSnapshot = { [weak self] snapshot in
            self?.snapshots.append(snapshot)
        }
        engine.onOutputChange = { [weak self] output in
            self?.outputs.append(output)
        }
        return engine
    }
}

// MARK: - Test Doubles

private final class FakeMicCamSignal: MicCamSignalProtocol {
    var microphoneActive = false
    private(set) var microphoneReadCount = 0

    func isMicrophoneInUseByAnotherApplication() -> Bool {
        microphoneReadCount += 1
        return microphoneActive
    }
}

private final class FakeMeetingDetector: MeetingDetectorProtocol {
    var name: String { "Fake Zoom" }
    var isActive = false
    private(set) var callCount = 0

    func isMeetingActive() -> Bool {
        callCount += 1
        return isActive
    }
}

private final class BlockingMeetingDetector: MeetingDetectorProtocol {
    var name: String { "Blocking Zoom" }

    private let result: Bool
    private let started = DispatchSemaphore(value: 0)
    private let resumeSignal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0

    init(result: Bool) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func isMeetingActive() -> Bool {
        lock.lock()
        calls += 1
        lock.unlock()
        started.signal()
        _ = resumeSignal.wait(timeout: .now() + 2)
        return result
    }

    func waitUntilStarted() -> DispatchTimeoutResult {
        started.wait(timeout: .now() + 1)
    }

    func resume() {
        resumeSignal.signal()
    }
}

private final class OneShotBlockingMeetingDetector: MeetingDetectorProtocol {
    var name: String { "One-shot Blocking Zoom" }

    private let lock = NSLock()
    private let blocked = DispatchSemaphore(value: 0)
    private let resumeSignal = DispatchSemaphore(value: 0)
    private var shouldBlockNextCall = false
    private var calls = 0
    private var storedResult: Bool

    init(initialResult: Bool) {
        storedResult = initialResult
    }

    var result: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedResult
        }
        set {
            lock.lock()
            storedResult = newValue
            lock.unlock()
        }
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func blockNextCall() {
        lock.lock()
        shouldBlockNextCall = true
        lock.unlock()
    }

    func isMeetingActive() -> Bool {
        lock.lock()
        calls += 1
        let capturedResult = storedResult
        let shouldBlock = shouldBlockNextCall
        shouldBlockNextCall = false
        lock.unlock()

        if shouldBlock {
            blocked.signal()
            _ = resumeSignal.wait(timeout: .now() + 2)
        }
        return capturedResult
    }

    func waitUntilBlocked() -> DispatchTimeoutResult {
        blocked.wait(timeout: .now() + 1)
    }

    func resumeBlockedCall() {
        resumeSignal.signal()
    }
}

private final class ThreadRecordingMeetingDetector: MeetingDetectorProtocol {
    var name: String { "Thread Recording Zoom" }
    private(set) var wasCalledOnMainThread = true

    func isMeetingActive() -> Bool {
        wasCalledOnMainThread = Thread.isMainThread
        return false
    }
}

private final class FakeLuxaforClient: LuxaforClientProtocol {
    enum Action: Equatable {
        case red(String)
        case yellow(String)
        case off(String)
        case forced(LuxaforColor, String)
        case custom(LuxaforColor, String)
    }

    private(set) var actions: [Action] = []

    func setSolidColor(_ color: LuxaforColor, userId: String, force: Bool) {
        if force {
            actions.append(.forced(color, userId))
        } else if color == .red {
            actions.append(.red(userId))
        } else if color == .yellow {
            actions.append(.yellow(userId))
        } else if color == .off {
            actions.append(.off(userId))
        } else {
            actions.append(.custom(color, userId))
        }
    }
}

private final class FakeLightOutputTimer: LightOutputTimerProtocol {
    private(set) var scheduledIntervals: [TimeInterval] = []
    private(set) var cancelCount = 0
    private(set) var handler: (() -> Void)?

    func schedule(every interval: TimeInterval, handler: @escaping () -> Void) {
        scheduledIntervals.append(interval)
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func fire() {
        handler?()
    }
}

private final class FakeVoiceActivitySignal: VoiceActivitySignalProtocol {
    var onQualifyingActivity: ((Date) -> Void)?
    var active = false
    var lastActivityDate: Date?
    private(set) var isCapturing = false
    private(set) var captureContextRequests: [Bool] = []
    private(set) var captureContextChanges: [Bool] = []
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0
    private(set) var resetCount = 0
    private var captureContextActive = false
    private var isSuspended = false

    func requestAccessIfNeeded() {}

    func setCaptureContextActive(_ active: Bool) {
        captureContextRequests.append(active)
        guard captureContextActive != active else { return }
        captureContextActive = active
        captureContextChanges.append(active)
        isCapturing = active && !isSuspended
        if !active {
            self.active = false
        }
    }

    func isVoiceActive() -> Bool {
        active
    }

    var lastVoiceActivityDate: Date? {
        lastActivityDate
    }

    func suspend() {
        suspendCount += 1
        isSuspended = true
        isCapturing = false
        active = false
    }

    func resume() {
        resumeCount += 1
        isSuspended = false
        isCapturing = captureContextActive
    }

    func reset() {
        resetCount += 1
        active = false
        lastActivityDate = nil
    }

    func emitQualifyingActivity(at date: Date) {
        lastActivityDate = date
        onQualifyingActivity?(date)
    }
}

private final class FakeLocalServiceRecoveryMonitor: LocalServiceRecoveryMonitoring {
    var onReconnect: (() -> Void)?
    var onReachabilityChange: ((Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startCount += 1
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
    }

    func reconnect() {
        onReconnect?()
    }

    func reportReachability(_ reachable: Bool) {
        onReachabilityChange?(reachable)
    }
}

private final class FakeLocalOutputHeartbeat: LocalOutputHeartbeating {
    var onHeartbeat: (() -> Void)?
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startCount += 1
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
    }

    func fire() {
        onHeartbeat?()
    }
}

private final class BlockingVoiceActivitySignal: VoiceActivitySignalProtocol {
    var onQualifyingActivity: ((Date) -> Void)?
    var isCapturing: Bool { false }

    private let blocked = DispatchSemaphore(value: 0)
    private let resumeSignal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var shouldBlockNextRead = false
    private var storedActivityDate: Date?

    init(lastActivityDate: Date?) {
        storedActivityDate = lastActivityDate
    }

    var lastVoiceActivityDate: Date? {
        lock.lock()
        let capturedDate = storedActivityDate
        let shouldBlock = shouldBlockNextRead
        shouldBlockNextRead = false
        lock.unlock()
        if shouldBlock {
            blocked.signal()
            _ = resumeSignal.wait(timeout: .now() + 2)
        }
        return capturedDate
    }

    func requestAccessIfNeeded() {}
    func setCaptureContextActive(_ active: Bool) {}
    func isVoiceActive() -> Bool { false }
    func suspend() {}
    func resume() {}

    func reset() {
        lock.lock()
        storedActivityDate = nil
        lock.unlock()
    }

    func blockNextRead() {
        lock.lock()
        shouldBlockNextRead = true
        lock.unlock()
    }

    func waitUntilBlocked() -> DispatchTimeoutResult {
        blocked.wait(timeout: .now() + 1)
    }

    func resumeRead() {
        resumeSignal.signal()
    }
}
