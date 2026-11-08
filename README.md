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
| Right-click menu bar icon | Menu, including **Settings…** |
| Click | Tap (nothing underneath is clicked) |
| Hold and drag | Draw (press harder on a Force Touch trackpad for a thicker line); strokes fade a few seconds after you let go |
| **⇧** + drag | Straight arrow from where you pressed to where you let go |
| **⌥** + drag | Highlighter: a wide see-through stroke (yellow by default) |
| **⌃⌥L** | Cycle pointer: hand → laser dot → lock-on brackets |
| **⌃⌥S** | Spotlight on / off (dims all but a circle around the pointer) |
| **⌃⌥A** | Snap to elements on / off (hand magnetises to buttons, menu items, links; label shows what it is) |
| **⌃⌥N** | Step stamps on / off: each tap drops a numbered badge 1, 2, 3… (on a snapped button's top-left corner); they stay until cleared |
| **⌃⌥C** | Click-through on / off: clicks and drags reach the app underneath, each click shows a ripple, no drawing (menu bar icon becomes a tapping hand) |
| **⌃⌥X** | Clear drawing and stamps (numbering restarts at 1) |
| **Esc** | Clear and turn pointer off |

Clicks on the menu bar icon still go through while the pointer is on.

## Settings

Right-click the menu bar icon → **Settings…**. Changes apply instantly and are
remembered:

- **Pointer**: style; hand (the menu bar icon's hand in white, the same hand
  in a skin tone, or the ☝️ emoji); skin tone; which side the finger is on (left like
  the menu bar icon, right like ☝️, or auto: flips so the palm faces the
  nearer side edge); whether to show the stick; hand size; laser and brackets colours; snapping; hiding the system
  cursor; tap sound
- **Clicks go through to apps**: the click-through mode above
- **Drawing**: ink and arrow colour, highlighter colour, line width, fade delay (or never)
- **Spotlight**: size and darkness
- **Step stamps**: badge colour
- **General**: open at login, reset to defaults, and a shortcuts reference

The pointer can stay on while Settings is open; clicks on Fingertip's own
windows go through to them.

## Code map

```
Sources/Fingertip/
  main.swift              NSApplication bootstrap, accessory policy
  AppDelegate.swift       menu bar item, hotkey wiring, activation flow
  OverlayController.swift one click-through NSWindow per screen; frame loop
  PointerLayer.swift      the hand (menu bar symbol or emoji, mirrored as set), stick, laser
  InkLayer.swift          drag-to-draw strokes
  SpotlightLayer.swift    dim mask with a hole that follows the cursor
  AXProbe.swift           Accessibility hit test: clickable element under a point
  SnapLayer.swift         outline + label pill for the snapped element
  ReticleLayer.swift      lock-on brackets that clamp onto the snapped element
  StampLayer.swift        numbered step badges for walkthroughs
  ClickRipple.swift       the ring shown for each click in click-through mode
  InputTap.swift          CGEvent tap that swallows left-button events
  HotKeys.swift           Carbon RegisterEventHotKey wrapper
  CursorHider.swift       hides the system cursor while active
  TapSound.swift          click sound
  Prefs.swift             settings on UserDefaults, hand kinds, skin tones
  SettingsView.swift      SwiftUI Settings window
```

How it works: the overlay windows sit above everything
(`level = screenSaver + 1`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`) and
ignore mouse events. A 120 Hz timer reads `NSEvent.mouseLocation` and moves the
hand. A session-level `CGEvent` tap on its own thread intercepts
left-down/drag/up plus Force Touch pressure events (NSEvent type 34, which
`CGEventMask` happily accepts): the tap animates the hand and feeds the ink,
and returns `nil` so the event never reaches the app underneath. Everything else — right
clicks, keyboard, scrolling — passes through untouched.

Click-through: the same event tap only watches instead of swallowing, so
every click and drag reaches the app while the press callbacks still fire to
squash the hand, drop a ripple, and count step stamps.

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
- [ ] ~~**Phase 4** — Record & replay~~: built, then removed; not useful in practice
- [ ] ~~**Phase 5** — Voice control~~: built, then removed; it didn't earn its
      place in real use

## License

MIT
