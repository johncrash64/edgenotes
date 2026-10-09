# EdgeNotes

A tiny macOS app that keeps your text templates on the edge of the screen, one click away from the clipboard.

Notes live in a thin pill on the right edge. Touch the edge and they fan out; click one and it is copied **with its formatting** (color, font, size, bold, italic, underline), ready to paste into Mail, Notes, Pages, Slack, a browser, anywhere.

Inspired by [Hold My Notes](https://holdmynotes.app/). EdgeNotes is smaller on purpose: it is a template shelf, not a note-taking suite.

## How it works

- **At rest** the app is a slim, dark, translucent capsule on the right edge with one small pastel dash per note. As your cursor approaches the edge, the capsule glides to your cursor's height.
- **Touch the edge**: each dash grows into its own colored tab, top to bottom, showing the note's title. A "+" button appears under them.
- **Rest on a tab**: after a moment that same tab grows into a pastel card with a rich-text preview. Once a card is out, it follows the cursor from tab to tab. Move away and everything shrinks back into the capsule.

Dash, tab and card are one surface per note, not three: position, size, corners and color interpolate, and the contents are revealed inside the same shape.
- **Click a tab or card**: copies it. The clipboard gets RTF (native Mac apps), HTML (web apps) and plain text (everything else), so the destination picks the richest format it understands. Copying never steals focus from the app you are pasting into.
- **Pencil on the card** (or right-click → Edit, or "+"): opens the editor.
- **Right-click** a tab or card to copy, edit, duplicate, move up/down, or delete (deletes can be undone for 10 seconds).
- The menu bar icon offers *Show Notes*, *New Note*, *Launch at Login* (a toggle that registers the app as a login item; it also shows up in System Settings → Login Items) and *Quit*.

The open/close motion is modeled on [Hold My Notes](https://holdmynotes.app/)' demo video.

### The editor

A pastel sheet in its own window, centered on the screen:

- Title, a live *Saving… / Saved* indicator, and a pin that keeps the window open when you click elsewhere.
- Formatting bar: font, size, bold, italic, underline and text color. The buttons light up to match the selection or caret. Shortcuts: ⌘B, ⌘I, ⌘U, plus ⌘Z / ⌘X / ⌘C / ⌘V / ⌘A, and ⌘W to close.
- Footer: note color, a two-step *Delete*, and *Copy*, which copies the note with its formatting.

The writing surface is always a light "paper" sheet, so a color you pick means the same thing wherever you paste. "Automatic" text color leaves the color unset, so the destination app uses its own default (this is what keeps pasted text readable in dark mode).

## Requirements

- macOS 14 or later
- Xcode (or the Swift 6 toolchain) to build

## Build and run

```sh
git clone https://github.com/johncrash64/edgenotes.git
cd edgenotes
./scripts/package.sh
open build/EdgeNotes.app
```

Run the tests with `swift test`.

### Signing

With no configuration the app is signed ad-hoc, which works. macOS treats each ad-hoc build as a different app, though. To keep a stable identity across builds, sign with any code-signing certificate in your login keychain:

```sh
CODESIGN_IDENTITY="Your Certificate Name" ./scripts/package.sh
```

There is no notarization and no hardened runtime: EdgeNotes is meant to be built and run on your own Mac.

## Where your notes live

`~/Library/Application Support/EdgeNotes/notes/`, one JSON file per note. The body is stored as RTF inside the file. Back it up or sync it however you like.

## Project layout

```
Sources/EdgeNotesCore   model, JSON persistence, RTF/clipboard, formatting logic (no SwiftUI)
Sources/EdgeNotesApp    edge panel, deck and editor (SwiftUI + AppKit)
Tests/                  swift-testing suites for Core
scripts/package.sh      builds and signs build/EdgeNotes.app
```

## Known limitations (v0.1)

- Appears on the primary display only.
- Tabs are tightened to fit the screen height; beyond roughly 40 notes the extra ones are not shown.
- No sync, no search, no archive, no global shortcut.
- No app icon yet.

## License

MIT, see [LICENSE](LICENSE).
