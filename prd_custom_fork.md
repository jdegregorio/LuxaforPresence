# Product Requirements Document: Family Office Presence Light

**Project:** LuxaforPresence Custom Fork
**Working name:** Family Presence Light
**Version:** 0.1
**Platform:** macOS 13 or later
**Hardware:** Luxafor Flag / Flag 2
**Source project:** `kantselovich/LuxaforPresence`

## 1. Product summary

Create a minimal fork of LuxaforPresence that gives family members a simple visual indication of whether the user can be interrupted or pass through the home office.

The light will distinguish among:

1. A Zoom meeting where the user has not spoken recently
2. A meeting or microphone session where the user has spoken recently
3. A cooldown period after recent speaking
4. No relevant meeting or microphone activity

The application must operate locally on the Mac, run as a menu-bar application, start automatically at login, and avoid recording or transmitting microphone audio.

## 2. Background

LuxaforPresence is already designed to show family members whether a Mac user is on a call. It includes:

* Zoom process-based meeting detection
* Native macOS microphone and camera detection
* Voice activity detection using `AVAudioEngine`
* A timestamp for the most recent detected voice activity
* Local and remote Luxafor webhook transports
* A configurable state engine
* Manual menu-bar controls
* Logging and unit-test infrastructure

The current application maps an active meeting with voice activity to red, an active but quiet meeting to yellow, and no meeting to off. It already separates meeting detection from voice activity and exposes `lastVoiceActivityDate`, making it a strong foundation for this fork.

The existing VAD uses an `AVAudioEngine` input tap, calculates RMS energy from small audio buffers, compares it with a configurable threshold, and updates `lastActivity` when the threshold is exceeded. No recorded audio needs to be stored.

## 3. Product objective

Provide a visual signal outside the office that answers:

> “Can I come through the office or interrupt right now?”

The first release should favor predictable and understandable behavior over extensive application integrations.

## 4. User-facing status meanings

### Light off: Available

The user is not known to be in a Zoom meeting and has not generated a qualifying recent voice signal in an active microphone context.

**Family interpretation:** It is generally okay to enter or interrupt.

### Solid yellow: On Zoom, currently quiet

A Zoom meeting is active, but the user has not produced a qualifying microphone signal within the previous ten minutes.

This includes:

* A newly started Zoom meeting
* A Zoom meeting where the user has remained muted
* A meeting where the user last spoke more than ten minutes ago

**Family interpretation:** The user is in a meeting, but cautiously passing through the office is probably okay. Avoid unnecessary interruption.

### Flashing red: Actively engaged or recently speaking

A qualifying audio signal was detected while the microphone was active, and fewer than five minutes have elapsed since the most recent qualifying signal.

Every new qualifying signal resets the five-minute timer.

**Family interpretation:** Do not enter or interrupt except for something urgent.

### Solid red: Recent-speaking cooldown

Between five and ten minutes have elapsed since the most recent qualifying audio signal.

Every new qualifying signal immediately returns the light to flashing red and restarts the five-minute timer.

**Family interpretation:** The user may still be engaged in an important conversation. Avoid interruption, but the situation is less restrictive than flashing red.

## 5. State precedence

The application must evaluate states in this order:

1. Manual override
2. Recent voice signal: less than five minutes ago
3. Voice cooldown: five through ten minutes ago
4. Active Zoom meeting
5. Available

The resulting logic is:

```text
IF manual override is active:
    display the selected manual state

ELSE IF communication context is active
        AND last qualifying voice signal was less than 5 minutes ago:
    flash red

ELSE IF communication context is active
        AND last qualifying voice signal was 5–10 minutes ago:
    show solid red

ELSE IF Zoom meeting is active:
    show solid yellow

ELSE:
    turn light off
```

## 6. Communication-context definition

A communication context is active when either:

* A Zoom meeting is detected, or
* macOS reports that an input microphone device is currently in use

This allows the red voice states to work even when Zoom detection temporarily fails or when another application is using the microphone.

