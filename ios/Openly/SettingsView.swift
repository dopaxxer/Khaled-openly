import SwiftUI

struct SettingsView: View {
    @AppStorage("openly.appearance") private var appearanceRaw = OpenlyAppearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("الإعدادات", subtitle: "خصص مظهر Openly بالطريقة التي تفضلها.")

                Text("المظهر")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(OpenlyTheme.ink)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    ForEach(OpenlyAppearance.allCases) { option in
                        Button {
                            appearanceRaw = option.rawValue
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: option.icon)
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

                                Image(systemName: appearanceRaw == option.rawValue ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(appearanceRaw == option.rawValue ? OpenlyTheme.accent : OpenlyTheme.subtle)
                            }
                            .padding(.horizontal, 20)
                            .frame(minHeight: 72)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option != OpenlyAppearance.allCases.last {
                            Rectangle()
                                .fill(OpenlyTheme.line)
                                .frame(height: 1)
                                .padding(.leading, 64)
                        }
                    }
                }
                .background(OpenlyTheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                )
                .padding(.horizontal, 18)

                Text("يتم حفظ اختيار المظهر على هذا الجهاز ويُطبق فورًا على جميع شاشات التطبيق.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineSpacing(4)
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
            }
            .padding(.bottom, 30)
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الإعدادات")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}