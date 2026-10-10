import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
    var title: String {
        switch self {
        case .system: "Otomatik"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppSidebarView: View {
    @Binding var selection: AppSection?
    @State private var examsExpanded = true
    let profile: StudentProfile?
    let profileImage: NSImage?
    let isLoadingProfile: Bool
    let selectProfile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    Label("Ana Sayfa", systemImage: "house")
                        .tag(AppSection.home)
                    Label("Ders Programı", systemImage: "calendar")
                        .tag(AppSection.schedule)
                    DisclosureGroup(isExpanded: $examsExpanded) {
                        Label("Deneme Sınavı", systemImage: "doc.text")
                            .tag(AppSection.practiceExams)
                        Label("Taramalar", systemImage: "checklist")
                            .tag(AppSection.taramalar)
                    } label: {
                        Label("Sınavlar", systemImage: "graduationcap")
                    }
                    .accessibilityHint(examsExpanded ? "Alt menüyü daraltır" : "Alt menüyü genişletir")
                    Label("Ödevler", systemImage: "book")
                        .tag(AppSection.homework)
                    Label("Yemek Listesi", systemImage: "fork.knife")
                        .tag(AppSection.foodList)
                    Label("Mesajlar", systemImage: "envelope")
                        .tag(AppSection.messages)
                    Label("Devamsızlık", systemImage: "calendar.badge.exclamationmark")
                        .tag(AppSection.attendance)
                    Label("Öğretmenlerim", systemImage: "person.2")
                        .tag(AppSection.teachers)
                    Label("Duyurular", systemImage: "megaphone")
                        .tag(AppSection.announcements)
                    Label("Etkinlikler", systemImage: "calendar.day.timeline.left")
                        .tag(AppSection.events)
                }
            }

            Divider()

            SidebarProfileView(
                name: profile?.name,
                image: profileImage,
                isLoading: isLoadingProfile,
                action: selectProfile
            )
        }
    }
}

private struct SidebarProfileView: View {
    let name: String?
    let image: NSImage?
    let isLoading: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ProfileAvatarView(name: name, image: image, size: 30)

                Text(displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHovering ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
        .padding(6)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(displayName)
        .accessibilityHint("Profil bilgilerini gösterir")
    }

    private var displayName: String {
        guard let name, !name.isEmpty else {
            return "Kullanıcı"
        }
        return name.capitalized(with: Locale(identifier: "tr_TR"))
    }
}

struct ProfileDetailView: View {
    let profile: StudentProfile?
    let image: NSImage?

    var body: some View {
        if let profile {
            ProfileDetailContent(profile: profile, image: image)
                .navigationTitle("Profil")
        } else {
            ContentUnavailableView(
                "Profil bilgisi alınamadı",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Diğer özellikleri kullanmaya devam edebilirsiniz.")
            )
            .navigationTitle("Profil")
        }
    }
}

private struct ProfileDetailContent: View {
    let profile: StudentProfile
    let image: NSImage?
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FullProfileImage(name: profile.name, image: image)

            Text(profile.name.capitalized(with: Locale(identifier: "tr_TR")))
                .font(.title.bold())
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Sınıf Kodu", value: profile.classId)
                    LabeledContent("Öğrenci Numarası", value: profile.stuNo)
                    if let parentName = profile.parentName, !parentName.isEmpty {
                        LabeledContent("Veli Adı Soyadı", value: parentName)
                    }
                }
                .frame(maxWidth: 420)

                Divider().frame(maxWidth: 420)

                Picker("Uygulama Teması", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct FullProfileImage: View {
    let name: String
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 320)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("\(name) profil fotoğrafı")
        } else {
            ProfileAvatarView(name: name, image: nil, size: 112)
        }
    }
}

private struct ProfileAvatarView: View {
    let name: String?
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .fill(.quaternary)

                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.24)
                        .foregroundStyle(.secondary)
                } else {
                    Text(initials)
                        .font(size > 50 ? .title.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    private var initials: String {
        guard let name else {
            return ""
        }
        return name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased(with: Locale(identifier: "tr_TR"))
    }
}