Microphone use without a qualifying audio signal must not independently change the light.

Examples:

| Situation                                                   | Output       |
| ----------------------------------------------------------- | ------------ |
| Zoom active, muted, never spoke                             | Yellow       |
| Zoom active, microphone open, silence                       | Yellow       |
| Zoom active, voice detected 30 seconds ago                  | Flashing red |
| Zoom active, voice detected 7 minutes ago                   | Solid red    |
| Zoom active, voice detected 12 minutes ago                  | Yellow       |
| Microphone active outside Zoom, silence                     | Off          |
| Microphone active outside Zoom, voice detected 1 minute ago | Flashing red |
| Zoom and microphone both inactive                           | Off          |

## 7. Session termination behavior

When Zoom is no longer active and macOS no longer reports microphone use:

* Immediately turn the light off
* Stop any active flashing timer
* Retain the last voice timestamp internally only for diagnostics
* Do not display the remaining five- or ten-minute cooldown

This prevents the office from appearing unavailable for ten minutes after a call has ended.

If Zoom remains active but the user mutes the microphone after speaking, the red timeline continues. This is intentional: muting does not necessarily mean the conversation or presentation has ended.

## 8. Voice-signal requirements

### 8.1 Definition

A qualifying voice signal is an audio input signal that:

1. Occurs while macOS reports that an input microphone is active
2. Exceeds the configured RMS threshold
3. Meets the debounce requirements below

The system is detecting meaningful microphone energy, not semantically proving that the sound is human speech.

### 8.2 Initial threshold

Retain the existing default VAD threshold:

```text
vadThreshold = 0.02
```

The threshold must remain configurable through `config.plist`.

### 8.3 Debouncing

To reduce triggers from isolated clicks, bumps, or short keyboard noise, a qualifying signal should require either:

* At least 250 milliseconds of cumulative above-threshold audio within a rolling one-second window, or
* At least three consecutive above-threshold audio buffers

The engineering team may select the simpler implementation for v1.

Once a qualifying event occurs, `lastVoiceActivityDate` should be updated continuously or at least once per second while above-threshold audio continues.

### 8.4 Cooldown timing

Configure two durations:

```text
recentVoiceBlinkSeconds = 300
voiceCooldownSeconds = 300
```

Interpretation:

* `0–300 seconds` after the last signal: flashing red
* `300–600 seconds` after the last signal: solid red
* More than `600 seconds`: return to the underlying Zoom or available state

Durations must be independently configurable for testing.

### 8.5 Audio privacy

The application must:

* Process audio buffers only in memory
* Never save raw audio
* Never transmit audio
* Never perform speech-to-text
* Never log individual samples
* Store only derived state, RMS values when debug logging is enabled, and the last qualifying timestamp

The existing application already states that microphone access is used for local voice-activity analysis rather than recording.

## 9. Flashing behavior

### 9.1 Appearance

Default flashing-red pattern:

```text
Red: 750 milliseconds
Off: 750 milliseconds
Repeat continuously
```

The exact interval should be configurable:

```text
blinkIntervalMilliseconds = 750
```

The transition into flashing red should begin within one second of a qualifying signal.

### 9.2 Implementation preference

Use the following priority:

1. Native Luxafor blink or strobe command, if supported by the selected local transport
2. Application-managed blinking using a dedicated timer
3. Remote Luxafor webhook effect only as a fallback

The current local webhook client supports posting solid RGB colors but does not currently expose a blink method. It sends a color value to the local `/color` endpoint and retries failed requests.

If software-controlled flashing is required:

* Do not tie flashing to the two-second presence polling interval
* Use a dedicated dispatch timer
* Start the timer only when entering the flashing state
* Cancel it immediately when leaving the flashing state
* Avoid creating multiple concurrent timers
* Do not resend a color when the desired output has not changed

## 10. Proposed state model

Replace or extend the existing `PresenceState` with:

