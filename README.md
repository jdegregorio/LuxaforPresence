# LuxaforPresence for macOS

LuxaforPresence is a macOS menu-bar app that turns a Luxafor Flag or Flag 2 into a family office presence light. It watches Zoom, active microphone input in any application, and local input energy, then sends color changes to the official Luxafor desktop app through its local webhook.

## Required versus optional setup

The recommended setup uses only local transport. It does **not** require a Luxafor user ID or a personal configuration file when the Luxafor desktop app uses the default port and token.

| Item | Required? | When it is needed |
| --- | --- | --- |
| Luxafor Flag or Flag 2 | Required | This is the physical light controlled by the app. |
| Official Luxafor macOS app 2.5.32+ | Required | It owns the USB device and provides the local webhook used by LuxaforPresence. |
| Incoming Local Webhooks enabled | Required | Required for the recommended local transport. |
| Matching webhook port and security token | Required | The defaults are port `5383` and token `luxafor`. No config file is needed when both apps use those values. |
| LuxaforPresence in `/Applications` or `~/Applications` | Required | Needed for normal launching, permissions, and launch-at-login support. `/Applications` is recommended. |
| Microphone permission | Required for signal detection | Without it, Zoom detection and manual controls still work, but input energy cannot select the Recent Signal and Cooldown states. |
| Settings | Optional | Use the menu-bar app's **Settings…** window to change colors, timing, detection, connection, or advanced output behavior. |
| `remoteWebhookUserId` | Optional | Used only when `transportMode` is `remote`. Leave `YOUR_USER_ID_HERE` unchanged for local transport. |
| Zoom | Optional | Needed only for automatic Zoom detection. Microphone-based presence and manual controls work without Zoom. |
| Launch at Login | Optional | Enable it if you want LuxaforPresence to start automatically. |

### What is `remoteWebhookUserId`?

It is the ID generated for Luxafor's cloud Webhook API. Luxafor documents it as the `userId` shown in the official desktop app's **Webhook** tab. It is not your macOS account name, Apple ID, email address, or Luxafor device serial number.

Most users should keep:

```xml
<key>transportMode</key>
<string>local</string>
```

With local transport, `remoteWebhookUserId` is ignored and may remain `YOUR_USER_ID_HERE`.

## Quick start

LuxaforPresence depends on the official Luxafor desktop app. Complete these steps in order:

