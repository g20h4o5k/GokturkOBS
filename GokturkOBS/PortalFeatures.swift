import SwiftUI
import Foundation

struct PortalRecord: Identifiable {
    let values: [String: JSONValue]
    let fallbackID: String

    var id: String {
        string("id", "mailId", "userId", "sinavKod") ?? fallbackID
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            guard let value = values[key] else { continue }
            switch value {
            case .string(let text) where !text.isEmpty: return text
            case .number(let number): return number.formatted(.number.grouping(.never))
            case .bool(let flag): return flag ? "Evet" : "Hayır"
            default: continue
            }
        }
        return nil
    }
}

struct AttendanceSnapshot {
    let periodDescription: String
    let records: [PortalRecord]
}

extension OBSClient {
    func loadInbox() async throws -> [PortalRecord] {
        try await webJSON(path: "obsapi/mail/getInbox", method: "GET").records(at: ["data", "mail"])
    }

    func loadSentMail() async throws -> [PortalRecord] {
        try await webJSON(path: "obsapi/mail/getSentMail", method: "GET").records(at: ["data", "mail"])
    }

    func loadMailContent(id: String) async throws -> PortalRecord {
        let json = try await webJSON(path: "obsapi/mail/getMailContent", fields: [("mailId", id)])
        guard let record = json.record(at: ["data", "mailContent"]) else {
            throw OBSClientError.invalidResponse("Mesaj içeriği okunamadı.")
        }
        return record
    }

    func searchReceivers(_ query: String) async throws -> [PortalRecord] {
        var components = URLComponents(url: baseURL.appendingPathComponent("obsapi/mail/getReceiverList"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw OBSClientError.invalidResponse("Alıcı arama adresi oluşturulamadı.") }
        return try await webJSON(url: url, method: "GET").records(at: ["data"])
    }

    func sendMessage(title: String, content: String, receiver: PortalRecord, replyID: String = "") async throws -> String {
        guard let type = receiver.string("userType", "type"),
              let id = receiver.string("userId", "id") else {
            throw OBSClientError.invalidResponse("Alıcının sistem kimliği bulunamadı.")
        }
        let receiverJSON = try JSONSerialization.data(withJSONObject: [["type": type, "id": id]])
        guard let receivers = String(data: receiverJSON, encoding: .utf8) else {
            throw OBSClientError.invalidResponse("Alıcı bilgisi hazırlanamadı.")
        }
        let json = try await webJSON(path: "obsapi/mail/sendMail", fields: [
            ("title", title), ("content", content), ("receivers", receivers),
            ("canReply", "true"), ("shouldReply", replyID.isEmpty ? "false" : "true"), ("replyId", replyID)
        ])
        guard json["success"]?.boolValue == true else {
            throw OBSClientError.invalidResponse(json["msg"]?.stringValue ?? "Mesaj gönderilemedi.")
        }
        return json["msg"]?.stringValue ?? "Mesaj gönderildi."
    }

    func loadAttendance() async throws -> AttendanceSnapshot {
        let initial = try await webJSON(path: "pages/student/require/attendanceDashboard.php", fields: [("request", "load-attendance-initial-data")])
        let periods = initial.records(at: ["periods"])
        let periodDescription = periods.first?.string("description") ?? "Aktif Dönem"
        guard let periodID = periods.first?.string("id") else {
            return AttendanceSnapshot(periodDescription: periodDescription, records: [])
        }
        let records = try await webJSON(path: "pages/student/require/attendanceDashboard.php", fields: [
            ("request", "get-attendance-graph-7"), ("periodId", periodID)
        ]).records(at: ["list"])
        return AttendanceSnapshot(periodDescription: periodDescription, records: records)
    }

    func loadTeachers() async throws -> [PortalRecord] {
        try await webJSON(path: "pages/student/require/teacherAction.php", fields: [
            ("request", "loadMyOwnTeachers")
        ]).records(at: ["data"])
    }

    func loadAnnouncements() async throws -> [PortalRecord] {
        try await loadIndexRecords(key: "announcementList")
    }

    func loadEvents() async throws -> [PortalRecord] {
        try await loadIndexRecords(key: "eventList")
    }

    private func loadIndexRecords(key: String) async throws -> [PortalRecord] {
        try await webJSON(path: "pages/student/require/indexAction.php", fields: [
            ("request", "loadIndex")
        ]).records(at: ["data", key])
    }

    private func webJSON(path: String, method: String = "POST", fields: [(String, String)] = []) async throws -> [String: JSONValue] {
        try await webJSON(url: baseURL.appendingPathComponent(path), method: method, fields: fields)
    }

    private func webJSON(url: URL, method: String = "POST", fields: [(String, String)] = []) async throws -> [String: JSONValue] {
        try await performRead(for: .web) { [self] in
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            if method == "POST" {
                var components = URLComponents()
                components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
                request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
            guard let cookies = currentCookieHeader, !cookies.isEmpty else { throw OBSClientError.sessionExpired }
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OBSClientError.serverError }
            try validateHTTPResponse(http)
            let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
            if object["success"]?.boolValue == false {
                throw OBSClientError.invalidResponse(object["msg"]?.stringValue ?? object["message"]?.stringValue ?? "Sunucu isteği reddetti.")
            }
            return object
        }
    }
}

private extension JSONValue {
    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return ["true", "1", "success"].contains(value.lowercased())
        default: return nil
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func value(at path: [String]) -> JSONValue? {
        var current: JSONValue = .object(self)
        for key in path {
            guard case .object(let dictionary) = current, let next = dictionary[key] else { return nil }
            current = next
        }
        return current
    }

