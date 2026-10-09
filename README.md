# EdgeNotes

A tiny macOS app that keeps your text templates on the edge of the screen, one click away from the clipboard.

Notes live in a thin pill on the right edge. Touch the edge and they fan out; click one and it is copied **with its formatting** (color, font, size, bold, italic, underline), ready to paste into Mail, Notes, Pages, Slack, a browser, anywhere.

Inspired by [Hold My Notes](https://holdmynotes.app/). EdgeNotes is smaller on purpose: it is a template shelf, not a note-taking suite.

## How it works

- **Hover** the right screen edge: the deck opens. Move away and it folds back into the pill.
- **Click a note**: copies it. The clipboard gets RTF (native Mac apps), HTML (web apps) and plain text (everything else), so the destination picks the richest format it understands. Copying never steals focus from the app you are pasting into.
- **Pencil / right-click → Edit**: opens the editor with a title, an accent color, and a formatting bar (font, size, bold, italic, underline, text color). Shortcuts: ⌘B, ⌘I, ⌘U, plus the usual ⌘Z / ⌘X / ⌘C / ⌘V / ⌘A.
- **Drag** rows to reorder, **right-click** to duplicate or delete (deletes can be undone for 10 seconds).
- The menu bar icon offers *Show Notes*, *New Note* and *Quit*.

The editor is always a light "paper" sheet, so a color you pick means the same thing wherever you paste. "Automatic" text color leaves the color unset, so the destination app uses its own default (this is what keeps pasted text readable in dark mode).

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
- No sync, no search, no archive, no global shortcut.
- No app icon yet.

## License

MIT, see [LICENSE](LICENSE).