```swift
enum PresenceState: String {
    case available
    case zoomQuiet
    case voiceRecent
    case voiceCooldown
    case unknown
}
```

Suggested output mapping:

```swift
available      -> off
zoomQuiet      -> solid yellow
voiceRecent    -> flashing red
voiceCooldown  -> solid red
unknown        -> off
```

A separate presentation model may be preferable:

```swift
enum LightOutput: Equatable {
    case off
    case solid(red: UInt8, green: UInt8, blue: UInt8)
    case blink(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        interval: TimeInterval
    )
}
```

Keeping presence state separate from light behavior will make future changes easier.

## 11. Proposed state-engine pseudocode

```swift
func evaluateState(now: Date) -> PresenceState {
    if let forcedState {
        return forcedState
    }

    let zoomActive = zoomMeetingDetector.isMeetingActive()
    let microphoneActive = micCam.isMicrophoneInUse()
    let communicationContextActive = zoomActive || microphoneActive

    guard communicationContextActive else {
        return .available
    }

    if let lastVoiceAt = voiceActivity.lastVoiceActivityDate {
        let elapsed = now.timeIntervalSince(lastVoiceAt)

        if elapsed < recentVoiceBlinkSeconds {
            return .voiceRecent
        }

        if elapsed < recentVoiceBlinkSeconds + voiceCooldownSeconds {
            return .voiceCooldown
        }
    }

    if zoomActive {
        return .zoomQuiet
    }

    return .available
}
```

A qualifying voice event must only update `lastVoiceActivityDate` when the microphone is actually in use.

## 12. Existing code to reuse

### `PresenceEngine.swift`

Reuse:

* Config loading
* Polling lifecycle
* Injected `now` function
* Meeting detector
* Microphone detector
* Voice activity signal
* Manual forced state
* State-change callback
* Output deduplication

The engine already accepts an injected clock and protocol-backed dependencies, making deterministic state-machine tests straightforward.

Modify:

* Existing state-decision hierarchy
* State definitions
* Output mappings
* Cooldown configuration
* Communication-context logic

### `VoiceActivitySignal.swift`

Reuse:

* `AVAudioEngine`
* Microphone authorization
* RMS calculation
* Threshold configuration
* Thread-safe `lastVoiceActivityDate`

Modify:

* Add debounce logic
* Optionally expose current RMS for diagnostics
* Ensure signals are ignored when no microphone input is considered active
* Add a testable buffer-processing abstraction if practical

### Zoom meeting detector

Reuse the existing Zoom detector for the baseline yellow state.

The source project identifies Zoom detection as process-based and implemented, although it still notes that more testing is needed.

For v1, do not add calendar, Teams, Slack, Webex, Google Meet, camera, or screen-sharing logic to the product state machine.

Unused detectors may remain in the source tree, but they should be disabled by default.

### Luxafor transport

Reuse:

* Local webhook endpoint
* Authentication token
* Retry behavior
* Remote-webhook fallback

Modify the transport abstraction so it supports:

```swift
func setSolidColor(_ color: RGBColor)
func startBlinking(_ color: RGBColor, interval: TimeInterval)
func turnOff()
```

Alternatively, introduce:

```swift
func apply(_ output: LightOutput)
```

## 13. Configuration

Add the following values to `config.plist`:

```xml
<key>recentVoiceBlinkSeconds</key>
<real>300</real>

<key>voiceCooldownSeconds</key>
<real>300</real>

<key>blinkIntervalMilliseconds</key>
<integer>750</integer>

<key>vadThreshold</key>
<real>0.02</real>

<key>vadMinimumActiveMilliseconds</key>
<integer>250</integer>

<key>detectZoom</key>
<true/>

<key>detectOtherMeetingApps</key>
<false/>

<key>useCalendar</key>
<false/>

<key>useCamera</key>
<false/>
```

For development and automated tests, allow five-minute durations to be replaced with values such as five and ten seconds.

## 14. Menu-bar interface

The menu-bar application should display:

