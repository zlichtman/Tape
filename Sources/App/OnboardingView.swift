import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: TapeController
    let finish: () -> Void
    @State private var selected = 1
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image("TapeIcon").resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your windows, side by side").font(.title2.bold())
                        Text("Tape brings the window you choose into view.").foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Button { selected = index } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: ["safari", "doc.text", "message"][index]).font(.title2)
                                    Text(["Browser", "Notes", "Chat"][index]).font(.caption)
                                }.frame(maxWidth: .infinity, minHeight: 82)
                            }.buttonStyle(.bordered).tint(selected == index ? .accentColor : .secondary)
                        }
                    }
                    Text("Try selecting a window above. Real windows keep their own widths; Tape scrolls to the one you select.").font(.callout).foregroundStyle(.secondary)
                }
                instruction("1", "Start Tape", "Allow Accessibility access, then start. Tape arranges normal windows on each enabled display.")
                instruction("2", "Choose your apps", "Use Managed Windows → Choose Apps in the Tape menu. Uncheck apps you want to leave alone, or manage only your selected apps.")
                instruction("3", "Choose a window", "Click any app in the Dock, click its window, or use Go to Window in the Tape menu. Keyboard: Control–Option–← / →. Hold Control–Option and scroll horizontally with two fingers to browse without switching apps.")
                instruction("4", "Make room", "Use Width in the menu. Float a window to position it freely. Control–Option–D moves the focused window to the next enabled display. Pause restores the windows Tape arranged.")
                Text("Turn off Stage Manager and macOS window tiling, and pause other window managers, so they don’t fight over window positions.").font(.callout).foregroundStyle(.secondary)
                if !controller.hasAccessibility {
                    HStack {
                        Button("Allow Accessibility…") { controller.requestAccessibility() }
                        Button("Check Access") { controller.checkPermission() }
                    }
                }
                HStack {
                    Label(controller.hasAccessibility ? "Ready to start" : "Accessibility access is required", systemImage: controller.hasAccessibility ? "checkmark.circle" : "lock").foregroundStyle(.secondary)
                    Spacer()
                    Button(controller.isPaused ? "Start Tape" : "Done") {
                        controller.checkPermission()
                        guard controller.hasAccessibility else { return }
                        controller.resume(); finish()
                    }.disabled(!controller.hasAccessibility || controller.isPreview).keyboardShortcut(.defaultAction)
                }
            }.padding(26)
        }.background(SystemStyle.background).buttonStyle(.bordered)
    }
    private func instruction(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline).frame(width: 26, height: 26).background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
