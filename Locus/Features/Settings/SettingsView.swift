import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                SpeedControlsSection()
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "已匯入 RPPairing 配對檔" : "尚未匯入配對檔")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("在這支 iPhone 上配對", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("匯入 RPPairing 配對檔…") { showImporter = true }
                    Button("從剪貼簿貼上 RPPairing") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("移除配對檔", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("開發者配對")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "iOS 27 可在本機配對：到「設定 › 隱私權與安全性 › 開發者模式 › 與主機配對」輸入六位數代碼。iOS 18～26 請使用 idevice_pair 匯入 RPPairing 檔；LiveContainer 若無法選檔，請開啟「修正檔案選擇器」或使用貼上／分享功能。"
                         : "請使用 idevice_pair 產生 RPPairing 配對檔，SideStore 的 .mobiledevicepairing 不適用。若在 LiveContainer 無法選檔，請啟用「修正檔案選擇器」，或透過分享／貼上匯入。")
                }

                Section {
                    TextField("裝置通道 IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("狀態") {
                        Text(LocalDevVPN.isConnected ? "已連線" : "尚未連線")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("儲存通道 IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "開啟 LocalDevVPN" : "前往 App Store 下載 LocalDevVPN",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("連線通道")
                } footer: {
                    Text("瞬移前請連接 LocalDevVPN，預設通道 IP 為 10.7.0.1。第一次請在 Wi-Fi 下啟動定位，之後可繼續使用行動網路。")
                }

                Section("隱私") {
                    Text("收藏與速度設定儲存在本機，未加入分析追蹤或自有伺服器。地圖、地點搜尋及路線規劃會使用 Apple 地圖服務；使用者自行匯出的備份可能經所選分享服務傳送。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("關於") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("定位引擎", value: "idevice DVT 定位模擬")
                    Text("卡皮定位 0.2.0，基於 Locus（MIT）客製。保留原作者授權；定位引擎使用 idevice FFI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("Locus 原意為「所在之處」。")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""
    @State private var showNewFavorite = false
    @State private var showBackup = false
    @State private var searchText = ""
    private var filteredFavorites: [SavedPlace] {
        session.favorites.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) ||
            "\($0.latitude),\($0.longitude)".contains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("最愛座標") {
                    if session.favorites.isEmpty {
                        Text("點選地圖上的星號可收藏座標。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredFavorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label("刪除", systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label("重新命名", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                    .onMove { offsets, destination in
                        if searchText.isEmpty { session.moveFavorites(from: offsets, to: destination) }
                    }
                    .moveDisabled(!searchText.isEmpty)
                }

                Section("最近使用") {
                    if session.recents.isEmpty {
                        Text("最近瞬移的座標會顯示在這裡。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("刪除", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle("收藏座標")
            .searchable(text: $searchText, prompt: "搜尋最愛名稱或座標")
            .sheet(isPresented: $showNewFavorite) { AddFavoriteView() }
            .sheet(isPresented: $showBackup) { FavoritesBackupView() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("新增座標", systemImage: "plus") { showNewFavorite = true }
                        Button("匯入／匯出備份", systemImage: "square.and.arrow.up") { showBackup = true }
                    } label: { Image(systemName: "plus.circle") }
                }
                ToolbarItem(placement: .bottomBar) { EditButton() }
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重新命名最愛座標", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("名稱", text: $renameText)
                Button("取消", role: .cancel) {
                    placeToRename = nil
                }
                Button("儲存") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("請輸入方便辨識的名稱。")
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
