# LuxaforPresence for macOS

LuxaforPresence is a macOS menu-bar app that turns a Luxafor Flag or Flag 2 into a family office presence light. It watches Zoom, external microphone ownership, and local voice energy, then sends color changes to the official Luxafor desktop app through its local webhook.

## Required versus optional setup

The recommended setup uses only local transport. It does **not** require a Luxafor user ID or a personal configuration file when the Luxafor desktop app uses the default port and token.

| Item | Required? | When it is needed |
| --- | --- | --- |
| Luxafor Flag or Flag 2 | Required | This is the physical light controlled by the app. |
| Official Luxafor macOS app 2.5.32+ | Required | It owns the USB device and provides the local webhook used by LuxaforPresence. |
| Incoming Local Webhooks enabled | Required | Required for the recommended local transport. |
| Matching webhook port and security token | Required | The defaults are port `5383` and token `luxafor`. No config file is needed when both apps use those values. |
| LuxaforPresence in `/Applications` or `~/Applications` | Required | Needed for normal launching, permissions, and launch-at-login support. `/Applications` is recommended. |
| Microphone permission | Required for voice detection | Without it, Zoom detection and manual controls still work, but voice energy cannot select the red states. |
| `~/.config/LuxaforPresence/config.plist` | Optional | Create it only to change a default port, token, timing, threshold, or transport mode. |
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
5. Open the LuxaforPresence DMG, drag **LuxaforPresence.app** onto **Applications**, eject the DMG, and launch the copy in `/Applications`.
6. Approve Microphone access when macOS asks.
7. Open the LuxaforPresence menu-bar icon and confirm it reports **External Microphone: Not In Use** and **Voice Sampling: Idle** while no other app is using the microphone.
8. Select a manual color override to confirm the Flag responds, then return the menu to **Automatic**.

