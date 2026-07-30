import SwiftUI
import TwitchCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            List {
                if !model.online.isEmpty {
                    Section("Live") {
                        ForEach(model.online) { stream in
                            StreamRow(stream: stream, model: model)
                        }
                    }
                }
                Section("Offline") {
                    ForEach(model.offline) { stream in
                        StreamRow(stream: stream, model: model)
                    }
                }
            }
            .overlay {
                if model.streams.isEmpty && model.errorMessage == nil {
                    ContentUnavailableView(
                        "No channels configured",
                        systemImage: "play.tv",
                        description: Text("Add channels and Twitch credentials in Settings.")
                    )
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: model)
        }
        .task {
            await model.refreshLoop()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Twitch Launcher")
                    .font(.title2.weight(.semibold))
                Text("\(model.online.count) live · \(model.offline.count) offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task {
                    await model.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                showsSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding()
    }
}

private struct StreamRow: View {
    let stream: StreamInfo
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.launch(stream)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: stream.isOnline ? "play.circle.fill" : "moon.zzz")
                    .foregroundStyle(stream.isOnline ? .purple : .secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.displayName)
                        .font(.headline)
                    if stream.isOnline {
                        Text(stream.gameName.isEmpty ? stream.title : stream.gameName)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Offline")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if stream.isOnline {
                    Label(stream.formattedViewers, systemImage: "eye")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open the channel with Streamlink")
    }
}
