import SwiftUI
import CryptoKit
import LinkPresentation
import UIKit

private let maxInterestsPerProfile = 36
private let maxInterestsPerKind = 12

private func interestTitle(_ kind: InterestKind) -> String {
    switch kind {
    case .topic: return NSLocalizedString("مواضيع الحديث", comment: "")
    case .book: return NSLocalizedString("الكتب", comment: "")
    case .movie: return NSLocalizedString("الأفلام", comment: "")
    }
}

/// Loads interest artwork as native image data instead of leaving rendering to
/// AsyncImage. It keeps a memory + disk cache, retries transient image failures,
/// and can fall back to the official Apple Books/TV page metadata when the
/// catalog API did not return a direct artwork URL.
private final class InterestArtworkLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private var task: Task<Void, Never>?
    private static let memory = NSCache<NSString, UIImage>()
    private static let cacheDirectory: URL = {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("OpenlyInterestArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }()

    func load(item: InterestItem) {
        task?.cancel()

        let key = Self.cacheKey(for: item)
        if let cached = Self.memory.object(forKey: key as NSString) {
            image = cached
            return
        }

        let diskURL = Self.diskURL(for: key)
        if let data = try? Data(contentsOf: diskURL),
           let cached = UIImage(data: data) {
            Self.memory.setObject(cached, forKey: key as NSString)
            image = cached
            return
        }

        image = nil
        task = Task { [weak self] in
            guard let loaded = await Self.fetch(item: item), !Task.isCancelled else { return }
            Self.memory.setObject(loaded, forKey: key as NSString)
            if let data = loaded.jpegData(compressionQuality: 0.9) {
                try? data.write(to: diskURL, options: .atomic)
            }
            await MainActor.run {
                self?.image = loaded
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func cacheKey(for item: InterestItem) -> String {
        item.artworkUrl ?? item.externalUrl ?? item.id
    }

    private static func diskURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent(digest).appendingPathExtension("jpg")
    }

    private static func httpsURL(_ raw: String?) -> URL? {
        guard let raw,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func fetch(item: InterestItem) async -> UIImage? {
        if let artwork = httpsURL(item.artworkUrl),
           let image = await fetchDirectImage(from: artwork) {
            return image
        }

        guard let external = httpsURL(item.externalUrl),
              let host = external.host?.lowercased(),
              host == "tv.apple.com" || host == "books.apple.com" else {
            return nil
        }

        return await fetchApplePagePreview(from: external)
    }

    private static func fetchDirectImage(from url: URL) async -> UIImage? {
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }

            var request = URLRequest(url: url)
            request.timeoutInterval = 9
            request.cachePolicy = attempt == 0 ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if (200...299).contains(status), let image = UIImage(data: data) {
                    return image
                }
            } catch {
                // A second/third attempt handles brief mobile-network drops.
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 350_000_000)
            }
        }
        return nil
    }

    private static func fetchApplePagePreview(from url: URL) async -> UIImage? {
        guard let metadata = await linkMetadata(for: url) else { return nil }

        if let provider = metadata.imageProvider,
           let image = await loadImage(from: provider) {
            return image
        }

        if let provider = metadata.iconProvider,
           let image = await loadImage(from: provider) {
            return image
        }

        return nil
    }

    private static func linkMetadata(for url: URL) async -> LPLinkMetadata? {
        await withCheckedContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.startFetchingMetadata(for: url) { metadata, _ in
                _ = provider
                continuation.resume(returning: metadata)
            }
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}

private struct InterestArtwork: View {
    let item: InterestItem
    var width: CGFloat = 48
    var height: CGFloat = 66

    @StateObject private var loader = InterestArtworkLoader()

    private var cacheIdentity: String {
        item.artworkUrl ?? item.externalUrl ?? item.id
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(OpenlyTheme.line, lineWidth: 1)
        )
        .task(id: cacheIdentity) {
            loader.load(item: item)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var placeholder: some View {
        ZStack {
            OpenlyTheme.surfaceSoft
            Image(systemName: item.interestKind?.systemImage ?? "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(OpenlyTheme.subtle)
        }
    }
}

// MARK: - Preferences

struct InterestPreferencesView: View {
    @EnvironmentObject private var session: AppSession

    let isOnboarding: Bool
    let onComplete: (() -> Void)?

    init(isOnboarding: Bool = false, onComplete: (() -> Void)? = nil) {
        self.isOnboarding = isOnboarding
        self.onComplete = onComplete
    }

    @State private var profile: InterestProfile?
    @State private var selected: [InterestItem] = []
    @State private var kind: InterestKind = .topic
    @State private var query = ""
    @State private var results: [InterestItem] = []
    @State private var discoveryOptIn = true
    @State private var preferencesPublic = true
    @State private var isLoading = true
    @State private var busyID: String?
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if session.user == nil {
                LoginRequiredView(message: "سجّل الدخول لاختيار اهتماماتك.")
            } else if isLoading && profile == nil {
                ProgressView("جارِ تحميل اهتماماتك")
                    .tint(OpenlyTheme.accent)
            } else {
                content
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle(
            isOnboarding
                ? NSLocalizedString("اختر اهتماماتك", comment: "")
                : NSLocalizedString("اهتماماتي", comment: "")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { if session.user != nil { await load() } }
        .onDisappear { searchTask?.cancel() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isOnboarding {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("ابدأ بما يهمك")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(OpenlyTheme.ink)
                            Text("هذه الخطوة تجعل الاكتشاف مفيدًا من أول مرة، ويمكنك تغيير اختياراتك لاحقًا.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OpenlyTheme.muted)
                        }
                        Spacer(minLength: 16)
                        Button {
                            onComplete?()
                        } label: {
                            Text("تخطي الآن")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(OpenlyTheme.accent)
                    }
                }

                Text("اختر الكتب والأفلام ومواضيع الحديث التي تهمك. تستخدم هذه الاختيارات لإيجاد أرضية مشتركة، وتبقى الموسيقى ضمن ملفها الحالي.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineSpacing(4)

                kindPicker

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(interestTitle(kind))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(OpenlyTheme.ink)
                        Spacer()
                        Text("\(selectedForKind.count) / \(maxInterestsPerKind)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)
                    }

                    if !selectedForKind.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                            ForEach(selectedForKind) { item in
                                Button {
                                    selected.removeAll { $0.id == item.id }
                                    savedMessage = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(item.label)
                                            .lineLimit(1)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.accentForeground)
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .frame(maxWidth: .infinity)
                                    .background(OpenlyTheme.accent)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    TextField(searchPlaceholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(OpenlyTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .onChange(of: query) { value in scheduleSearch(value) }

                    if kind != .topic && query.trimmingCharacters(in: .whitespacesAndNewlines).count == 1 {
                        Text("اكتب حرفين على الأقل للبحث في الكتالوج.")
                            .font(.system(size: 12))
                            .foregroundColor(OpenlyTheme.subtle)
                    }

                    ForEach(results) { item in
                        interestResult(item)
                    }

                    if kind == .topic, canCreateTopic {
                        Button {
                            Task { await createTopic() }
                        } label: {
                            Label(
                                busyID == "create-topic"
                                    ? NSLocalizedString("جارِ الإضافة…", comment: "")
                                    : String(
                                        format: NSLocalizedString("interest_add_topic_format", comment: ""),
                                        query.trimmingCharacters(in: .whitespacesAndNewlines)
                                    ),
                                systemImage: "plus"
                            )
                        }
                        .buttonStyle(OpenlySecondaryButtonStyle())
                        .disabled(busyID != nil)
                    }
                }
                .padding(18)
                .background(OpenlyTheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(OpenlyTheme.line, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: $discoveryOptIn) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("استخدم اهتماماتي في الاكتشاف")
                                .font(.system(size: 16, weight: .semibold))
                            Text("يسمح لـOpenly باقتراح أشخاص بينكم اهتمامات مشتركة.")
                                .font(.system(size: 13))
                                .foregroundColor(OpenlyTheme.muted)
                        }
                    }
                    .padding(.vertical, 12)

                    Divider().background(OpenlyTheme.line)

                    Toggle(isOn: $preferencesPublic) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("اعرض اهتماماتي في ملفي")
                                .font(.system(size: 16, weight: .semibold))
                            Text("يمكنك إخفاء القائمة مع إبقاء حساب التوافق مفعّلًا.")
                                .font(.system(size: 13))
                                .foregroundColor(OpenlyTheme.muted)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 18)
                .background(OpenlyTheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(OpenlyTheme.line, lineWidth: 1)
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OpenlyTheme.danger)
                }
                if let savedMessage {
                    Text(savedMessage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OpenlyTheme.accent)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(
                        busyID == "save"
                            ? NSLocalizedString("جارِ الحفظ…", comment: "")
                            : NSLocalizedString("حفظ الاهتمامات", comment: "")
                    )
                }
                .buttonStyle(OpenlyPrimaryButtonStyle())
                .disabled(busyID != nil || selected.count > maxInterestsPerProfile)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .refreshable { await load() }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(InterestKind.allCases) { value in
                Button {
                    kind = value
                    query = ""
                    errorMessage = nil
                    Task { await search("") }
                } label: {
                    Label(value.title, systemImage: value.systemImage)
                        .font(.system(size: 13, weight: kind == value ? .bold : .semibold))
                        .foregroundColor(kind == value ? OpenlyTheme.accentForeground : OpenlyTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(kind == value ? OpenlyTheme.accent : OpenlyTheme.surfaceSoft)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(kind == value ? Color.clear : OpenlyTheme.lineStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func interestResult(_ item: InterestItem) -> some View {
        let isSelected = selectedContains(item)
        Button {
            Task { await add(item) }
        } label: {
            HStack(spacing: 12) {
                InterestArtwork(item: item)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OpenlyTheme.ink)
                        .lineLimit(2)
                    let detail = [item.subtitle, item.releaseYear.map { String($0) }].compactMap { $0 }.joined(separator: " · ")
                    Text(detail.isEmpty ? (item.interestKind?.title ?? NSLocalizedString("اهتمام", comment: "")) : detail)
                        .font(.system(size: 13))
                        .foregroundColor(OpenlyTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(
                    isSelected
                        ? NSLocalizedString("مضاف", comment: "")
                        : busyID == item.id ? "…" : NSLocalizedString("إضافة", comment: "")
                )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? OpenlyTheme.subtle : OpenlyTheme.accent)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelected || busyID != nil)
    }

    private var selectedForKind: [InterestItem] {
        selected.filter { $0.kind == kind.rawValue }
    }

    private var searchPlaceholder: String {
        switch kind {
        case .topic: return NSLocalizedString("مثال: علم النفس", comment: "")
        case .book: return NSLocalizedString("ابحث عن كتاب أو كاتب", comment: "")
        case .movie: return NSLocalizedString("ابحث عن فيلم أو مخرج", comment: "")
        }
    }

    private var canCreateTopic: Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        return !results.contains { $0.label.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private func selectedContains(_ item: InterestItem) -> Bool {
        selected.contains { existing in
            if existing.id == item.id { return true }
            guard let externalId = item.externalId, let provider = item.provider else { return false }
            return existing.externalId == externalId && existing.provider == provider
        }
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await search(value)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let value = try await session.api.interestProfile()
            profile = value
            selected = value.items
            discoveryOptIn = value.discoveryOptIn
            preferencesPublic = value.preferencesPublic
            await search(query)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func search(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind != .topic && trimmed.count == 1 {
            results = []
            return
        }
        do {
            results = try await session.api.searchInterests(query: trimmed, kind: kind)
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func add(_ item: InterestItem) async {
        guard !selectedContains(item) else { return }
        guard selected.count < maxInterestsPerProfile else {
            errorMessage = String(
                format: NSLocalizedString("interest_limit_total", comment: ""),
                maxInterestsPerProfile
            )
            return
        }
        guard selectedForKind.count < maxInterestsPerKind else {
            errorMessage = String(
                format: NSLocalizedString("interest_limit_kind", comment: ""),
                maxInterestsPerKind
            )
            return
        }

        busyID = item.id
        errorMessage = nil
        do {
            let value = item.isCatalogResult ? try await session.api.persistCatalogInterest(item) : item
            selected.append(value)
            query = ""
            savedMessage = nil
            await search("")
        } catch {
            errorMessage = error.localizedDescription
        }
        busyID = nil
    }

    @MainActor
    private func createTopic() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        busyID = "create-topic"
        errorMessage = nil
        do {
            let item = try await session.api.createTopicInterest(label: term)
            await add(item)
        } catch {
            errorMessage = error.localizedDescription
        }
        if busyID == "create-topic" { busyID = nil }
    }

    @MainActor
    private func save() async {
        busyID = "save"
        errorMessage = nil
        savedMessage = nil
        do {
            let value = try await session.api.updateInterestProfile(
                discoveryOptIn: discoveryOptIn,
                preferencesPublic: preferencesPublic,
                interestIDs: selected.map(\.id)
            )
            profile = value
            selected = value.items
            savedMessage = NSLocalizedString("تم حفظ اهتماماتك.", comment: "")
            if isOnboarding {
                onComplete?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyID = nil
    }
}

// MARK: - Discovery

struct InterestDiscoveryView: View {
    @EnvironmentObject private var session: AppSession

    @State private var kind: InterestKind?
    @State private var items: [InterestMatch] = []
    @State private var total = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var loadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AppHeader()

                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لرؤية من يشاركك اهتماماتك.")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ScreenHeader(
                                "اكتشف",
                                subtitle: "أشخاص بينكم أرضية مشتركة في الكتب والأفلام والمواضيع، ومع الموسيقى عندما تكون مفعلة."
                            )

                            filterBar

                            if isLoading && items.isEmpty {
                                ProgressView()
                                    .tint(OpenlyTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else if let errorMessage, items.isEmpty {
                                EmptyState(icon: "wifi.exclamationmark", title: "تعذر تحميل الاقتراحات", message: errorMessage)
                            } else if items.isEmpty {
                                VStack(spacing: 16) {
                                    EmptyState(
                                        icon: "sparkles",
                                        title: "لا توجد اقتراحات بعد",
                                        message: "أضف بعض الكتب والأفلام ومواضيع الحديث التي تهمك."
                                    )
                                    NavigationLink(destination: InterestPreferencesView()) {
                                        Text("اختر اهتماماتك")
                                    }
                                    .buttonStyle(OpenlySecondaryButtonStyle())
                                    .padding(.horizontal, 28)
                                }
                            } else {
                                Text(
                                    String(
                                        format: NSLocalizedString("interest_suggestion_count", comment: ""),
                                        total
                                    )
                                )
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.subtle)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)

                                ForEach(items) { match in
                                    matchCard(match)
                                        .onAppear {
                                            if match.id == items.last?.id, hasMore, !loadingMore {
                                                Task { await load(reset: false) }
                                            }
                                        }
                                }

                                if loadingMore {
                                    ProgressView()
                                        .tint(OpenlyTheme.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 22)
                                }
                            }
                        }
                    }
                    .refreshable { await load(reset: true) }
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task(id: session.user?.publicCode) {
                if session.user != nil { await load(reset: true) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(title: "الكل", image: "square.grid.2x2", value: nil)
                ForEach(InterestKind.allCases) { value in
                    filterButton(title: value.title, image: value.systemImage, value: value)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    private func filterButton(title: String, image: String, value: InterestKind?) -> some View {
        let selected = kind == value
        return Button {
            kind = value
            Task { await load(reset: true) }
        } label: {
            Label(title, systemImage: image)
                .font(.system(size: 13, weight: selected ? .bold : .semibold))
                .foregroundColor(selected ? OpenlyTheme.accentForeground : OpenlyTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(selected ? OpenlyTheme.accent : OpenlyTheme.surfaceSoft)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : OpenlyTheme.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func matchCard(_ match: InterestMatch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NavigationLink(destination: UserProfileView(code: match.publicCode)) {
                    IdentityBadge(code: match.publicCode, color: match.identityColor)
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(match.compatibility)%")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(OpenlyTheme.ink)
                        .environment(\.layoutDirection, .leftToRight)
                    Text("توافق")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(OpenlyTheme.subtle)
                }
            }

            if !match.sharedItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(match.sharedItems.prefix(8)) { item in
                            HStack(spacing: 5) {
                                Image(systemName: item.interestKind?.systemImage ?? "sparkles")
                                Text(item.label).lineLimit(1)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OpenlyTheme.ink)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(OpenlyTheme.surfaceSoft)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(OpenlyTheme.line, lineWidth: 1))
                        }
                    }
                }
            }

            Text(
                String(
                    format: NSLocalizedString("interest_shared_count_format", comment: ""),
                    match.sharedTopicCount,
                    match.sharedBookCount,
                    match.sharedMovieCount
                )
            )
                .font(.system(size: 13))
                .foregroundColor(OpenlyTheme.muted)

            if match.musicCompatibility > 0 {
                Text(
                    String(
                        format: NSLocalizedString("interest_music_compatibility_format", comment: ""),
                        match.musicCompatibility
                    )
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
            }

            NavigationLink(destination: UserProfileView(code: match.publicCode)) {
                Text("عرض الملف والكتابات")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OpenlyTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OpenlyTheme.line).frame(height: 1)
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        if reset {
            isLoading = true
        } else {
            loadingMore = true
        }
        errorMessage = nil

        do {
            let response = try await session.api.discoverInterestPeople(
                kind: kind,
                limit: 20,
                offset: reset ? 0 : items.count
            )
            if reset {
                items = response.items
            } else {
                let existing = Set(items.map(\.publicCode))
                items += response.items.filter { !existing.contains($0.publicCode) }
            }
            total = response.total
            hasMore = response.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingMore = false
    }
}

// MARK: - Public profile

struct NativePublicInterestSection: View {
    let profile: PublicInterestProfile

    private var grouped: [(InterestKind, [InterestItem])] {
        InterestKind.allCases.compactMap { kind in
            let values = profile.items.filter { $0.kind == kind.rawValue }
            return values.isEmpty ? nil : (kind, values)
        }
    }

    var body: some View {
        if !grouped.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("الاهتمامات")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(OpenlyTheme.ink)
                    Spacer()
                    Text("\(profile.items.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OpenlyTheme.subtle)
                }

                ForEach(grouped, id: \.0.id) { kind, items in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                            Text(interestTitle(kind))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(OpenlyTheme.muted)

                        if kind == .topic {
                            FlowInterestChips(items: Array(items.prefix(10)))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(items.prefix(8)) { item in
                                        InterestMediaCard(item: item)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                            .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(OpenlyTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }
}

private struct InterestMediaCard: View {
    let item: InterestItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            InterestArtwork(item: item, width: 72, height: 96)

            Text(item.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 112, alignment: .leading)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineLimit(1)
                    .frame(width: 112, alignment: .leading)
            } else if let year = item.releaseYear {
                Text(String(year))
                    .font(.system(size: 11))
                    .foregroundColor(OpenlyTheme.subtle)
            }
        }
        .frame(width: 112, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct FlowInterestChips: View {
    let items: [InterestItem]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items) { item in
                Text(item.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(OpenlyTheme.surfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
