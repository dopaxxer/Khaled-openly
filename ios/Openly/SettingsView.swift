import SwiftUI

struct SettingsView: View {
    @AppStorage("openly.appearance") private var appearanceRaw = OpenlyAppearance.system.rawValue
    @AppStorage("openly.language") private var languageRaw = OpenlyLanguage.arabic.rawValue
    @AppStorage("openly.colorTheme") private var colorThemeRaw = OpenlyColorTheme.ultramarine.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("الإعدادات", subtitle: "خصص لغة وثيم Openly على هذا الجهاز.")

                languageSection
                    .padding(.bottom, 30)

                themeSection
                    .padding(.bottom, 30)
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الإعدادات")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("اللغة")

            VStack(spacing: 0) {
                ForEach(OpenlyLanguage.allCases) { option in
                    Button {
                        languageRaw = option.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option == .arabic ? "character.book.closed" : "textformat")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundColor(OpenlyTheme.muted)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.ink)
                                Text(option.subtitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(OpenlyTheme.subtle)
                            }

                            Spacer()

                            selectionMark(active: languageRaw == option.rawValue)
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 72)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != OpenlyLanguage.allCases.last {
                        divider
                    }
                }
            }
            .settingsCard

            Text("يتغير اتجاه الواجهة تلقائيًا: العربية من اليمين إلى اليسار والإنجليزية من اليسار إلى اليمين.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OpenlyTheme.subtle)
                .lineSpacing(4)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 18)
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("الثيمات")

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("وضع الإضاءة")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(OpenlyTheme.muted)

                    HStack(spacing: 8) {
                        ForEach(OpenlyAppearance.allCases) { option in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    appearanceRaw = option.rawValue
                                }
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                    Text(option.title)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(
                                    appearanceRaw == option.rawValue
                                        ? OpenlyTheme.accentForeground
                                        : OpenlyTheme.ink
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 66)
                                .background(
                                    appearanceRaw == option.rawValue
                                        ? OpenlyTheme.accent
                                        : OpenlyTheme.surfaceSoft
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            appearanceRaw == option.rawValue
                                                ? OpenlyTheme.accentStrong
                                                : OpenlyTheme.line,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Rectangle()
                    .fill(OpenlyTheme.line)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("لون التمييز")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(OpenlyTheme.muted)
                        Spacer()
                        if let selected = OpenlyColorTheme(rawValue: colorThemeRaw) {
                            Text(selected.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(OpenlyTheme.subtle)
                        }
                    }

                    HStack(spacing: 12) {
                        ForEach(OpenlyColorTheme.allCases) { theme in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    colorThemeRaw = theme.rawValue
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(theme.swatch)
                                        .frame(width: 44, height: 44)

                                    if colorThemeRaw == theme.rawValue {
                                        Circle()
                                            .stroke(Color.white.opacity(0.95), lineWidth: 3)
                                            .frame(width: 34, height: 34)

                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .black))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(theme.title)
                            .accessibilityValue(colorThemeRaw == theme.rawValue ? "محدد" : "")
                        }
                    }

                    Text("نفس ألوان الموقع: أزرق ملكي، عنّابي، غابي، كهرماني، وبنفسجي.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OpenlyTheme.subtle)
                        .lineSpacing(3)
                }

                themePreview
            }
            .padding(18)
            .settingsCard

            Text("يُحفظ الثيم على هذا الجهاز ويُطبّق فورًا على الأزرار، الروابط، التبويبات وحالات التحديد.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OpenlyTheme.subtle)
                .lineSpacing(4)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 18)
    }

    private var themePreview: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(OpenlyTheme.accentSoft)
                    .frame(width: 42, height: 42)
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(OpenlyTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("معاينة")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(OpenlyTheme.ink)
                Text("سيظهر لون التمييز بهذا الشكل داخل التطبيق.")
                    .font(.system(size: 12))
                    .foregroundColor(OpenlyTheme.subtle)
            }

            Spacer()

            Text("زر")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(OpenlyTheme.accentForeground)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(OpenlyTheme.accent)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(OpenlyTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(OpenlyTheme.ink)
            .padding(.horizontal, 2)
    }

    private func selectionMark(active: Bool) -> some View {
        Image(systemName: active ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(active ? OpenlyTheme.accent : OpenlyTheme.subtle)
    }

    private var divider: some View {
        Rectangle()
            .fill(OpenlyTheme.line)
            .frame(height: 1)
            .padding(.leading, 64)
    }
}

private extension View {
    var settingsCard: some View {
        self
            .background(OpenlyTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
            )
    }
}
