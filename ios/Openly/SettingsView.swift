import SwiftUI

private let nativeIdentityAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
private let nativeIdentityPalette = [
    "#D9484F", "#E85D75", "#F47B5D", "#E8A33F", "#C9A227",
    "#8AA64B", "#4F9D69", "#3E9B8E", "#3D8BB5", "#4A6FA5",
    "#6B5B95", "#8D6E63", "#A07E5C", "#9B6A6A", "#B8336A",
    "#2F4858", "#1B998B", "#5C7AEA", "#7B6EAA", "#D6A2E8"
]

private func normalizedNativeIdentityCode(_ value: String) -> String {
    String(
        value
            .uppercased()
            .filter { nativeIdentityAlphabet.contains($0) }
            .prefix(8)
    )
}

private func randomNativeIdentityCode(length: Int = 5) -> String {
    var generator = SystemRandomNumberGenerator()
    return String((0..<length).compactMap { _ in nativeIdentityAlphabet.randomElement(using: &generator) })
}

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("openly.appearance") private var appearanceRaw = OpenlyAppearance.system.rawValue
    @AppStorage("openly.language") private var languageRaw = OpenlyLanguage.arabic.rawValue
    @AppStorage("openly.colorTheme") private var colorThemeRaw = OpenlyColorTheme.graphite.rawValue

    @State private var publicCode = ""
    @State private var identityColor = "#5C7AEA"
    @State private var status = ""
    @State private var bio = ""
    @State private var isSaving = false
    @State private var inlineMessage: String?
    @State private var inlineError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.6)
                        .foregroundColor(OpenlyTheme.ink)
                    Text("Identity, appearance and privacy")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OpenlyTheme.muted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 8)

                if session.user == nil {
                    EmptyState(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: "سجّل الدخول",
                        message: "سجّل الدخول لتعديل هويتك وإعداداتك."
                    )
                } else {
                    identityPanel
                    securityPanel
                    displayPanel
                }
            }
            .padding(.bottom, 34)
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .openlyKeyboardDismissal()
        .task(id: session.user?.publicCode) { loadIdentityFromSession() }
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: identityColor) ?? OpenlyTheme.accent)
                        .frame(width: 13, height: 13)
                        .shadow(color: (Color(hex: identityColor) ?? OpenlyTheme.accent).opacity(0.3), radius: 4)

                    Text(publicCode.isEmpty ? (session.user?.publicCode ?? "") : publicCode)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundColor(OpenlyTheme.ink)
                        .environment(\.layoutDirection, .leftToRight)
                }

                Spacer()

                Text("هذه هي الهوية التي يراها الآخرون.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldTitle("كود الهوية")

                HStack(spacing: 10) {
                    Button {
                        publicCode = randomNativeIdentityCode()
                        inlineMessage = nil
                        inlineError = nil
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(OpenlyTheme.ink)
                            .frame(width: 58, height: 56)
                            .background(OpenlyTheme.background)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إنشاء كود عشوائي")

                    OpenlyFieldContainer {
                        TextField("KHA9D", text: $publicCode)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                            .onChange(of: publicCode) { publicCode = normalizedNativeIdentityCode($0) }
                    }
                }

                Text("4–8 رموز واضحة؛ لا نستخدم I أو L أو O أو 0 أو 1 لتجنب الالتباس.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 12) {
                fieldTitle("لون الهوية")

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8),
                    spacing: 12
                ) {
                    ForEach(nativeIdentityPalette, id: \.self) { swatch in
                        let selected = swatch.caseInsensitiveCompare(identityColor) == .orderedSame
                        Button {
                            identityColor = swatch
                            inlineMessage = nil
                            inlineError = nil
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: swatch) ?? OpenlyTheme.accent)
                                    .frame(width: 38, height: 38)

                                if selected {
                                    Circle()
                                        .stroke(OpenlyTheme.ink, lineWidth: 3)
                                        .frame(width: 46, height: 46)
                                    Circle()
                                        .stroke(OpenlyTheme.background, lineWidth: 2)
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("لون الهوية \(swatch)")
                        .accessibilityValue(selected ? "محدد" : "")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldTitle("الحالة")
                OpenlyFieldContainer {
                    TextField("جملة قصيرة — اختياري", text: $status)
                        .foregroundColor(OpenlyTheme.ink)
                        .onChange(of: status) { status = String($0.prefix(60)) }
                }
                characterCount(status.count, maximum: 60)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldTitle("النبذة")
                TextEditor(text: $bio)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(OpenlyTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .frame(minHeight: 128)
                    .background(OpenlyTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(OpenlyTheme.lineStrong, lineWidth: 1.2)
                    )
                    .overlay(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("اكتب شيئًا مختصرًا عن هذه الهوية — اختياري")
                                .font(.system(size: 16))
                                .foregroundColor(OpenlyTheme.subtle)
                                .padding(.horizontal, 19)
                                .padding(.vertical, 22)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: bio) { bio = String($0.prefix(240)) }

                characterCount(bio.count, maximum: 240)
            }

            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OpenlyTheme.danger)
            }

            if let inlineMessage {
                Label(inlineMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OpenlyTheme.accent)
            }

            Button {
                Task { await saveIdentity() }
            } label: {
                if isSaving {
                    ProgressView().tint(OpenlyTheme.accentForeground)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "square.and.arrow.down")
                        Text("حفظ الهوية")
                    }
                }
            }
            .buttonStyle(OpenlyPrimaryButtonStyle())
            .disabled(isSaving || publicCode.count < 4)
            .opacity(publicCode.count < 4 ? 0.55 : 1)
        }
        .padding(20)
        .websiteSettingsPanel
        .padding(.horizontal, 24)
    }

    private var securityPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            fieldTitle("الأمان")

            Text("يتطلب التغيير كلمة المرور الحالية، أو رابط استعادة موثّقًا عبر البريد.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .lineSpacing(4)

            NavigationLink(destination: ForgotPasswordView()) {
                HStack(spacing: 9) {
                    Image(systemName: "key")
                    Text("تغيير كلمة المرور")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(OpenlyTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(OpenlyTheme.background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1.2))
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
        .padding(20)
        .websiteSettingsPanel
        .padding(.horizontal, 18)
    }

    private var displayPanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text("اللغة")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(OpenlyTheme.ink)

                Text("اختر لغة واجهة Openly.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineSpacing(4)

                HStack(spacing: 10) {
                    languageButton(.arabic)
                    languageButton(.english)
                }
            }

            Rectangle()
                .fill(OpenlyTheme.line)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                fieldTitle("المظهر")

                Text("كيف يظهر التطبيق على هذا الجهاز.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)

                VStack(spacing: 10) {
                    appearanceButton(.system)
                    appearanceButton(.light)
                    appearanceButton(.dark)
                }

                Text("لون التمييز")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OpenlyTheme.muted)
                    .padding(.top, 8)

                HStack(spacing: 13) {
                    ForEach(OpenlyColorTheme.allCases) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                colorThemeRaw = theme.rawValue
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.swatch)
                                    .frame(width: 39, height: 39)

                                if colorThemeRaw == theme.rawValue {
                                    Circle()
                                        .stroke(OpenlyTheme.ink, lineWidth: 3)
                                        .frame(width: 47, height: 47)
                                    Circle()
                                        .stroke(OpenlyTheme.background, lineWidth: 2)
                                        .frame(width: 41, height: 41)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.title)
                        .accessibilityValue(colorThemeRaw == theme.rawValue ? "محدد" : "")
                    }
                }
            }
        }
        .padding(20)
        .websiteSettingsPanel
        .padding(.horizontal, 18)
    }

    private func fieldTitle(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(OpenlyTheme.ink)
    }

    private func characterCount(_ count: Int, maximum: Int) -> some View {
        Text("\(count) / \(maximum)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(OpenlyTheme.subtle)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func languageButton(_ language: OpenlyLanguage) -> some View {
        let active = languageRaw == language.rawValue
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                languageRaw = language.rawValue
            }
        } label: {
            Text(language.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(active ? OpenlyTheme.accentForeground : OpenlyTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(active ? OpenlyTheme.accent : OpenlyTheme.background)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(active ? OpenlyTheme.accentStrong : OpenlyTheme.lineStrong, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
    }

    private func appearanceButton(_ appearance: OpenlyAppearance) -> some View {
        let active = appearanceRaw == appearance.rawValue
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                appearanceRaw = appearance.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: appearance.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(OpenlyTheme.accent)
                    }
                }

                Spacer(minLength: 0)

                Text(appearance.title)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(
                appearance == .dark
                    ? Color.white
                    : OpenlyTheme.ink
            )
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                Group {
                    switch appearance {
                    case .system:
                        LinearGradient(
                            colors: [
                                Color(red: 247/255, green: 244/255, blue: 238/255),
                                Color(red: 23/255, green: 21/255, blue: 19/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    case .light:
                        Color(red: 1, green: 253/255, blue: 248/255)
                    case .dark:
                        Color(red: 23/255, green: 23/255, blue: 25/255)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(active ? OpenlyTheme.accent : OpenlyTheme.line, lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadIdentityFromSession() {
        guard let user = session.user else { return }
        publicCode = user.publicCode
        identityColor = user.identityColor
        status = user.status ?? ""
        bio = user.bio ?? ""
        inlineMessage = nil
        inlineError = nil
    }

    @MainActor
    private func saveIdentity() async {
        guard !isSaving else { return }
        guard publicCode.count >= 4 else {
            inlineError = "الكود يجب أن يكون من 4 إلى 8 رموز."
            return
        }

        isSaving = true
        inlineMessage = nil
        inlineError = nil
        do {
            try await session.updateProfile(
                publicCode: publicCode,
                identityColor: identityColor,
                status: status,
                bio: bio
            )
            loadIdentityFromSession()
            inlineMessage = "تم حفظ التغييرات."
        } catch {
            inlineError = error.localizedDescription
        }
        isSaving = false
    }
}

private extension View {
    var websiteSettingsPanel: some View {
        self
            .background(OpenlyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(OpenlyTheme.line, lineWidth: 1)
            )
    }
}