    func records(at path: [String]) -> [PortalRecord] {
        guard case .array(let items) = value(at: path) else { return [] }
        return items.enumerated().compactMap { index, value in
            guard case .object(let object) = value else { return nil }
            return PortalRecord(values: object, fallbackID: "\(path.joined(separator: "."))-\(index)")
        }
    }

    func record(at path: [String]) -> PortalRecord? {
        guard case .object(let object) = value(at: path) else { return nil }
        return PortalRecord(values: object, fallbackID: path.joined(separator: "."))
    }
}

private struct PortalListScreen: View {
    let title: String
    let systemImage: String
    let loader: () async throws -> [PortalRecord]
    let primaryKeys: [String]
    let secondaryKeys: [String]
    let detailKeys: [String]
    @State private var records: [PortalRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var search = ""

    private var filtered: [PortalRecord] {
        guard !search.isEmpty else { return records }
        return records.filter { record in
            (primaryKeys + secondaryKeys).contains { record.string($0)?.localizedCaseInsensitiveContains(search) == true }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && records.isEmpty {
                    ProgressView("\(title) yükleniyor…")
                } else if let errorMessage, records.isEmpty {
                    ContentUnavailableView {
                        Label("\(title) yüklenemedi", systemImage: "exclamationmark.triangle")
                    } description: { Text(errorMessage) } actions: { Button("Tekrar Dene") { Task { await load() } } }
                } else if records.isEmpty {
                    ContentUnavailableView("Kayıt bulunamadı", systemImage: systemImage)
                } else {
                    List(filtered) { record in
                        NavigationLink {
                            PortalRecordDetail(record: record, keys: detailKeys, title: record.string(primaryKeys.first ?? "") ?? title)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(primaryKeys.compactMap { record.string($0) }.first ?? "—").font(.headline)
                                if let secondary = secondaryKeys.compactMap({ record.string($0) }).first {
                                    Text(secondary).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }.searchable(text: $search, prompt: "Ara")
                }
            }
            .navigationTitle(title)
            .toolbar { Button { Task { await load() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }.disabled(isLoading) }
            .task { if records.isEmpty { await load() } }
        }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { records = try await loader() } catch { errorMessage = error.localizedDescription }
    }
}

private struct PortalRecordDetail: View {
    let record: PortalRecord
    let keys: [String]
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(keys, id: \.self) { key in
                    if let value = record.string(key) {
                        LabeledContent(label(for: key), value: value)
                    }
                }
            }.padding().frame(maxWidth: 760, alignment: .leading)
        }.navigationTitle(title)
    }

