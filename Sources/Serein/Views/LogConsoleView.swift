import SwiftUI

/// Real-time diagnostic console drawer displaying coordinator decisions, FFprobe data, and FFmpeg streaming output.
public struct LogConsoleView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @State private var filterLevel: CoordinatorLogItem.LogLevel? = nil
    var onClose: (() -> Void)?

    private var filteredLogs: [CoordinatorLogItem] {
        if let filter = filterLevel {
            return coordinator.logs.filter { $0.level == filter }
        }
        return coordinator.logs
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Label("Diagnostics & Engine Console", systemImage: "terminal.fill")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                // Filter pills
                HStack(spacing: 4) {
                    filterButton(title: "All", level: nil)
                    filterButton(title: "Info", level: .info)
                    filterButton(title: "Transcode", level: .transcode)
                    filterButton(title: "Warn", level: .warning)
                    filterButton(title: "Error", level: .error)
                }

                Divider().frame(height: 14)

                Button("Copy") {
                    copyToClipboard()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))

                Button("Clear") {
                    coordinator.clearLogs()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))

                if let onClose = onClose {
                    Divider().frame(height: 14)
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Console output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredLogs) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.formattedTime)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text(item.level.rawValue)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(badgeBackground(for: item.level))
                                    .foregroundColor(badgeForeground(for: item.level))
                                    .cornerRadius(3)

                                Text(item.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)

                                Spacer()
                            }
                            .id(item.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: coordinator.logs.count) { _, _ in
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    private func filterButton(title: String, level: CoordinatorLogItem.LogLevel?) -> some View {
        Button(action: { filterLevel = level }) {
            Text(title)
                .font(.system(size: 10, weight: filterLevel == level ? .bold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(filterLevel == level ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func badgeBackground(for level: CoordinatorLogItem.LogLevel) -> Color {
        switch level {
        case .info: return Color.blue.opacity(0.15)
        case .success: return Color.green.opacity(0.15)
        case .warning: return Color.orange.opacity(0.15)
        case .error: return Color.red.opacity(0.15)
        case .transcode: return Color.purple.opacity(0.15)
        }
    }

    private func badgeForeground(for level: CoordinatorLogItem.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .transcode: return .purple
        }
    }

    private func copyToClipboard() {
        let text = coordinator.logs.map { "[\($0.formattedTime)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