1. Install and launch the [Luxafor desktop app](https://luxafor.com/download/).
2. Connect the Flag by USB and confirm the Luxafor app reports **Device connected**.
3. In the Luxafor app, open **Settings → Incoming Webhook** and enable **Incoming Local Webhooks**.
4. Set the webhook port to `5383` and the security token to `luxafor`, or record your existing values so you can put the same values in LuxaforPresence.
5. [Download the latest LuxaforPresence DMG](https://github.com/jdegregorio/LuxaforPresence/releases/latest/download/LuxaforPresence.dmg), drag **LuxaforPresence.app** onto **Applications**, eject the DMG, and launch the copy in `/Applications`.
6. Approve Microphone access when macOS asks.
7. Open the LuxaforPresence menu-bar icon and confirm it reports **Other App Input: Not In Use** and **Signal Sampling: Idle** while no other app is using a microphone.
8. Select a manual color override to confirm the Flag responds, then return the menu to **Automatic**.

If the manual override does not change the Flag, work through [Troubleshooting](#troubleshooting) before testing Zoom or input-signal activity.

## Requirements

- macOS 13 or later.
- A Luxafor Flag or Flag 2 connected to the Mac.
- The official Luxafor macOS desktop app version 2.5.32 or later. Luxafor documents that version as the first macOS release with incoming local webhooks.
- LuxaforPresence installed in `/Applications` or `~/Applications` for launch-at-login support.
- Microphone permission for local audio-energy analysis.
- Zoom for automatic Zoom detection. Zoom is optional if only microphone-based presence is needed.

The official [Luxafor Flag setup guide](https://luxafor.helpscoutdocs.com/article/6-luxafor-flag-set-up-and-use) covers the device, USB connection, and desktop software. Luxafor's [local webhook instructions](https://luxafor.helpscoutdocs.com/article/58-luxafor-stream-deck-plugin) document the incoming-webhook switch, port, and security token used by this app.

## 1. Set up the Luxafor desktop app

1. Download and install the official [Luxafor software for macOS](https://luxafor.com/download/).
2. Connect the Luxafor Flag to the Mac with its USB data cable.
3. Launch the Luxafor app.
4. Confirm the app reports **Device connected** and can change the Flag's color itself.
5. Leave the Luxafor app running. LuxaforPresence sends commands to this app; it does not control the USB device directly.

### Enable incoming local webhooks

In the Luxafor desktop app:

1. Open **Settings**.
2. Find the **Incoming Webhook** section.
3. Enable **Incoming Local Webhooks**.
4. Note the **Webhook Port**. The Luxafor default is `5383`.
5. Note the **Security Token**. LuxaforPresence's bundled default is `luxafor`.

The Luxafor and LuxaforPresence values must match exactly. With the bundled defaults, LuxaforPresence posts colors to:

```text
http://127.0.0.1:5383/color
```

If the Luxafor app uses a different port or token, update the Local webhook fields under **LuxaforPresence → Settings… → Connection**.

## 2. Install LuxaforPresence

1. Double-click `LuxaforPresence.dmg`.
2. Drag **LuxaforPresence.app** onto the **Applications** shortcut in the DMG.
3. Eject the DMG.
4. Open `/Applications` in Finder and launch **LuxaforPresence** from there.

LuxaforPresence is a menu-bar-only app. It does not open a normal window or appear in the Dock. Look for its status icon on the right side of the macOS menu bar.

The drag-to-Applications window appears only when you open the `.dmg` file, normally from **Downloads**. Clicking `LuxaforPresence.app` in Applications starts the already-installed menu-bar app; it does not show the installer again.

### Ad-hoc release warning

Current GitHub Releases and locally packaged DMGs are ad-hoc signed and are not notarized by Apple. macOS may block the first launch. For a build from this repository that you trust, Control-click the app in Finder and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway** after the blocked launch. Do not bypass Gatekeeper for an artifact you do not trust. See [DIST.md](DIST.md) for the complete limitations and the requirements for a future Developer ID-signed release.

Replacing an ad-hoc-signed development build also changes its code identity, so macOS may ask for Microphone approval again even when an older LuxaforPresence entry still appears enabled. The menu reports **Microphone Permission: Waiting for Approval** until the current build is approved. This repeat prompt does not occur across properly Developer ID-signed releases from the same developer.

### Approve permissions and launch at login

On first launch:

1. Approve **Microphone** access. Audio is analyzed only while another process has active microphone input.
2. Open the LuxaforPresence menu and check **Launch at Login**.
3. If the menu says **Approval Required**, open **System Settings → General → Login Items** and approve LuxaforPresence.

If the menu says **Unavailable** while the running app is already in Applications, the app is installed correctly but macOS cannot register that build automatically. This can occur with a locally built or ad-hoc-signed copy. Open **System Settings → General → Login Items**, click **+** under **Open at Login**, and add `/Applications/LuxaforPresence.app` manually. A Developer ID-signed and notarized release can register itself normally.

If Microphone access was denied, enable LuxaforPresence later in **System Settings → Privacy & Security → Microphone**, then quit and reopen the app.

## 3. Configure LuxaforPresence

No user configuration file is required when the Luxafor desktop app uses port `5383` and token `luxafor`. LuxaforPresence uses its bundled local-transport defaults in that case.

To change settings:

1. Open the LuxaforPresence menu-bar menu.
2. Choose **Settings…**.
3. Use **Behavior** to configure the Recent Signal → Cooldown timeline, **Colors** to choose the output for every state, **Connection** for Luxafor webhook settings, or **Advanced** for polling and signal qualification.
4. Choose **Save**. The app writes a private user configuration, rebuilds its signal engine, and applies the settings immediately.

Choose **Restore Defaults…**, confirm, and then choose **Save** to reset every setting to the bundled defaults. Saving writes a complete normalized file, so obsolete or unknown keys from older configurations are removed. Existing configurations continue to load from `~/.config/LuxaforPresence/config.plist` or the older Application Support location, but normal setup no longer requires manual plist editing or an app restart.

The saved file is readable only by the current user. The complete default configuration is:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>transportMode</key>
    <string>local</string>
    <key>localWebhookBaseUrl</key>
    <string>http://127.0.0.1:5383</string>
    <key>localWebhookToken</key>
    <string>luxafor</string>
    <!-- Ignored while transportMode is local. -->
    <key>remoteWebhookUserId</key>
    <string>YOUR_USER_ID_HERE</string>
    <key>pollInterval</key>
    <real>2</real>
    <key>detectZoom</key>
    <true/>
    <key>vadEnabled</key>
    <true/>
    <key>vadThreshold</key>
    <real>0.001</real>
    <key>vadMinimumActiveMilliseconds</key>
    <integer>250</integer>
    <key>recentVoiceSeconds</key>
    <real>300</real>
    <key>voiceCooldownSeconds</key>
    <real>300</real>
    <key>availableColor</key>
    <string>#000000</string>
    <key>zoomQuietColor</key>
    <string>#FFFF00</string>
    <key>recentVoiceColor</key>
    <string>#FF0000</string>
    <key>voiceCooldownColor</key>
    <string>#FF8C00</string>
    <key>localOutputHeartbeatEnabled</key>
    <false/>
    <key>localOutputReassertSeconds</key>
    <integer>30</integer>
    <key>outputBrightness</key>
    <real>0.7</real>
</dict>
</plist>
```

### Configuration reference

| Key | Default | Purpose |
| --- | --- | --- |
| `transportMode` | `local` | Uses the Luxafor desktop app's loopback webhook. Set to `remote` only for the cloud fallback. |
| `localWebhookBaseUrl` | `http://127.0.0.1:5383` | Luxafor local webhook address and port. The app appends `/color`. |
| `localWebhookToken` | `luxafor` | Must match the Luxafor app's Incoming Webhook security token. |
| `remoteWebhookUserId` | placeholder | Required only for `remote` transport. Find the ID in the Luxafor app's Webhook tab. Never commit a real ID. |
| `pollInterval` | `2` seconds | How often Zoom and other processes' active microphone input are checked. Minimum `0.25`. |
| `detectZoom` | `true` | Enables Zoom detection from Zoom-owned microphone input, in-call power assertions, and legacy helper processes. |
| `vadEnabled` | `true` | Enables local input-energy analysis while any other process has active microphone input. |
| `vadThreshold` | `0.001` | RMS threshold separating digital silence from a real input signal. Valid range is greater than `0` through `1`. Raise it if room noise qualifies too easily. |
| `vadMinimumActiveMilliseconds` | `250` | Consecutive above-threshold energy required for microphone-only tools. Minimum `250`; Zoom uses at least three seconds to reject call-start noise. |
| `recentVoiceSeconds` | `300` | Seconds spent in Recent Signal after the last qualifying input. A new signal restarts this duration. |
| `voiceCooldownSeconds` | `300` | Seconds spent in Cooldown after Recent Signal ends. Afterward the state becomes Zoom Quiet or Available. |
| `availableColor` | `#000000` | Output used when no communication context is active. Black turns the device off. |
| `zoomQuietColor` | `#FFFF00` | Output used for an active Zoom meeting without a recent or cooling-down signal. |
| `recentVoiceColor` | `#FF0000` | Output used during the Recent Signal duration. |
| `voiceCooldownColor` | `#FF8C00` | Output used during the Cooldown duration. |
| `localOutputHeartbeatEnabled` | `false` | Advanced recovery option that periodically reasserts output. Keep disabled for the Luxafor desktop listener's best responsiveness. |
| `localOutputReassertSeconds` | `30` | Heartbeat interval when `localOutputHeartbeatEnabled` is enabled. Minimum `5`. |
| `outputBrightness` | `0.7` | Scales every configured RGB color per request. Use a value from `0` through `1`; `0.7` is 70% of full output. |

Invalid numeric values are rejected at startup and replaced with safe defaults. Local plain-HTTP URLs are accepted only for loopback hosts such as `127.0.0.1` and `localhost`.

### Optional remote transport

Local transport is recommended because it stays on the Mac. If local webhooks are unavailable, select **Remote webhook** under **Settings… → Connection** and enter the Luxafor ID from the desktop app's Webhook tab. Remote transport sends only color commands through Luxafor's Webhook API; voice audio is never transmitted.

## 4. Verify the installation

### Check the idle state

With Zoom closed and no other application using a microphone, open the menu and expect:

```text
Status: Available
Output: Off
Luxafor Webhook: Listening
Zoom: Inactive
Microphone Permission: Authorized
Other App Input: Not In Use
Signal Sampling: Idle
Input Signal: Quiet
```

The macOS microphone privacy indicator should not remain active because LuxaforPresence does not keep an idle audio stream open.

If the menu instead says **Luxafor Webhook: Not Listening — Check Luxafor Settings**, open the official Luxafor app and enable **Incoming Local Webhooks** on the configured port before testing any color.

### Check the Luxafor connection first

Use the menu's manual overrides before testing Zoom:

1. Select **Zoom Quiet / Yellow (#FFFF00)**. The Flag should become solid yellow.
2. Select **Signal Recent / Red (#FF0000)**. The Flag should become solid red.
3. Select **Signal Cooldown / Orange (#FF8C00)**. The Flag should become solid orange.
4. Select **Available / Off**. The Flag should turn off.
5. Select **Automatic** to restore signal-based behavior.

If these controls do not affect the Flag, the problem is the Luxafor desktop app, device connection, webhook port, or token—not Zoom or input-signal detection.

You can test the default local webhook directly from Terminal. This command turns the Flag green when the Luxafor app uses the default port and token:

```bash
curl --fail-with-body \
  --request POST \
  --header 'Authorization: Bearer luxafor' \
  --header 'Content-Type: application/json' \
  --data '{"color":"#00FF00"}' \
  http://127.0.0.1:5383/color
```

Use the actual port and token if you changed them. Treat a custom token like a password and do not paste it into logs, issues, or screenshots.

### Check microphone-gated signal sampling

1. Leave Zoom closed and confirm **Signal Sampling: Idle**.
2. Start any app that actively receives microphone input, such as Zoom, Teams, Slack, FaceTime, a browser call, dictation, or recording software.
3. Within one polling interval, expect **Other App Input: In Use** and **Signal Sampling: Active**. The macOS microphone privacy indicator is expected while sampling is active.
4. For dictation or recording without Zoom, produce a non-silent input signal for at least 250 milliseconds. Expect **Input Signal: Detected** and solid red. In Zoom, continuous input must remain above the threshold for at least three seconds; the light stays yellow before then.
5. Stop the microphone-using app. Expect **Signal Sampling: Idle** while the light remains red for the configured Recent Signal duration, then orange for Cooldown. The timeline continues without keeping LuxaforPresence's microphone open.
6. After Cooldown expires, expect yellow if Zoom is still active or off otherwise. macOS may briefly retain its privacy indicator after capture stops.

LuxaforPresence measures RMS input energy; it does not classify speech or inspect audio content. A very quiet room, hardware mute, application-level processing, or a threshold set too high can all appear silent.

## Presence behavior

| Default output | Meaning |
| --- | --- |
| Off | No active Zoom meeting and no qualifying signal in the Recent/Cooldown timeline |
| Solid yellow | Zoom is active without a recent or cooling-down input signal |
| Solid red | A qualifying non-silent input signal occurred within `recentVoiceSeconds` |
| Solid orange | The recent-signal period ended and `voiceCooldownSeconds` is still running |

The Recent Signal → Cooldown timeline continues after Zoom or another application releases its microphone. Capture stops immediately, but the light remains red and then orange until both configured durations expire. It then becomes Zoom Quiet when Zoom is still active or Available otherwise. A new qualifying signal restarts Recent Signal. Every output color and both durations can be changed under **Settings…**.

Manual choices take precedence over automatic detection and stop signal sampling:

- Automatic
- Available / Off
- Zoom Quiet / Yellow (#FFFF00)
- Signal Recent / Red (#FF0000)
- Signal Cooldown / Orange (#FF8C00)
- Clear Recent Signal & Cooldown

**Clear Recent Signal & Cooldown** forgets the last detected input signal. When Automatic is selected, the app reevaluates immediately; a manual override remains selected. It is useful after a false positive or when the light should leave Recent/Cooldown before their configured durations expire.

The bottom of the menu shows the semantic version read from the running app, for example **Version: 1.9.5**.

## Privacy and permissions

The packaged app requests only **Microphone** permission. Permission alone does not keep an audio stream open: `AVAudioEngine` starts only while Core Audio reports active input in another process, and it stops when that external use ends, a manual override is selected, the Mac sleeps, or the app quits. The app excludes its own audio process and Apple's background CoreSpeech voice trigger, which can remain active when no user-facing dictation client is listening, so neither can keep sampling active by itself.

While active, LuxaforPresence calculates RMS energy from short in-memory buffers. It never records, stores, transmits, or transcribes audio, and it never logs individual audio samples. Zoom detection reads privacy-safe Core Audio process ownership and power assertions, with the legacy `CptHost` helper as a compatibility fallback; it does not require Accessibility, Calendar, Camera, browser automation, or Apple Events permissions.

Use the packaged app for final permission testing. `swift run` is an unpackaged development process, so macOS may attribute microphone permission to the parent terminal instead of LuxaforPresence.

## Updating or reinstalling

1. Open the LuxaforPresence menu and choose **Quit**.
2. Open the new DMG.
3. Drag **LuxaforPresence.app** onto **Applications** and approve replacing the existing copy.
4. Eject the DMG and launch the copy in `/Applications`.

The user configuration in `~/.config/LuxaforPresence/config.plist` is outside the app bundle and is preserved during replacement.

## Troubleshooting

### The Flag never changes

- Confirm the official Luxafor desktop app is running.
- Confirm it reports **Device connected** and can control the Flag itself.
- Enable **Incoming Local Webhooks** in Luxafor Settings.
- Confirm the webhook port and security token match `localWebhookBaseUrl` and `localWebhookToken`.
- Run the direct `curl` test above.
- Return LuxaforPresence to **Automatic** after testing manual overrides.

### LuxaforPresence launches but no window appears

This is expected. LuxaforPresence is a menu-bar app with no Dock icon. Look on the right side of the menu bar; macOS may place less frequently used status items behind Control Center when space is limited.

### Microphone permission is denied

If the menu says **Microphone Permission: Denied — Open Privacy Settings**, open **System Settings → Privacy & Security → Microphone**, enable LuxaforPresence, then quit and relaunch the installed app. If an ad-hoc replacement says **Waiting for Approval** while an older entry appears enabled, toggle that entry off and on, or run `tccutil reset Microphone com.jdegregorio.LuxaforPresence`, relaunch the installed app, and approve the new prompt. If LuxaforPresence is not listed, launch the installed copy to trigger the prompt.

### The microphone privacy indicator stays on

- Open the menu and check **Other App Input** and **Signal Sampling**.
- If **Other App Input: In Use**, another process still has active input I/O. Close Zoom, recording, dictation, meeting, and browser-call applications.
- If **Signal Sampling: Idle**, LuxaforPresence has stopped its audio engine; macOS may briefly retain the indicator.
- Turn off **Settings… → Behavior → Analyze microphone input energy** to disable LuxaforPresence audio analysis entirely.

### Another app uses the microphone but signal sampling stays idle

- Confirm the microphone-using app is actively receiving input, not merely open.
- Return LuxaforPresence to **Automatic**; manual overrides intentionally stop sampling.
- Stream diagnostics and look for `External input activity changed active=true source=coreAudioProcesses`.
- If sampling is active but **Input Signal** remains quiet, lower `vadThreshold`; `0.001` is the bundled digital-silence-oriented default. Zoom also requires three continuous seconds above the threshold, while microphone-only tools use the configured minimum.

### Zoom is active but the light stays off

- Confirm **Settings… → Behavior → Detect Zoom meetings** is enabled.
- Wait at least one polling interval, two seconds by default.
- Confirm the menu changes to **Zoom: Active**.
- Clear any manual override by selecting **Automatic**.

### Launch at login requires approval

Open **System Settings → General → Login Items** and approve LuxaforPresence. Launch-at-login registration is unavailable from a mounted DMG, App Translocation, or `swift run`; install and launch the app from `/Applications` first.

If the installed app reports **Launch at Login (Unavailable…)**, click it to open Login Items and add `/Applications/LuxaforPresence.app` under **Open at Login**. The message no longer means the app is in the wrong folder; it means macOS did not expose automatic registration for that build.

### Collect diagnostics

Stream privacy-safe structured logs in Terminal:

```bash
/usr/bin/log stream --level debug \
  --predicate 'subsystem == "com.jdegregorio.LuxaforPresence"'
```

Logs contain derived state, timestamps, booleans, decision paths, output modes, optional numerical RMS values, and redacted transport errors. They do not contain calendar titles, meeting URLs, speech, tokens, or raw audio.

## Build and test from source

Development requires macOS 13+, Swift 5.7+, and Xcode 14.3+ or a compatible newer release. Full Xcode is recommended because some Command Line Tools-only installations do not include XCTest.

```bash
git clone https://github.com/jdegregorio/LuxaforPresence.git
cd LuxaforPresence
swift build
swift test
swift run
```

If `swift test` reports `no such module 'XCTest'`, install Xcode and select its developer directory:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
swift test
```

For restricted build environments with unwritable home-directory caches:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.cache swift build --disable-sandbox
```

Create the same ad-hoc-signed app and DMG used by the current personal release workflow:

```bash
./scripts/package-dmg.sh -c release -n LuxaforPresence
```

Outputs are written under `dist/`. The packaging script includes the microphone entitlement but does not provide an identified-developer signature or Apple notarization. Versioned builds merged to `main` publish this DMG and its SHA-256 file on GitHub automatically. See [DIST.md](DIST.md) for the current release behavior, its limitations, and the future trusted-distribution checklist.

## License

LuxaforPresence is available under the [Apache License 2.0](LICENSE.txt).
