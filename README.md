# Fingertip

A cartoon hand on a stick that points at things on your Mac screen. Personal
tool, built for the satisfaction of using my own software.

Inspired by [TinyHand](https://github.com/nilbuild/tinyhand) by Kamran Ahmed.
Written from scratch.

macOS 13+, Apple Silicon and Intel. Swift, AppKit, Core Animation. No
dependencies.

## Build & run

```sh
chmod +x build.sh
./build.sh
open dist/Fingertip.app
```

On first toggle it asks for **Accessibility** access. That's what lets it
swallow your clicks so a click taps the hand instead of whatever is under it.

For day-to-day hacking, `swift run` from the repo root also works (no bundle,
so no Dock-hiding plist — but `setActivationPolicy(.accessory)` in `main.swift`
hides the Dock icon anyway).

See the note in `build.sh` about code signing: with ad-hoc signing you re-grant
Accessibility after every rebuild. A self-signed "Code Signing" cert fixes that.

## Use

| Action | Effect |
|---|---|
| Click menu bar icon, or **⌃⌥H** | Pointer on / off |
| Right-click menu bar icon | Menu |
| Click | Tap (nothing underneath is clicked) |
| Hold and drag | Draw (press harder on a Force Touch trackpad for a thicker line); strokes fade a few seconds after you let go |
| **⌃⌥L** | Cycle pointer: hand → laser dot → lock-on brackets |
| **⌃⌥S** | Spotlight on / off (dims all but a circle around the pointer) |
| **⌃⌥A** | Snap to elements on / off (hand magnetises to buttons, menu items, links; label shows what it is) |
| **⌃⌥X** | Clear drawing |
| **⌃⌥R** | Start / stop recording the pointer (menu bar icon turns into a record dot) |
| **⌃⌥P** | Replay the last recording |
| **⌃⌥V** | Voice control on / off (menu bar icon becomes a mic) |

Voice commands start with the wake word **"Fingertip"**, so ordinary talking
during a demo never triggers anything. Say the command, then pause briefly:
**"Fingertip, point at Save"** (finds a button, menu item or link with that
title in the frontmost app and moves the pointer onto it), **"Fingertip, tap"**,
**"… spotlight on"** / **"… spotlight off"**, **"… laser"**, **"… hand"**,
**"… brackets"**,
**"… clear"**, **"… record"** / **"… stop recording"**, **"… replay"**,
**"… pointer off"**, **"… stop listening"**. First use asks for Microphone and
Speech Recognition access.
| **Esc** | Clear and turn pointer off |

Clicks on the menu bar icon still go through while the pointer is on.

## Code map

```
Sources/Fingertip/
  main.swift              NSApplication bootstrap, accessory policy
  AppDelegate.swift       menu bar item, hotkey wiring, activation flow
  OverlayController.swift one click-through NSWindow per screen; frame loop
  PointerLayer.swift      the hand + stick (CAShapeLayers) and the laser dot
  InkLayer.swift          drag-to-draw strokes
  SpotlightLayer.swift    dim mask with a hole that follows the cursor
  AXProbe.swift           Accessibility hit test: clickable element under a point
  SnapLayer.swift         outline + label pill for the snapped element
  ReticleLayer.swift      lock-on brackets that clamp onto the snapped element
  Recording.swift         recorded pointer session: JSON model, interpolation, Recorder
  VoiceControl.swift      on-device speech (Apple Speech framework) → commands
  InputTap.swift          CGEvent tap that swallows left-button events
  HotKeys.swift           Carbon RegisterEventHotKey wrapper
  CursorHider.swift       hides the system cursor while active
  TapSound.swift          click sound
  Prefs.swift             hardcoded preferences (promote to UserDefaults later)
```

How it works: the overlay windows sit above everything
(`level = screenSaver + 1`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`) and
ignore mouse events. A 120 Hz timer reads `NSEvent.mouseLocation` and moves the
hand. A session-level `CGEvent` tap on its own thread intercepts
left-down/drag/up plus Force Touch pressure events (NSEvent type 34, which
`CGEventMask` happily accepts): the tap animates the hand and feeds the ink,
and returns `nil` so the event never reaches the app underneath. Everything else — right
clicks, keyboard, scrolling — passes through untouched.

Recording samples the pointer at ~30 Hz plus every press and release into
`~/Library/Application Support/Fingertip/last.json`. Replay feeds those
positions into the same frame loop the live cursor uses, so the hand eases
and snaps exactly as it does live. Before playback, each recorded tap that
was snapped to an element is re-probed; if the same element is still under
that point, the tap (and the drag through its release) shifts to the
element's current centre.

Voice: `SFSpeechRecognizer` with `requiresOnDeviceRecognition` when the
dictation model is present, continuous partial results. The parser only looks
at the words after the last "Fingertip", requires them to be exactly one
command, and waits until the transcript has been stable for 0.7 s, so
"spotlight off" is never cut short at "spotlight". Every command restarts the
recognition task so the buffer starts clean; tasks that fail fast back off and
voice turns itself off after five in a row. "point at X" walks the frontmost app's AX
tree breadth-first (bounded) for a clickable element titled X and warps the
cursor to it; the usual snap then takes over.

Snapping: every 6th frame (~20 Hz) a background queue asks the Accessibility
API what is under the cursor. If it is a clickable role, the hand's goal
becomes the element's centre and it eases there; a tap lands where the hand
is, not where the cursor is.

## Roadmap

- [x] **Phase 0** — core: overlay, hand + laser, tap, ink, hotkeys
- [x] **Phase 1** — Spotlight mode: dim everything except a circle around the hand
- [x] **Phase 2** — Force Touch ink: `NSEvent.pressure` → stroke width
- [x] **Phase 3** — Snap-to-element + AX inspector: `AXUIElementCopyElementAtPosition`,
      hand snaps to buttons/menu items, tooltip shows role/title
- [x] **Phase 4** — Record & replay pointer paths (JSON, eased playback,
      re-resolves AX targets so replays survive window moves)
- [x] **Phase 5** — Voice control: on-device speech (Apple's Speech framework;
      no Whisper needed), "point at Save", "tap", "spotlight on", "replay"

## License

MIT
