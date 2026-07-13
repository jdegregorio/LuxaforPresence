# LuxaforPresence for macOS

LuxaforPresence is a local macOS menu-bar app that turns a Luxafor Flag into a simple family office presence light.

| Light | Meaning |
| --- | --- |
| Off | No active Zoom meeting or qualifying voice activity in an active microphone context |
| Solid yellow | Zoom is active, but no qualifying voice signal occurred in the last ten minutes |
| Flashing red | Qualifying microphone energy occurred in the last five minutes |
| Solid red | The last qualifying signal was five to ten minutes ago |

The red timeline continues while either Zoom or external microphone use keeps the communication context active. When both end, the light turns off immediately. A new qualifying signal restarts the five-minute flashing period.

## Privacy and permissions

The packaged app requests only **Microphone** permission. `AVAudioEngine` calculates RMS energy from short in-memory buffers. It never records, stores, transmits, or transcribes audio, and it never logs individual audio samples.

Zoom detection is process-based (`CptHost`) and does not require Accessibility, Calendar, Camera, browser automation, or Apple Events permissions.

Use the packaged and signed app for final permission testing. `swift run` is an unpackaged development process, so macOS may attribute its microphone permission to the parent terminal.

## Install and launch at login

1. Open the DMG and drag **LuxaforPresence.app** onto the **Applications** shortcut.
2. Launch the installed copy from `/Applications` or `~/Applications`.
3. Approve Microphone access.

The installed app registers itself with `SMAppService.mainApp` on first launch. Use **Launch at Login** in the menu to opt out or re-enable it. If macOS requires approval, the menu opens System Settings → General → Login Items. Registration is intentionally unavailable from a mounted DMG, App Translocation, or `swift run`.

## Luxafor transport

Both LuxaforPresence and the Luxafor macOS desktop app 2.5.32 or later must be running. In the Luxafor app, enable **Incoming Local Webhooks** and make its port and security token match `localWebhookBaseUrl` and `localWebhookToken`. Local webhook transport is the default:

```text
http://127.0.0.1:5383/color
```

Failed requests use latest-wins retry behavior. A five-second listener probe reasserts output after an observed desktop-service recovery. Because the documented local API exposes no device-health endpoint, local transport also forces the current physical phase every 30 seconds by default; semantic state/output changes remain deduplicated. The liveness monitor, heartbeat, flashing timer, VAD, and polling pause during sleep.

Remote webhook transport remains available as a fallback and requires a non-placeholder `remoteWebhookUserId`.

## Menu diagnostics and controls

The menu shows the current state and Luxafor output, Zoom and external microphone status, current above-threshold energy, last qualifying voice time, and remaining flashing/cooldown time.

Manual choices take precedence over automatic detection:

- Automatic
- Available / Off
- Zoom Quiet / Yellow
- Voice Recent / Flashing Red
- Voice Cooldown / Solid Red
- Reset Voice Timer

## Configuration

Choose **Open Configuration File…** to create and reveal `~/.config/LuxaforPresence/config.plist`. Restart the app after editing.

```xml
<dict>
    <key>transportMode</key>
    <string>local</string>
    <key>localWebhookBaseUrl</key>
    <string>http://127.0.0.1:5383</string>
    <key>localWebhookToken</key>
    <string>luxafor</string>
    <key>remoteWebhookUserId</key>
    <string>YOUR_USER_ID_HERE</string>
    <key>pollInterval</key>
    <real>2</real>
    <key>detectZoom</key>
    <true/>
    <key>vadEnabled</key>
    <true/>
    <key>vadThreshold</key>
    <real>0.02</real>
    <key>vadMinimumActiveMilliseconds</key>
    <integer>250</integer>
    <key>recentVoiceBlinkSeconds</key>
    <real>300</real>
    <key>voiceCooldownSeconds</key>
    <real>300</real>
    <key>blinkIntervalMilliseconds</key>
    <integer>750</integer>
    <key>localOutputReassertSeconds</key>
    <integer>30</integer>
</dict>
```

Numeric values are validated at startup. `pollInterval` must be at least 0.25 seconds, `vadThreshold` must be greater than 0 and at most 1, `vadMinimumActiveMilliseconds` must be at least 250, voice durations must be non-negative, `blinkIntervalMilliseconds` must be at least 100, and `localOutputReassertSeconds` must be at least 5.

## Development

Requires macOS 13+, Swift 5.7+, and Xcode 14.3+ or matching Command Line Tools.

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.cache swift build --disable-sandbox
swift test
./scripts/package-dmg.sh
```

The packaging script builds a release app and emits `dist/LuxaforPresence.dmg`. For a trusted distribution, follow [DIST.md](DIST.md) to Developer ID-sign, notarize, staple, and verify the app and DMG.

Structured logs contain only derived state, timestamps, booleans, decision paths, output modes, and optional numerical RMS values. They never contain calendar titles, meeting URLs, speech, or raw audio.

```bash
log stream --level debug --predicate 'subsystem == "com.jdegregorio.LuxaforPresence"'
```

## License

LuxaforPresence is available under the [Apache License 2.0](LICENSE.txt).
