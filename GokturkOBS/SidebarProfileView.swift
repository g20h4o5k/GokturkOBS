import SwiftUI
import AppKit

struct AppSidebarView: View {
    @Binding var selection: AppSection?
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
                    Label("Sınavlar", systemImage: "pencil")
                        .tag(AppSection.exams)
                    Label("Ödevler", systemImage: "book")
                        .tag(AppSection.homework)
                    Label("Yemek Listesi", systemImage: "fork.knife")
                        .tag(AppSection.foodList)
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

    var body: some View {
        VStack(spacing: 18) {
            ProfileAvatarView(name: profile.name, image: image, size: 112)

            Text(profile.name.capitalized(with: Locale(identifier: "tr_TR")))
                .font(.title.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Sınıf Kodu", value: profile.classId)
                LabeledContent("Öğrenci Numarası", value: profile.stuNo)
            }
            .frame(maxWidth: 360)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
