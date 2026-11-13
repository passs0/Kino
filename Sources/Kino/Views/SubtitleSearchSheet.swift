import SwiftUI
import AppKit

/// Native Liquid Glass search & download sheet for OpenSubtitles.com.
public struct SubtitleSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var service = OpenSubtitlesService.shared
    @ObservedObject private var coordinator = MediaCoordinator.shared

    @State private var searchQuery: String = ""
    @State private var computedMovieHash: String? = nil
    @State private var isCalculatingHash: Bool = false
    @State private var selectedLanguage: String = "en"

    @State private var results: [SubtitleSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String? = nil
    @State private var quotaErrorWebURL: URL? = nil

    @State private var downloadingFileId: Int? = nil
    @State private var appliedFileId: Int? = nil

    // Account login fold-out
    @State private var showAccountSettings: Bool = false
    @State private var inputUsername: String = ""
    @State private var inputPassword: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var loginError: String? = nil

    private let supportedLanguages: [(code: String, name: String, flag: String)] = [
        ("all", "All Languages", "🌐"),
        ("en", "English", "🇺🇸"),
        ("zh-CN", "Chinese (Simplified)", "🇨🇳"),
        ("zh-TW", "Chinese (Traditional)", "🇹🇼"),
        ("es", "Spanish", "🇪🇸"),
        ("fr", "French", "🇫🇷"),
        ("de", "German", "🇩🇪"),
        ("ja", "Japanese", "🇯🇵"),
        ("ko", "Korean", "🇰🇷"),
        ("it", "Italian", "🇮🇹"),
        ("pt-BR", "Portuguese (Brazil)", "🇧🇷"),
        ("ru", "Russian", "🇷🇺"),
        ("ar", "Arabic", "🇸🇦"),
        ("id", "Indonesian", "🇮🇩"),
        ("vi", "Vietnamese", "🇻🇳"),
        ("th", "Thai", "🇹🇭"),
        ("hi", "Hindi", "🇮🇳"),
        ("tr", "Turkish", "🇹🇷"),
        ("pl", "Polish", "🇵🇱"),
        ("nl", "Dutch", "🇳🇱"),
        ("sv", "Swedish", "🇸🇪")
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            searchBarView
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            if showAccountSettings {
                accountSettingsView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                Divider()
            }

            contentAreaView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 660, height: 560)
        .background(VisualEffectBackdrop().ignoresSafeArea())
        .onAppear {
            setupInitialState()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Search Subtitles Online")
                    .font(.headline)
                Text("Search and download synchronized subtitles via OpenSubtitles.com")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showAccountSettings.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: service.isLoggedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                        .foregroundColor(service.isLoggedIn ? .green : .secondary)
                    Text(service.isLoggedIn ? (service.username ?? "Account") : "Account")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: showAccountSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .help("Manage OpenSubtitles account and API credentials")
        }
    }

    // MARK: - Search Bar & Filters

    private var searchBarView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search movie, series, or video title...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performSearch()
                        }

                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                // Language picker
                Picker("", selection: $selectedLanguage) {
                    ForEach(supportedLanguages, id: \.code) { item in
                        Text("\(item.flag) \(item.name)").tag(item.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 175)
                .onChange(of: selectedLanguage) { newLanguage in
                    service.preferredLanguage = newLanguage
                    performSearch()
                }

                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isSearching || (searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && computedMovieHash == nil))
            }

            // MovieHash status banner (if local media)
            if let hash = computedMovieHash {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))

                    Text("File Hash: \(hash)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("• Exact timing synchronization ready")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()
                }
            } else if isCalculatingHash {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Calculating file hash for exact sync...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Account Settings Panel

    private var accountSettingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if service.isLoggedIn {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Logged in as \(service.username ?? "User")")
                            .font(.system(size: 13, weight: .semibold))
                        if let quota = service.remainingDailyQuota {
                            Text("\(quota) downloads remaining today")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("OpenSubtitles.com Member")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Log Out") {
                        service.logout()
                    }
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        TextField("Username", text: $inputUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)

                        SecureField("Password", text: $inputPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)

                        Button(isLoggingIn ? "Logging in..." : "Log In") {
                            loginUser()
                        }
                        .disabled(isLoggingIn || inputUsername.isEmpty || inputPassword.isEmpty)
                        .controlSize(.regular)

                        Spacer()

                        Link("Create Free Account ↗", destination: URL(string: "https://www.opensubtitles.com/users/sign_up")!)
                            .font(.system(size: 11))
                    }

                    if let err = loginError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else {
                        Text("Free OpenSubtitles accounts receive 20 downloads per 24 hours.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Content Area

    private var contentAreaView: some View {
        ZStack {
            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Searching OpenSubtitles.com...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if let err = searchError {
                errorStateView(message: err)
            } else if results.isEmpty {
                emptyStateView
            } else {
                resultsListView
            }
        }
    }

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(results) { item in
                    subtitleRow(item)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func subtitleRow(_ item: SubtitleSearchResult) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Language Flag
            Text(item.languageFlag)
                .font(.system(size: 24))
                .frame(width: 34)

            // Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.releaseName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if item.isExactHashMatch {
                        Text("Exact Match")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }

                    if item.hearingImpaired {
                        Text("SDH")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    if item.isHD {
                        Text("HD")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 12) {
                    Text(item.languageName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if item.downloadCount > 0 {
                        Text("⬇ \(formatCount(item.downloadCount))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if item.rating > 0 {
                        Text("★ \(String(format: "%.1f", item.rating))")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }

                    if let fps = item.fps, fps > 0 {
                        Text("\(String(format: "%.2f", fps)) fps")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Text(item.fileName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Download / Applied Button
            if appliedFileId == item.fileId {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Applied")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else if downloadingFileId == item.fileId {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80)
            } else {
                Button("Download") {
                    downloadSubtitle(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.isExactHashMatch ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.isExactHashMatch ? Color.green.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Subtitles Found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Try searching with a shorter title, year, or selecting 'All Languages'.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            if let webURL = quotaErrorWebURL {
                Button("Open in Browser to Download ↗") {
                    NSWorkspace.shared.open(webURL)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Link("OpenSubtitles.com", destination: URL(string: "https://www.opensubtitles.com")!)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Actions

    private func setupInitialState() {
        // Preferred language
        selectedLanguage = service.preferredLanguage

        // Determine initial search query from current media source
        if let source = coordinator.currentSource {
            switch source {
            case .local(let url):
                let rawName = url.deletingPathExtension().lastPathComponent
                searchQuery = OpenSubtitlesService.cleanTitle(from: rawName)

                // Calculate MovieHash in background
                isCalculatingHash = true
                Task.detached(priority: .userInitiated) {
                    let hash = try? OpenSubtitlesHasher.calculateHash(for: url)
                    await MainActor.run {
                        self.computedMovieHash = hash
                        self.isCalculatingHash = false
                        // Automatically perform search with exact hash and query
                        self.performSearch()
                    }
                }
                return

            case .online(_, _):
                if let title = coordinator.extractedOnlineInfo?.title, !title.isEmpty {
                    searchQuery = OpenSubtitlesService.cleanTitle(from: title)
                } else {
                    searchQuery = OpenSubtitlesService.cleanTitle(from: source.displayName)
                }
                performSearch()
                return
            }
        }
    }

    private func performSearch() {
        guard !isSearching else { return }
        isSearching = true
        searchError = nil
        quotaErrorWebURL = nil

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = computedMovieHash
        let lang = selectedLanguage

        Task {
            do {
                let fetched = try await service.search(
                    query: query.isEmpty ? nil : query,
                    movieHash: hash,
                    languageCode: lang
                )
                self.results = fetched
                self.isSearching = false
            } catch {
                self.isSearching = false
                self.searchError = error.localizedDescription
            }
        }
    }

    private func downloadSubtitle(_ item: SubtitleSearchResult) {
        downloadingFileId = item.fileId
        searchError = nil
        quotaErrorWebURL = nil

        Task {
            do {
                let localURL = try await service.download(result: item)
                SubtitleManager.shared.loadExternalSubtitle(from: localURL)
                self.appliedFileId = item.fileId
                self.downloadingFileId = nil
                PlayerController.shared.showHUD(
                    message: "Applied: \(item.languageName) Subtitles",
                    iconName: "captions.bubble.fill"
                )
            } catch let OpenSubtitlesError.quotaExceeded(msg, _, webURL) {
                self.downloadingFileId = nil
                self.searchError = msg
                self.quotaErrorWebURL = webURL ?? item.webURL
            } catch {
                self.downloadingFileId = nil
                self.searchError = error.localizedDescription
            }
        }
    }

    private func loginUser() {
        guard !inputUsername.isEmpty, !inputPassword.isEmpty else { return }
        isLoggingIn = true
        loginError = nil

        Task {
            do {
                try await service.login(username: inputUsername, password: inputPassword)
                self.isLoggingIn = false
                self.showAccountSettings = false
                self.inputPassword = ""
            } catch {
                self.isLoggingIn = false
                self.loginError = error.localizedDescription
            }
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

/// Helper that provides standard macOS AppKit visual effect backdrop for sheets.
private struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sheet
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
