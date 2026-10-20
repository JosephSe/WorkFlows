# WorkFlows

A menu bar app for macOS 14+ that runs a list of actions ("Start Work", "Start Timepass", …) when you click one.

## Install

```bash
brew install blueutil switchaudio-osx     # Bluetooth + audio output steps
cd WorkFlows
./build_app.sh --install                  # builds, copies to /Applications, launches
```

Needs Xcode (or its command line tools) for `swift build`. You can also run `open Package.swift` to edit in Xcode, but run the app via `build_app.sh`, because the menu-bar-only behaviour and the Bluetooth permission text live in the Info.plist that the script generates.

Click the ⚡ menu bar icon → **Launch at Login** to start it at boot.

## Use

- Click a workflow in the menu bar to run it. Steps run top to bottom; a failed step is logged and the rest still run.
- **Edit Workflows…** opens the editor: add/rename/duplicate/delete workflows, add/reorder/disable steps, and watch the run log.
- Workflows are stored in `~/Library/Application Support/WorkFlows/workflows.json`.

## Step types

| Step | What it does |
|---|---|
| Open App | `open -a "<App>"` |
| Open URL | `open -a "<Browser>" <url>`, or the default browser if none is chosen |
| Connect Bluetooth Device | `blueutil --connect <address>`, turns Bluetooth on first, waits up to 15s for connected |
| Set Audio Output | `SwitchAudioSource -s <name>`, retried for ~18s so it works right after the speaker connects |
| Set Volume | `osascript -e "set volume output volume N"` |
| Run Shortcut | `shortcuts run "<name>"` |
| Run Shell Command | `zsh -lc "<command>"`, 120s timeout |
| Wait | sleep N seconds |

The default workflows ship with the Bluetooth, audio-output and Focus steps **disabled** because they need your device names. Pick them from the dropdowns, then tick the checkbox.

## Focus / Do Not Disturb

macOS has no public API to toggle Focus. In the Shortcuts app, make a Shortcut containing **Set Focus** (e.g. Work → On), then add a *Run Shortcut* step pointing at it.

## First run

- macOS will ask for **Bluetooth** access the first time a Bluetooth step runs. Allow it (System Settings → Privacy & Security → Bluetooth if you missed it).
- If **Launch at Login** errors, make sure the app is in `/Applications` (use `--install`) and check System Settings → General → Login Items.