If the manual override does not change the Flag, work through [Troubleshooting](#troubleshooting) before testing Zoom or voice activity.

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

If the Luxafor app uses a different port or token, update `localWebhookBaseUrl` or `localWebhookToken` in the LuxaforPresence configuration as described below.

## 2. Install LuxaforPresence

1. Double-click `LuxaforPresence-1.7.0.dmg`.
2. Drag **LuxaforPresence.app** onto the **Applications** shortcut in the DMG.
3. Eject the DMG.
4. Open `/Applications` in Finder and launch **LuxaforPresence** from there.

LuxaforPresence is a menu-bar-only app. It does not open a normal window or appear in the Dock. Look for its status icon on the right side of the macOS menu bar.

The drag-to-Applications window appears only when you open the `.dmg` file, normally from **Downloads**. Clicking `LuxaforPresence.app` in Applications starts the already-installed menu-bar app; it does not show the installer again.

### Local development build warning

A Developer ID-signed and notarized release should open normally. A locally built or ad-hoc-signed DMG is not notarized and macOS may block its first launch. For a build you created or received from a trusted source, Control-click the app in Finder and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway** after the blocked launch. Do not bypass Gatekeeper for an artifact you do not trust.

### Approve permissions and launch at login

On first launch:

1. Approve **Microphone** access. Audio is analyzed only while another application owns a microphone.
2. Open the LuxaforPresence menu and check **Launch at Login**.
3. If the menu says **Approval Required**, open **System Settings → General → Login Items** and approve LuxaforPresence.

If the menu says **Unavailable** while the running app is already in Applications, the app is installed correctly but macOS cannot register that build automatically. This can occur with a locally built or ad-hoc-signed copy. Open **System Settings → General → Login Items**, click **+** under **Open at Login**, and add `/Applications/LuxaforPresence.app` manually. A Developer ID-signed and notarized release can register itself normally.

If Microphone access was denied, enable LuxaforPresence later in **System Settings → Privacy & Security → Microphone**, then quit and reopen the app.

## 3. Configure LuxaforPresence

No user configuration file is required when the Luxafor desktop app uses port `5383` and token `luxafor`. LuxaforPresence uses its bundled local-transport defaults in that case.

To create or edit a personal configuration:

1. Open the LuxaforPresence menu-bar menu.
2. Choose **Open Configuration File…**.
3. Edit the file revealed in Finder:

   ```text
   ~/.config/LuxaforPresence/config.plist
   ```

4. Save the file, quit LuxaforPresence, and launch it again. Configuration is loaded only at startup.

The created file is readable only by the current user. The complete default configuration is:

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
    <real>0.02</real>
    <key>vadMinimumActiveMilliseconds</key>
    <integer>250</integer>
    <key>recentVoiceBlinkSeconds</key>
    <real>300</real>
    <key>voiceCooldownSeconds</key>
    <real>300</real>
    <key>blinkIntervalMilliseconds</key>
    <integer>500</integer>
    <key>localOutputReassertSeconds</key>
    <integer>30</integer>
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
| `pollInterval` | `2` seconds | How often Zoom and external microphone ownership are checked. Minimum `0.25`. |
| `detectZoom` | `true` | Enables process-based Zoom detection. |
| `vadEnabled` | `true` | Enables local voice-energy analysis during external microphone use. |
| `vadThreshold` | `0.02` | RMS energy threshold. Valid range is greater than `0` through `1`. |
| `vadMinimumActiveMilliseconds` | `250` | Consecutive above-threshold energy required to qualify voice activity. Minimum `250`. |
| `recentVoiceBlinkSeconds` | `300` | Duration of the flashing-red recent-voice state. |
| `voiceCooldownSeconds` | `300` | Duration of the solid-red cooldown state. |
| `blinkIntervalMilliseconds` | `500` | Duration of each red/off phase. `500` produces one complete flash per second. Minimum `100`. |
| `localOutputReassertSeconds` | `30` | Periodic physical-output reassertion for local transport. Minimum `5`. |

Invalid numeric values are rejected at startup and replaced with safe defaults. Local plain-HTTP URLs are accepted only for loopback hosts such as `127.0.0.1` and `localhost`.

### Optional remote transport

Local transport is recommended because it stays on the Mac. If local webhooks are unavailable, set `transportMode` to `remote` and replace `YOUR_USER_ID_HERE` with the Luxafor ID from the desktop app's Webhook tab. Remote transport sends only color commands through Luxafor's Webhook API; voice audio is never transmitted.

## 4. Verify the installation

### Check the idle state

With Zoom closed and no other application using a microphone, open the menu and expect:

```text
Status: Available / Off
Output: Off
Luxafor Webhook: Listening
Zoom: Inactive
External Microphone: Not In Use
Voice Sampling: Idle
Voice Energy: Quiet
```

The macOS microphone privacy indicator should not remain active because LuxaforPresence does not keep an idle audio stream open.

If the menu instead says **Luxafor Webhook: Not Listening — Check Luxafor Settings**, open the official Luxafor app and enable **Incoming Local Webhooks** on the configured port before testing any color.

### Check the Luxafor connection first

Use the menu's manual overrides before testing Zoom:

1. Select **Zoom Quiet / Yellow**. The Flag should become solid yellow.
2. Select **Voice Recent / Flashing Red**. The Flag should flash red.
3. Select **Available / Off**. The Flag should turn off.
4. Select **Automatic** to restore signal-based behavior.

If these controls do not affect the Flag, the problem is the Luxafor desktop app, device connection, webhook port, or token—not Zoom or voice detection.

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

### Check microphone-gated sampling

1. Leave Zoom closed and confirm **Voice Sampling: Idle**.
2. Start an app that actively opens the microphone, such as a Zoom meeting with microphone input enabled.
3. Within one polling interval, expect **External Microphone: In Use** and **Voice Sampling: Active**. The macOS microphone privacy indicator is expected while sampling is active.
4. Speak normally for at least 250 milliseconds. Expect **Voice Energy: Detected** and then flashing red.
5. Stop the meeting or close the microphone-using app. Expect **Voice Sampling: Idle** and the light to turn off once both Zoom and external microphone contexts have ended. macOS may briefly retain its privacy indicator after capture stops.

LuxaforPresence measures input energy; it cannot prove that another application's mute control is enabled. Quiet may also mean a quiet room, a different input device, or application-level audio processing.

## Presence behavior

| Light | Meaning |
| --- | --- |
| Off | No active Zoom meeting or qualifying voice activity in an active microphone context |
| Solid yellow | Zoom is active, but no qualifying voice signal occurred in the last ten minutes |
| Flashing red | Qualifying microphone energy occurred in the last five minutes |
| Solid red | The last qualifying signal was five to ten minutes ago |

The red timeline continues while either Zoom or external microphone use keeps the communication context active. When both end, the light turns off immediately. A new qualifying signal restarts the five-minute flashing period.

Manual choices take precedence over automatic detection and stop voice sampling:

- Automatic
- Available / Off
- Zoom Quiet / Yellow
- Voice Recent / Flashing Red
- Voice Cooldown / Solid Red
- Reset Voice Timer

## Privacy and permissions

The packaged app requests only **Microphone** permission. Permission alone does not keep an audio stream open: `AVAudioEngine` starts only while macOS reports that another application is using a microphone, and it stops when that external use ends, a manual override is selected, the Mac sleeps, or the app quits.

While active, LuxaforPresence calculates RMS energy from short in-memory buffers. It never records, stores, transmits, or transcribes audio, and it never logs individual audio samples. Zoom detection is process-based (`CptHost`) and does not require Accessibility, Calendar, Camera, browser automation, or Apple Events permissions.

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

Open **System Settings → Privacy & Security → Microphone**, enable LuxaforPresence, then quit and relaunch the installed app. If LuxaforPresence is not listed, launch the installed copy and trigger the permission prompt again.

### The microphone privacy indicator stays on

- Open the menu and check **External Microphone** and **Voice Sampling**.
- If **External Microphone: In Use**, another process still owns an input device. Close Zoom, recording, dictation, meeting, and browser-call applications.
- If **Voice Sampling: Idle**, LuxaforPresence has stopped its audio engine; macOS may briefly retain the indicator.
- Set `vadEnabled` to `false` and restart to disable LuxaforPresence audio analysis entirely.

### Zoom is active but the light stays off

- Confirm `detectZoom` is `true`.
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

Create a release app and local DMG:

```bash
./scripts/package-dmg.sh -c release -n LuxaforPresence-1.7.0
```

Outputs are written under `dist/`. The packaging script intentionally creates an unsigned development artifact. For trusted distribution, follow [DIST.md](DIST.md) to Developer ID-sign, notarize, staple, and verify the app and DMG.

## License

LuxaforPresence is available under the [Apache License 2.0](LICENSE.txt).
