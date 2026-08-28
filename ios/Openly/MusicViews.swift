import SwiftUI

// MARK: - Preferences

struct MusicPreferencesView: View {
    @EnvironmentObject private var session: AppSession

    @State private var profile: MusicProfile?
    @State private var genres: [MusicGenre] = []
    @State private var query = ""
    @State private var results: [MusicArtist] = []
    @State private var isLoading = true
    @State private var busy: String?
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if session.user == nil {
                LoginRequiredView(message: "سجّل الدخول لإضافة ذوقك الموسيقي.")
            } else if isLoading && profile == nil {
                ProgressView("جارِ تحميل تفضيلاتك")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
            } else if let profile {
                content(profile)
            } else {
                VStack(spacing: 16) {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "تعذر تحميل تفضيلاتك",
                        message: errorMessage ?? "تحقق من اتصالك وحاول مجددًا."
                    )
                    Button("المحاولة مجددًا") { Task { await load() } }
                        .buttonStyle(OpenlySecondaryButtonStyle())
                        .padding(.horizontal, 28)
                }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("ذوقي الموسيقي")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { if session.user != nil { await load() } }
    }

    @ViewBuilder
    private func content(_ profile: MusicProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("اختياري تمامًا. لا نطلب ربط أي حساب موسيقى، ولا نجمع سجل استماعك.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineSpacing(4)

                NavigationLink(destination: FavoriteTracksView()) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(OpenlyTheme.accentSoft)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.accent)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("الأغاني المفضلة")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(OpenlyTheme.ink)
                            Text("اختر أغاني حقيقية مع الغلاف والفنان والألبوم")
                                .font(.system(size: 13))
                                .foregroundColor(OpenlyTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text("\((profile.tracks ?? []).count) / \(MusicNormalize.maxTracksPerProfile)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OpenlyTheme.subtle)
                    }
                    .padding(16)
                    .background(OpenlyTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)

                sectionCard("الظهور") {
                    Toggle(isOn: Binding(
                        get: { profile.discoveryOptIn },
                        set: { value in
                            Task { await saveSettings(discoveryOptIn: value, preferencesPublic: profile.preferencesPublic) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("اظهر في اكتشاف الموسيقى").font(.system(size: 16, weight: .semibold))
                            Text("يظهر كودك ولونك ونقاط التشابه فقط.")
                                .font(.system(size: 13)).foregroundColor(OpenlyTheme.muted)
                        }
                    }
                    .disabled(busy != nil)

                    Divider().background(OpenlyTheme.line)

                    Toggle(isOn: Binding(
                        get: { profile.preferencesPublic },
                        set: { value in
                            Task { await saveSettings(discoveryOptIn: profile.discoveryOptIn, preferencesPublic: value) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("اعرض قائمتي كاملة في صفحتي").font(.system(size: 16, weight: .semibold))
                            Text("من دون هذا الخيار لا يظهر إلا المشترك بينكما.")
                                .font(.system(size: 13)).foregroundColor(OpenlyTheme.muted)
                        }
                    }
                    .disabled(busy != nil)
                }

                sectionCard("التصنيفات (\(profile.genres.count)/\(MusicNormalize.maxGenresPerProfile))") {
                    FlowChips(
                        genres: genres,
                        selected: Set(profile.genres.map(\.id)),
                        disabled: busy != nil
                    ) { genre in
                        let selected = profile.genres.contains(where: { $0.id == genre.id })
                        let next = selected
                            ? profile.genres.filter { $0.id != genre.id }
                            : profile.genres + [genre]
                        guard selected || next.count <= MusicNormalize.maxGenresPerProfile else {
                            errorMessage = "الحد الأقصى \(MusicNormalize.maxGenresPerProfile) تصنيفًا."
                            return
                        }
                        Task { await saveGenres(next) }
                    }
                }

                sectionCard("الفنانون (\(profile.artists.count)/\(MusicNormalize.maxArtistsPerProfile))") {
                    TextField("ابحث أو أضف فنانًا", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(OpenlyTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .autocorrectionDisabled()
                        .onChange(of: query) { value in scheduleSearch(value) }

                    ForEach(results) { artist in
                        Button {
                            Task { await add(artist, to: profile) }
                        } label: {
                            HStack {
                                Text(artist.name).font(.system(size: 16))
                                Spacer()
                                Text(profile.artists.contains(where: { $0.id == artist.id }) ? "مضاف" : "إضافة")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.accent)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy != nil || profile.artists.contains(where: { $0.id == artist.id }))
                    }

                    if !query.trimmingCharacters(in: .whitespaces).isEmpty,
                       !results.contains(where: { MusicNormalize.isSameName($0.name, query) }) {
                        Button {
                            Task { await createArtist(into: profile) }
                        } label: {
                            Label("أضف «\(query.trimmingCharacters(in: .whitespaces))» كفنان جديد", systemImage: "plus")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(OpenlySecondaryButtonStyle())
                        .disabled(busy != nil)
                    }

                    if profile.artists.isEmpty {
                        Text("لم تضف أي فنان بعد.")
                            .font(.system(size: 14))
                            .foregroundColor(OpenlyTheme.subtle)
                            .padding(.top, 6)
                    } else {
                        ForEach(Array(profile.artists.enumerated()), id: \.element.id) { index, artist in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.subtle)
                                    .frame(minWidth: 18)
                                    .environment(\.layoutDirection, .leftToRight)
                                Text(artist.name).font(.system(size: 16))
                                Spacer(minLength: 8)
                                iconButton("chevron.up", label: "نقل للأعلى", disabled: index == 0) {
                                    Task { await move(index, by: -1, in: profile) }
                                }
                                iconButton("chevron.down", label: "نقل للأسفل", disabled: index == profile.artists.count - 1) {
                                    Task { await move(index, by: 1, in: profile) }
                                }
                                iconButton("xmark", label: "إزالة \(artist.name)", disabled: false, danger: true) {
                                    Task { await saveArtists(profile.artists.filter { $0.id != artist.id }) }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OpenlyTheme.danger)
                }

                Button(role: .destructive) {
                    Task { await clearAll() }
                } label: {
                    Label("حذف كل بيانات الموسيقى", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OpenlyTheme.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(Capsule().stroke(OpenlyTheme.danger.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(busy != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .refreshable { await load() }
    }

    private func iconButton(_ systemName: String, label: String, disabled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(danger ? OpenlyTheme.danger : OpenlyTheme.muted)
                .frame(width: 40, height: 40)
                .background(OpenlyTheme.surfaceSoft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy != nil)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(OpenlyTheme.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(OpenlyTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
    }

    // MARK: Data

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let mine = session.api.musicProfile()
            async let catalog = session.api.musicGenres()
            profile = try await mine
            genres = (try? await catalog) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            let found = (try? await session.api.searchMusicArtists(query: term)) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run { results = found }
        }
    }

    @MainActor
    private func saveSettings(discoveryOptIn: Bool, preferencesPublic _: Bool) async {
        busy = "settings"
        errorMessage = nil
        do {
            profile = try await session.api.updateMusicSettings(
                discoveryOptIn: discoveryOptIn,
                showTracks: profile.tracksArePublic,
                showArtists: profile.artistsArePublic,
                showGenres: profile.genresArePublic
            )
        } catch { errorMessage = error.localizedDescription }
        busy = nil
    }

    @MainActor
    private func saveArtists(_ artists: [MusicArtist]) async {
        busy = "artists"
        errorMessage = nil
        do {
            profile = try await session.api.updateMusicArtists(ids: artists.map(\.id))
        } catch { errorMessage = error.localizedDescription }
        busy = nil
    }

    @MainActor
    private func saveGenres(_ list: [MusicGenre]) async {
        busy = "genres"
        errorMessage = nil
        do {
            profile = try await session.api.updateMusicGenres(ids: list.map(\.id))
        } catch { errorMessage = error.localizedDescription }
        busy = nil
    }

    @MainActor
    private func add(_ artist: MusicArtist, to profile: MusicProfile) async {
        guard !profile.artists.contains(where: { $0.id == artist.id }) else { return }
        guard profile.artists.count < MusicNormalize.maxArtistsPerProfile else {
            errorMessage = "الحد الأقصى \(MusicNormalize.maxArtistsPerProfile) فنانًا."
            return
        }
        query = ""
        results = []
        await saveArtists(profile.artists + [artist])
    }

    @MainActor
    private func createArtist(into profile: MusicProfile) async {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = "create"
        errorMessage = nil
        do {
            // The server folds the name first, so a differently spelled variant
            // resolves to the existing catalog row instead of a duplicate.
            let artist = try await session.api.addMusicArtist(name: name)
            busy = nil
            await add(artist, to: profile)
        } catch {
            errorMessage = error.localizedDescription
            busy = nil
        }
    }

    @MainActor
    private func move(_ index: Int, by delta: Int, in profile: MusicProfile) async {
        var next = profile.artists
        let target = index + delta
        guard target >= 0, target < next.count else { return }
        next.swapAt(index, target)
        await saveArtists(next)
    }

    @MainActor
    private func clearAll() async {
        busy = "clear"
        errorMessage = nil
        do {
            profile = try await session.api.clearMusicPreferences()
        } catch { errorMessage = error.localizedDescription }
        busy = nil
    }
}

private struct FlowChips: View {
    let genres: [MusicGenre]
    let selected: Set<String>
    let disabled: Bool
    let onTap: (MusicGenre) -> Void

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(genres) { genre in
                let isOn = selected.contains(genre.id)
                Button { onTap(genre) } label: {
                    Text(genre.nameAr)
                        .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                        .foregroundColor(isOn ? OpenlyTheme.accentForeground : OpenlyTheme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isOn ? OpenlyTheme.accent : OpenlyTheme.background)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isOn ? Color.clear : OpenlyTheme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel(genre.nameAr)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Discovery

struct MusicDiscoveryView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var matches: [MusicMatch] = []
    @State private var total = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var genres: [MusicGenre] = []
    @State private var genreID: String?
    @State private var didLoad = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AppHeader()

                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لرؤية من يشاركك ذوقك.")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ScreenHeader(
                                "اكتشاف بالموسيقى",
                                subtitle: "أشخاص اختاروا الظهور هنا ويشاركونك الذوق. المساحة العامة تبقى زمنية كما هي."
                            )

                            genreFilter

                            if isLoading && matches.isEmpty {
                                ProgressView()
                                    .tint(OpenlyTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else if let errorMessage, matches.isEmpty {
                                VStack(spacing: 16) {
                                    EmptyState(icon: "wifi.exclamationmark", title: "تعذر تحميل الاقتراحات", message: errorMessage)
                                    Button("المحاولة مجددًا") { Task { await load(reset: true) } }
                                        .buttonStyle(OpenlySecondaryButtonStyle())
                                        .padding(.horizontal, 28)
                                }
                            } else if matches.isEmpty {
                                VStack(spacing: 16) {
                                    EmptyState(
                                        icon: "music.note.list",
                                        title: "لا توجد نتائج بعد",
                                        message: "أضف فنانين وتصنيفات إلى ملفك، وفعّل خيار الظهور، لتبدأ المطابقة."
                                    )
                                    NavigationLink(destination: MusicPreferencesView()) {
                                        Text("عدّل ذوقك الموسيقي")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .buttonStyle(OpenlySecondaryButtonStyle())
                                    .padding(.horizontal, 28)
                                }
                            } else {
                                Text("\(total) نتيجة")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.subtle)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)

                                ForEach(matches) { match in
                                    MatchCard(match: match)
                                        .onAppear {
                                            if match.id == matches.last?.id, hasMore, !isLoadingMore {
                                                Task { await load(reset: false) }
                                            }
                                        }
                                }

                                if isLoadingMore {
                                    ProgressView().tint(OpenlyTheme.accent).padding(.vertical, 22)
                                }
                            }
                        }
                    }
                    .refreshable { await load(reset: true) }
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                guard !didLoad, session.user != nil else { return }
                didLoad = true
                genres = (try? await session.api.musicGenres()) ?? []
                await load(reset: true)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, session.user != nil else { return }
                Task { await load(reset: true) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var genreFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "الكل", isOn: genreID == nil) {
                    genreID = nil
                    Task { await load(reset: true) }
                }
                ForEach(genres) { genre in
                    filterChip(title: genre.nameAr, isOn: genreID == genre.id) {
                        genreID = genreID == genre.id ? nil : genre.id
                        Task { await load(reset: true) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func filterChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                .foregroundColor(isOn ? OpenlyTheme.accentForeground : OpenlyTheme.ink)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(isOn ? OpenlyTheme.accent : OpenlyTheme.background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isOn ? Color.clear : OpenlyTheme.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @MainActor
    private func load(reset: Bool) async {
        if reset { isLoading = true } else { isLoadingMore = true }
        errorMessage = nil
        do {
            let response = try await session.api.discoverMusicPeople(
                genreID: genreID,
                limit: 20,
                offset: reset ? 0 : matches.count
            )
            matches = reset ? response.items : matches + response.items.filter { incoming in
                !matches.contains(where: { $0.publicCode == incoming.publicCode })
            }
            total = response.total
            hasMore = response.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        isLoadingMore = false
    }
}

private struct MatchCard: View {
    let match: MusicMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                IdentityBadge(code: match.publicCode, color: match.identityColor)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(match.compatibility)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(OpenlyTheme.ink)
                        .environment(\.layoutDirection, .leftToRight)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(OpenlyTheme.line)
                            Capsule()
                                .fill(OpenlyTheme.accent)
                                .frame(width: max(6, proxy.size.width * CGFloat(match.compatibility) / 100))
                        }
                    }
                    .frame(width: 108, height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("نسبة التشابه \(match.compatibility) بالمئة")
            }

            if !match.sharedArtists.isEmpty {
                reasonRow(title: "فنانون مشتركون", value: match.sharedArtists.map(\.name).joined(separator: "، "))
            }
            if !match.sharedGenres.isEmpty {
                reasonRow(title: "تصنيفات مشتركة", value: match.sharedGenres.map(\.nameAr).joined(separator: "، "))
            }

            Text("محسوبة من \(match.sharedArtistCount) فنان و\(match.sharedGenreCount) تصنيف مشترك؛ الفنان يزن ثلاثة أضعاف التصنيف.")
                .font(.system(size: 12))
                .foregroundColor(OpenlyTheme.subtle)
                .lineSpacing(3)

            NavigationLink(destination: UserProfileView(code: match.publicCode)) {
                Text("عرض الكتابات")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OpenlyTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }

    private func reasonRow(title: String, value: String) -> some View {
        (Text("\(title): ").foregroundColor(OpenlyTheme.muted) + Text(value).foregroundColor(OpenlyTheme.ink))
            .font(.system(size: 15))
            .fixedSize(horizontal: false, vertical: true)
    }
}
