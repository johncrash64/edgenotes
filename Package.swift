// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeNotes",
    platforms: [.macOS(.v14)],
    targets: [
        // Model, persistence, rich-text and clipboard logic. No SwiftUI.
        .target(
            name: "EdgeNotesCore",
            path: "Sources/EdgeNotesCore"
        ),
        // Menu-bar-less agent app: edge panel, deck and editor.
        .executableTarget(
            name: "EdgeNotesApp",
            dependencies: ["EdgeNotesCore"],
            path: "Sources/EdgeNotesApp"
        ),
        .testTarget(
            name: "EdgeNotesCoreTests",
            dependencies: ["EdgeNotesCore"],
            path: "Tests/EdgeNotesCoreTests"
        ),
    ]
)
