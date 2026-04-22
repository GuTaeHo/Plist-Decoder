import SwiftUI

@main
struct PlistDecoderApp: App {
    var body: some Scene {
#if os(macOS)
        Window("Plist Decoder", id: "main") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
#else
        WindowGroup {
            ContentView()
        }
#endif
    }
}