* Current state
* Current Luxafor output
* Whether Zoom is active
* Whether the microphone is in use
* Whether audio energy is currently above threshold
* Time since the last qualifying voice signal
* Remaining flashing-red time
* Remaining solid-red cooldown time

Example:

```text
Status: Flashing Red
Zoom: Active
Microphone: In Use
Voice Signal: Active
Last Voice: 12 seconds ago
Flashing Ends In: 4m 48s
```

Retain manual overrides:

* Automatic
* Available / Off
* Zoom Quiet / Yellow
* Voice Recent / Flashing Red
* Voice Cooldown / Solid Red

Include a “Reset Voice Timer” action for debugging and recovery.

## 15. macOS permissions

The minimal v1 application should require:

* Microphone permission for local audio-energy analysis

It may require additional permission depending on how Zoom detection is implemented.

Disable requests for permissions that are not needed in v1:

* Camera
* Calendar
* Browser automation
* Accessibility, unless required by the final Zoom detector

Use a stable bundle identifier and code signature so macOS privacy grants remain stable between builds.

Running through `swift run` may associate permissions with Terminal rather than the packaged application, as noted by the source project. Final validation must use a packaged `.app`.

## 16. Functional acceptance criteria

### Zoom baseline

1. Starting a Zoom meeting with no detected voice turns the light solid yellow within three seconds.
2. Remaining muted and silent keeps the light yellow.
3. Leaving Zoom turns the light off within three seconds, provided no other microphone session is active.

### Voice-triggered flashing

4. A qualifying signal while the microphone is active turns the light flashing red within one second.
5. Additional qualifying signals reset the five-minute flashing period.
6. Muting after speaking does not cancel the flashing period while Zoom remains active.
7. The flashing controller maintains a stable visual cadence without accumulating timers.

### Cooldown

8. Five minutes after the last qualifying signal, the light transitions from flashing red to solid red.
9. A new qualifying signal during solid red immediately restores flashing red and restarts the timer.
10. Ten minutes after the last qualifying signal, the light becomes yellow if Zoom is still active.
11. Ten minutes after the last qualifying signal, the light turns off if Zoom is not active.

### Ending a session

12. When both Zoom and microphone use end, the light immediately turns off even when a red timer would otherwise remain.
13. Closing and reopening the application does not restore stale red cooldown state.

### False-positive controls

14. Microphone use without above-threshold audio does not activate red.
15. An isolated sub-debounce sound does not activate red.
16. The VAD threshold can be changed without recompiling the application.

### Privacy

17. No audio file is created.
18. No audio buffer or speech content is transmitted.
19. Debug logs contain only state transitions, timestamps, device state, and optional numerical RMS values.

## 17. Unit-test requirements

Use mocked implementations of:

* `MeetingDetectorProtocol`
* `MicCamSignalProtocol`
* `VoiceActivitySignalProtocol`
* `LuxaforClientProtocol`
* Clock/`now`

Required test cases:

```text
Zoom active + no voice                          -> zoomQuiet
Zoom inactive + mic inactive                    -> available
Mic active + no voice                           -> available
Voice 1 second ago + context active             -> voiceRecent
Voice 299 seconds ago + context active          -> voiceRecent
Voice 301 seconds ago + context active          -> voiceCooldown
Voice 599 seconds ago + context active          -> voiceCooldown
Voice 601 seconds ago + Zoom active             -> zoomQuiet
Voice 601 seconds ago + Zoom inactive           -> available
Voice recent + no communication context         -> available
New voice during cooldown                       -> voiceRecent
Manual override                                 -> forced state
No state change                                 -> no duplicate output call
```

The existing `PresenceEngine` clock injection should be retained to make boundary tests deterministic.

## 18. Integration-test requirements

Test with:

* MacBook built-in microphone
* AirPods or another Bluetooth headset
* External USB microphone, when available
* Zoom muted and unmuted
* Zoom with microphone device open while muted
* Zoom meeting ended without quitting the Zoom application
* Microphone device switching during a call
* Mac sleep and wake
* Luxafor disconnected and reconnected
* Luxafor desktop application restarted
* Application restarted while Zoom remains active

