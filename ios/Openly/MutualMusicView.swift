import SwiftUI

struct MutualMusicView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var mode = 0
    @State private var suggestions: [MusicMatch] = []
    @State private var mutualMatches: [MusicMatch] = []
    @State private var total = 0
    @State private var matchTotal = 0
    @State private var isLoading = false
    @State private var matchesLoaded = false
    @State private var busyCode: String?
    @State private var errorMessage: String?
    @State private var matchMessage: String?
    @State private var genres: [MusicGenre] = []
    @State private var genreID: String?
    @State private var didLoad = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AppHeader()

                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لاستخدام المطابقة بالموسيقى.")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ScreenHeader(
                                "المطابقة بالموسيقى",
                                subtitle: "اختيار متبادل وهادئ. اهتمامك لا يظهر للطرف الآخر إلا إذا اختارك هو أيضًا."
                            )

                            HStack(spacing: 10) {
                                NavigationLink(destination: MusicVisibilitySettingsView()) {
                                    Label("ما يظهر في ملفي", systemImage: "eye")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(OpenlyTheme.accent)

                                NavigationLink(destination: MusicPreferencesView()) {
                                    Label("تعديل ذوقي", systemImage: "slider.horizontal.3")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(OpenlyTheme.muted)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)

                            Picker("نوع القائمة", selection: $mode) {
                                Text("اقتراحات").tag(0)
                                Text("الماتشات\(matchTotal > 0 ? " (\(matchTotal))" : "")").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                            .onChange(of: mode) { value in
                                if value == 1 && !matchesLoaded {
                                    Task { await loadMatches() }
                                }
                            }

                            if let matchMessage {
                                Text(matchMessage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.accent)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 14)
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OpenlyTheme.danger)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 14)
                            }

                            if mode == 0 {
                                genreFilter
                                suggestionContent
                            } else {
                                matchContent
                            }
                        }
                    }
                    .refreshable {
                        if mode == 0 { await loadSuggestions() }
                        else { await loadMatches() }
                    }
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                guard !didLoad, session.user != nil else { return }
                didLoad = true
                genres = (try? await session.api.musicGenres()) ?? []
                await loadSuggestions()
                await loadMatches()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, session.user != nil else { return }
                Task {
                    await loadSuggestions()
                    if matchesLoaded { await loadMatches() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var genreFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "الكل", selected: genreID == nil) {
                    genreID = nil
                    Task { await loadSuggestions() }
                }
                ForEach(genres) { genre in
                    filterChip(title: genre.nameAr, selected: genreID == genre.id) {
                        genreID = genreID == genre.id ? nil : genre.id
                        Task { await loadSuggestions() }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if isLoading && suggestions.isEmpty {
            ProgressView()
                .tint(OpenlyTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
        } else if suggestions.isEmpty {
            VStack(spacing: 12) {
                EmptyState(
                    icon: "music.note.list",
                    title: "لا توجد اقتراحات بعد",
                    message: "أضف فنانين وتصنيفات وفعّل الظهور في المطابقة."
                )
                NavigationLink(destination: MusicPreferencesView()) {
                    Text("تعديل ذوقي الموسيقي")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(OpenlySecondaryButtonStyle())
                .padding(.horizontal, 28)
            }
        } else {
            Text("\(total) اقتراح")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OpenlyTheme.subtle)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(suggestions) { match in
                NativeMusicMatchCard(
                    match: match,
                    isMutualList: false,
                    isBusy: busyCode == match.publicCode,
                    onInterest: { Task { await toggleInterest(match) } },
                    onRemove: nil
                )
            }
        }
    }

    @ViewBuilder
    private var matchContent: some View {
        if !matchesLoaded {
            ProgressView()
                .tint(OpenlyTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
        } else if mutualMatches.isEmpty {
            EmptyState(
                icon: "person.2",
                title: "لا توجد ماتشات متبادلة بعد",
                message: "اختر من الاقتراحات. إذا اختارك الطرف الآخر أيضًا سيظهر التطابق هنا فقط."
            )
        } else {
            Text("\(matchTotal) ماتش")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OpenlyTheme.subtle)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(mutualMatches) { match in
                NativeMusicMatchCard(
                    match: match,
                    isMutualList: true,
                    isBusy: busyCode == match.publicCode,
                    onInterest: nil,
                    onRemove: { Task { await removeMatch(match) } }
                )
            }
        }
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? OpenlyTheme.accentForeground : OpenlyTheme.ink)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(selected ? OpenlyTheme.accent : OpenlyTheme.background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : OpenlyTheme.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadSuggestions() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await session.api.discoverMusicPeople(
                genreID: genreID,
                limit: 50,
                offset: 0
            )
            suggestions = response.items
            total = response.total
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func loadMatches() async {
        errorMessage = nil
        do {
            let response = try await session.api.musicMatches(limit: 50, offset: 0)
            mutualMatches = response.items
            matchTotal = response.total
            matchesLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            matchesLoaded = true
        }
    }

    @MainActor
    private func toggleInterest(_ match: MusicMatch) async {
        guard busyCode == nil else { return }
        busyCode = match.publicCode
        errorMessage = nil
        matchMessage = nil
        do {
            let nextInterest = !(match.interested ?? false)
            let state = try await session.api.setMusicMatchInterest(
                code: match.publicCode,
                interested: nextInterest
            )
            if let index = suggestions.firstIndex(where: { $0.publicCode == match.publicCode }) {
                suggestions[index].interested = state.interested
                suggestions[index].matched = state.matched
                suggestions[index].matchedAt = state.matchedAt
            }
            if state.matched {
                matchMessage = "حدث تطابق متبادل مع \(state.publicCode)."
                await loadMatches()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyCode = nil
    }

    @MainActor
    private func removeMatch(_ match: MusicMatch) async {
        guard busyCode == nil else { return }
        busyCode = match.publicCode
        errorMessage = nil
        do {
            try await session.api.removeMusicMatch(code: match.publicCode)
            mutualMatches.removeAll { $0.publicCode == match.publicCode }
            matchTotal = max(0, matchTotal - 1)
            if let index = suggestions.firstIndex(where: { $0.publicCode == match.publicCode }) {
                suggestions[index].interested = false
                suggestions[index].matched = false
                suggestions[index].matchedAt = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyCode = nil
    }
}

private struct NativeMusicMatchCard: View {
    let match: MusicMatch
    let isMutualList: Bool
    let isBusy: Bool
    let onInterest: (() -> Void)?
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IdentityBadge(code: match.publicCode, color: match.identityColor)
                Spacer()
                Text("\(match.compatibility)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(OpenlyTheme.ink)
                    .environment(\.layoutDirection, .leftToRight)
            }

            if !match.sharedArtists.isEmpty {
                reason(title: "فنانون مشتركون", value: match.sharedArtists.map(\.name).joined(separator: "، "))
            }
            if !match.sharedGenres.isEmpty {
                reason(title: "تصنيفات مشتركة", value: match.sharedGenres.map(\.nameAr).joined(separator: "، "))
            }

            if isMutualList, let matchedAt = match.matchedAt {
                Text("تطابق \(OpenlyDate.short(matchedAt))")
                    .font(.system(size: 12))
                    .foregroundColor(OpenlyTheme.subtle)
            }

            HStack(spacing: 10) {
                NavigationLink(destination: UserProfileView(code: match.publicCode)) {
                    Text(isMutualList ? "فتح الملف" : "عرض الكتابات")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OpenlyTheme.accent)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if isMutualList {
                    if let onRemove {
                        Button(action: onRemove) {
                            Label("إلغاء التطابق", systemImage: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OpenlyTheme.danger)
                                .padding(.horizontal, 14)
                                .frame(height: 42)
                                .overlay(Capsule().stroke(OpenlyTheme.danger.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                } else if match.matched == true {
                    Label("تطابق متبادل", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(OpenlyTheme.accent)
                } else if let onInterest {
                    Button(action: onInterest) {
                        Label(
                            match.interested == true ? "إلغاء الاهتمام" : "مهتم بهذا التوافق",
                            systemImage: match.interested == true ? "heart.fill" : "heart"
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(match.interested == true ? OpenlyTheme.muted : OpenlyTheme.accentForeground)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(match.interested == true ? OpenlyTheme.surfaceSoft : OpenlyTheme.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }

            if !isMutualList && match.interested == true && match.matched != true {
                Text("اختيارك سري. لن يعرف الطرف الآخر إلا إذا اختارك أيضًا.")
                    .font(.system(size: 12))
                    .foregroundColor(OpenlyTheme.subtle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }

    private func reason(title: String, value: String) -> some View {
        (Text("\(title): ").foregroundColor(OpenlyTheme.muted) + Text(value).foregroundColor(OpenlyTheme.ink))
            .font(.system(size: 14))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MusicVisibilitySettingsView: View {
    @EnvironmentObject private var session: AppSession

    @State private var profile: MusicProfile?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && profile == nil {
                ProgressView("جارِ تحميل الإعدادات")
                    .tint(OpenlyTheme.accent)
            } else if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("أنت تختار ما يظهر في ملفك. إخفاء عنصر من الصفحة لا يمنع استخدامه داخليًا لحساب التشابه.")
                            .font(.system(size: 14))
                            .foregroundColor(OpenlyTheme.muted)
                            .lineSpacing(4)

                        visibilityToggle(
                            title: "أظهرني في اقتراحات المطابقة",
                            subtitle: "يسمح للحسابات المتشابهة بالعثور على كودك.",
                            value: profile.discoveryOptIn
                        ) { value in
                            Task { await save(profile: profile, discovery: value) }
                        }

                        Divider().background(OpenlyTheme.line)

                        visibilityToggle(
                            title: "إظهار الأغاني المفضلة",
                            subtitle: "يعرض الأغنية والفنان والغلاف.",
                            value: profile.tracksArePublic
                        ) { value in
                            Task { await save(profile: profile, showTracks: value) }
                        }

                        visibilityToggle(
                            title: "إظهار الفنانين",
                            subtitle: "يمكن إخفاؤهم مع بقائهم ضمن حساب التشابه.",
                            value: profile.artistsArePublic
                        ) { value in
                            Task { await save(profile: profile, showArtists: value) }
                        }

                        visibilityToggle(
                            title: "إظهار التصنيفات",
                            subtitle: "مثل روك، راب أو طرب.",
                            value: profile.genresArePublic
                        ) { value in
                            Task { await save(profile: profile, showGenres: value) }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OpenlyTheme.danger)
                        }
                    }
                    .padding(20)
                }
            } else {
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "تعذر تحميل الإعدادات",
                    message: errorMessage ?? "حاول مرة أخرى."
                )
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("ما يظهر في ملفي")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
    }

    private func visibilityToggle(
        title: String,
        subtitle: String,
        value: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { value }, set: onChange)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 13))
                    .foregroundColor(OpenlyTheme.muted)
            }
        }
        .disabled(isSaving)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await session.api.musicProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func save(
        profile current: MusicProfile,
        discovery: Bool? = nil,
        showTracks: Bool? = nil,
        showArtists: Bool? = nil,
        showGenres: Bool? = nil
    ) async {
        isSaving = true
        errorMessage = nil
        do {
            profile = try await session.api.updateMusicSettings(
                discoveryOptIn: discovery ?? current.discoveryOptIn,
                showTracks: showTracks ?? current.tracksArePublic,
                showArtists: showArtists ?? current.artistsArePublic,
                showGenres: showGenres ?? current.genresArePublic
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
