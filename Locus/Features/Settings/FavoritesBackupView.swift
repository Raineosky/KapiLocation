import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct AddFavoriteView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名稱，例如：三峽", text: $name)
                TextField("緯度 -90～90", text: $latitude).keyboardType(.numbersAndPunctuation)
                TextField("經度 -180～180", text: $longitude).keyboardType(.numbersAndPunctuation)
                Button("帶入目前地圖標記") {
                    if let point = session.pin ?? session.simulated {
                        latitude = String(point.latitude)
                        longitude = String(point.longitude)
                    } else { error = "請先在地圖放置標記。" }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("儲存到最愛") {
                    guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                          let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                          lat.isFinite, lon.isFinite,
                          (-90...90).contains(lat), (-180...180).contains(lon) else {
                        error = "座標格式錯誤，請使用十進位經緯度。"
                        return
                    }
                    session.addFavorite(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    dismiss()
                }
            }
            .navigationTitle("新增最愛座標")
            .toolbar { Button("取消") { dismiss() } }
        }
    }
}

struct FavoritesBackup: Codable {
    var schemaVersion: Int = 1
    var places: [SavedPlace]

    static func decode(_ data: Data) throws -> FavoritesBackup {
        guard data.count <= 5_000_000 else { throw BackupError.invalid }
        let backup = try JSONDecoder().decode(Self.self, from: data)
        guard backup.schemaVersion == 1, backup.places.count <= 10_000,
              backup.places.allSatisfy({
                  $0.name.count <= 500 && $0.latitude.isFinite && $0.longitude.isFinite &&
                  (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
              }) else { throw BackupError.invalid }
        return backup
    }
    enum BackupError: LocalizedError {
        case invalid
        var errorDescription: String? { "備份版本、檔案大小或座標內容不正確，未匯入任何資料。" }
    }
}

struct FavoritesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var backup: FavoritesBackup
    init(places: [SavedPlace]) { backup = FavoritesBackup(places: places) }
    init(configuration: ReadConfiguration) throws {
        backup = try FavoritesBackup.decode(configuration.file.regularFileContents ?? Data())
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}

struct FavoritesBackupView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var document = FavoritesDocument(places: [])
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("座標備份") {
                    Button("匯出所有最愛（JSON）") {
                        document = FavoritesDocument(places: session.favorites)
                        exporting = true
                    }
                    Button("匯入備份並合併") { importing = true }
                    Text("相同座標會跳過並保留現有名稱，不刪除原有收藏。備份只包含名稱與座標，不含配對金鑰。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Text(message) }
            }
            .navigationTitle("收藏備份")
            .toolbar { Button("完成") { dismiss() } }
            .fileExporter(isPresented: $exporting, document: document,
                          contentType: .json, defaultFilename: "KapiLocation-Favorites") { result in
                switch result {
                case .success: message = "匯出完成。"
                case .failure(let error): message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 5_000_000 else { throw FavoritesBackup.BackupError.invalid }
                    let backup = try FavoritesBackup.decode(Data(contentsOf: url))
                    var known = Set(session.favorites.map(\.id))
                    var added = 0
                    for place in backup.places.reversed() where !known.contains(place.id) {
                        session.addFavorite(name: place.name, coordinate: place.coordinate)
                        known.insert(place.id)
                        added += 1
                    }
                    message = "已新增 \(added) 筆收藏；重複座標已略過。"
                } catch { message = error.localizedDescription }
            }
        }
    }
}