Confirm whether the Flag 2 responds correctly to:

* Solid yellow
* Solid red
* Rapid repeated local-webhook color commands
* Any native blink endpoint or pattern command

## 19. Observability

Log state transitions in a structured form:

```text
previousState
newState
zoomActive
microphoneActive
voiceCurrentlyAboveThreshold
lastVoiceActivityDate
secondsSinceVoiceActivity
decisionPath
outputMode
```

Example:

```text
State transition:
zoomQuiet -> voiceRecent
decisionPath=recentVoice
zoomActive=true
microphoneActive=true
secondsSinceVoiceActivity=0.4
output=blinkRed
```

Do not log every audio buffer. At most, log threshold crossings and periodic summaries in debug mode.

## 20. Reliability requirements

* The app must recover if the Luxafor desktop app launches after the presence app.
* Failed webhook commands should be retried using existing retry behavior.
* The app must resend the desired output after Luxafor reconnects.
* Only the most recent requested output may remain active after retries.
* Sleep/wake must cause immediate state reevaluation.
* The flashing timer must stop during sleep and recompute the correct state after wake.
* CPU usage should remain negligible during idle operation.
* Audio processing should not materially affect battery life or Zoom audio quality.

## 21. Non-goals for v1

The following are explicitly outside the initial scope:

* Semantic speech recognition
* Speaker identification
* Determining whether Zoom’s internal mute button is enabled
* Calendar integration
* Camera detection
* Teams, Slack, Webex, FaceTime, or Google Meet-specific states
* Home Assistant integration
* Cloud-hosted state management
* Multiple Luxafor devices
* Mobile controls
* Persisting cooldown state across application restarts
* Family-facing text displays or notifications

## 22. Known limitations

The existing VAD measures microphone energy rather than conclusively identifying human speech. Potential triggers include:

* Keyboard noise
* Desk impacts
* Children speaking near the office
* Audio played through speakers and captured by the microphone
* HVAC or fan noise
* Virtual audio devices

The microphone-in-use guard, debounce duration, and configurable RMS threshold should reduce but will not eliminate these cases.

A later version could adopt a true speech-oriented VAD such as WebRTC VAD or an Apple audio-analysis API. That is not required for the initial fork.

## 23. Suggested implementation sequence

### Phase 1: State engine

1. Add the new presence states.
2. Add the two cooldown durations.
3. Implement the state precedence rules.
4. Add deterministic unit tests.
5. Map yellow and solid-red outputs using the existing transport.

### Phase 2: Flash controller

1. Test for a native Luxafor local blink command.
2. If unavailable, implement a dedicated software flash timer.
3. Ensure timer cancellation and state deduplication.
4. Test disconnect and reconnect behavior.

### Phase 3: VAD hardening

1. Gate qualifying signals on microphone-in-use state.
2. Add minimum signal duration or consecutive-buffer debounce.
3. Add threshold configuration.
4. Validate with the built-in microphone and the user’s normal headset.

### Phase 4: Menu and packaging

1. Add status and timer diagnostics to the menu.
2. Retain manual overrides.
3. Disable unnecessary permissions and detectors.
4. Package and sign the application.
5. Configure launch at login.
6. Conduct real-world testing outside the office door.

## 24. Definition of done

The release is complete when:

* The application reliably detects an active Zoom meeting
* A quiet Zoom meeting produces solid yellow
* Qualifying microphone activity produces flashing red
* Flashing red lasts five minutes from the most recent qualifying signal
* Solid red follows for another five minutes
* New voice activity resets the timeline
* Ending the communication context turns the light off
* The app runs automatically at login
* No audio is stored or transmitted
* Automated tests cover all timing boundaries and state transitions
* The behavior works for at least one full week of normal work calls without unacceptable false positives
