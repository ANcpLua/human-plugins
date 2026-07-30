import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var clientID: String
    @State private var token: String
    @State private var channels: String
    @State private var refreshInterval: Int

    init(model: AppModel) {
        self.model = model
        _clientID = State(initialValue: model.configuration.clientID)
        _token = State(initialValue: model.token)
        _channels = State(
            initialValue: model.configuration.channels.joined(separator: "\n")
        )
        _refreshInterval = State(
            initialValue: model.configuration.refreshInterval
        )
    }

    var body: some View {
        Form {
            Section("Twitch API") {
                TextField("Client ID", text: $clientID)
                SecureField("Access token", text: $token)
                Link(
                    "Twitch Developer Console",
                    destination: URL(string: "https://dev.twitch.tv/console")!
                )
            }
            Section("Channels") {
                TextEditor(text: $channels)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                Text("One Twitch channel name per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Refresh") {
                Stepper(
                    "\(refreshInterval) seconds",
                    value: $refreshInterval,
                    in: 30...300,
                    step: 10
                )
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    if model.save(
                        clientID: clientID,
                        token: token,
                        channelsText: channels,
                        refreshInterval: refreshInterval
                    ) {
                        dismiss()
                        Task {
                            await model.refresh()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 460)
    }
}