    private func label(for key: String) -> String {
        ["sender": "Gönderen", "recipient": "Alıcı", "sendDate": "Tarih", "date": "Tarih",
         "content": "İçerik", "description": "Açıklama", "lesson": "Ders", "teacher": "Öğretmen",
         "note": "Not", "location": "Yer", "subject": "Ders", "nameSurname": "Ad Soyad",
         "teaNameSurname": "Öğretmen"][key] ?? key
    }
}

struct AttendanceView: View {
    let client: OBSClient
    @State private var snapshot: AttendanceSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && snapshot == nil {
                    ProgressView("Devamsızlık bilgileri yükleniyor…")
                } else if let errorMessage, snapshot == nil {
                    ContentUnavailableView {
                        Label("Devamsızlık bilgileri yüklenemedi", systemImage: "exclamationmark.triangle")
                    } description: { Text(errorMessage) } actions: { Button("Tekrar Dene") { Task { await load() } } }
                } else if let snapshot {
                    List {
                        Section("Genel Durum · \(snapshot.periodDescription)") {
                            if snapshot.records.isEmpty {
                                Label("Bu dönem için devamsızlık kaydı bulunmuyor.", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            } else {
                                LabeledContent("Toplam devamsızlık", value: "\(snapshot.records.count) ders saati")
                            }
                        }
                        Section("Yoklama Kayıtları") {
                            if snapshot.records.isEmpty {
                                Text("Kayıtlı devamsızlık yok").foregroundStyle(.secondary)
                            } else {
                                ForEach(snapshot.records) { record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.string("lesson") ?? "Ders")
                                            .font(.headline)
                                        HStack {
                                            if let number = record.string("lessonNo") { Text("\(number). ders saati") }
                                            if let date = record.string("absenceDate") { Text(date) }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        if let teacher = record.string("teaNameSurname") {
                                            Text(teacher).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let description = record.string("description") {
                                            Text(description).font(.caption)
                                        }
                                        if let note = record.string("note"), !note.isEmpty {
                                            Text("Not: \(note)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Devamsızlık")
            .toolbar { Button { Task { await load() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }.disabled(isLoading) }
            .task { if snapshot == nil { await load() } }
        }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { snapshot = try await client.loadAttendance() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct TeachersView: View {
    let client: OBSClient
    var body: some View {
        PortalListScreen(
            title: "Öğretmenlerim",
            systemImage: "person.2",
            loader: client.loadTeachers,
            primaryKeys: ["teaNameSurname", "nameSurname", "teacherName", "name"],
            secondaryKeys: ["lesson", "subject"],
            detailKeys: ["teaNameSurname", "lesson", "subject"]
        )
    }
}

struct AnnouncementsView: View {
    let client: OBSClient
    var body: some View { PortalListScreen(title: "Duyurular", systemImage: "megaphone", loader: client.loadAnnouncements, primaryKeys: ["title", "announcementTitle"], secondaryKeys: ["date", "publisherPersonName", "content"], detailKeys: ["date", "content", "publisherPersonName"]) }
}

struct EventsView: View {
    let client: OBSClient
    var body: some View { PortalListScreen(title: "Etkinlikler", systemImage: "calendar", loader: client.loadEvents, primaryKeys: ["title"], secondaryKeys: ["date", "location"], detailKeys: ["date", "time", "location", "content", "description"]) }
}

struct MessagesView: View {
    let client: OBSClient
    @State private var inbox: [PortalRecord] = []
    @State private var sent: [PortalRecord] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var composing = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && inbox.isEmpty && sent.isEmpty { ProgressView("Mesajlar yükleniyor…") }
                else if let errorMessage, inbox.isEmpty && sent.isEmpty {
                    ContentUnavailableView("Mesajlar yüklenemedi", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    List {
                        Section("Gelen Kutusu") { ForEach(inbox) { MessageRow(record: $0, client: client) } }
                        Section("Gönderilenler") { ForEach(sent) { MessageRow(record: $0, client: client) } }
                    }
                }
            }
            .navigationTitle("Mesajlar")
            .toolbar {
                Button { composing = true } label: { Label("Yeni Mesaj", systemImage: "square.and.pencil") }
                Button { Task { await load() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
            .sheet(isPresented: $composing) { ComposeMessageView(client: client) }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            async let inboxRequest = client.loadInbox()
            async let sentRequest = client.loadSentMail()
            (inbox, sent) = try await (inboxRequest, sentRequest)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct MessageRow: View {
    let record: PortalRecord
    let client: OBSClient

    var body: some View {
        NavigationLink {
            MessageDetailView(summary: record, client: client)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.string("mailTitle", "title") ?? "Başlıksız mesaj").font(.headline)
                if let person = record.string("sender", "recipient") {
                    Text(person).font(.subheadline).foregroundStyle(.secondary)
                }
                if let preview = record.string("mailPreview"), !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let date = record.string("sendDate", "date") {
                    Text(date).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct MessageDetailView: View {
    let summary: PortalRecord
    let client: OBSClient
    @State private var detail: PortalRecord?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var title: String { summary.string("mailTitle", "title") ?? "Mesaj" }

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Mesaj yükleniyor…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, detail == nil {
                ContentUnavailableView {
                    Label("Mesaj yüklenemedi", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Tekrar Dene") { Task { await load() } }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(.title2.weight(.semibold))
                        if let person = summary.string("sender", "recipient") {
                            LabeledContent(summary.string("sender") == nil ? "Alıcı" : "Gönderen", value: person)
                        }
                        if let date = summary.string("sendDate", "date") {
                            LabeledContent("Tarih", value: date)
                        }
                        Divider()
                        Text(fullMessage)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(22)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(title)
        .task(id: summary.id) { await load() }
    }

    private var fullMessage: String {
        detail?.string("mailContent", "content", "message")
            ?? summary.string("mailPreview")
            ?? "Mesaj içeriği bulunamadı."
    }

    @MainActor private func load() async {
        guard !isLoading, detail == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await client.loadMailContent(id: summary.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ComposeMessageView: View {
    let client: OBSClient
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var receivers: [PortalRecord] = []
    @State private var receiver: PortalRecord?
    @State private var title = ""
    @State private var content = ""
    @State private var status: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Alıcı ara", text: $query)
                if receiver == nil {
                    ForEach(receivers.prefix(20)) { candidate in
                        Button(candidate.string("nameSurname", "name") ?? "Alıcı") { receiver = candidate }
                    }
                } else { LabeledContent("Alıcı", value: receiver?.string("nameSurname", "name") ?? "—") }
                TextField("Konu", text: $title)
                TextEditor(text: $content).frame(minHeight: 160)
                if let status { Text(status).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            .navigationTitle("Yeni Mesaj")
            .toolbar {
                Button("Vazgeç") { dismiss() }
                Button("Gönder") { Task { await send() } }
                    .disabled(receiver == nil || title.count < 5 || content.count < 10 || sending)
            }
            .task(id: query) {
                guard query.count >= 2 else { receivers = []; return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    receivers = try await client.searchReceivers(query)
                } catch is CancellationError { } catch { status = error.localizedDescription }
            }
        }.frame(minWidth: 520, minHeight: 460)
    }

    @MainActor private func send() async {
        guard let receiver else { return }
        sending = true; status = nil
        defer { sending = false }
        do { status = try await client.sendMessage(title: title, content: content, receiver: receiver) }
        catch { status = error.localizedDescription }
    }
}
