import SwiftUI
import NetworkExtension
import MapKit

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var showSettings = false
    @State private var showPlaces = false

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView()

            BottomControlsView(
                showSettings: $showSettings,
                showPlaces: $showPlaces
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPlaces) {
            PlacesView()
        }
        .alert("卡皮定位", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("確定", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var tunnelConnected = LocalDevVPN.isConnected

    private enum Display {
        case notSpoofing
        case connectVPN
        case status(String)
    }

    private var display: Display {
        switch session.status {
        case .idle:
            return tunnelConnected ? .notSpoofing : .connectVPN
        case .connecting:
            return .status("正在連線…")
        case .active:
            return .status("模擬定位中")
        case .reconnecting:
            return .status("正在重新連線…")
        case .dropped(let reason):
            return .status(reason.isEmpty ? "已中斷連線" : "連線中斷：\(reason)")
        }
    }

    private var color: Color {
        switch display {
        case .notSpoofing:
            return Color.primary.opacity(0.55)
        case .connectVPN:
            return LocusTheme.statusWarn
        case .status:
            switch session.status {
            case .active: return LocusTheme.statusGood
            case .connecting, .reconnecting: return LocusTheme.statusWarn
            case .dropped: return LocusTheme.statusBad
            case .idle: return Color.primary.opacity(0.55)
            }
        }
    }

    private var title: String {
        switch display {
        case .notSpoofing: return "尚未模擬定位"
        case .connectVPN: return "連接 LocalDevVPN"
        case .status(let text): return text
        }
    }

    var body: some View {
        Group {
            if case .connectVPN = display {
                Button(action: LocalDevVPN.openOrInstall) {
                    statusContent
                }
                .buttonStyle(.plain)
            } else {
                statusContent
            }
        }
        .onAppear { refreshTunnel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTunnel() }
        }
        .onChange(of: session.status) { _, _ in
            refreshTunnel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            // LocalDevVPN connection changes show up here even though we don’t own the VPN.
            refreshTunnel()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refreshTunnel()
            }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if case .connectVPN = display {
                Image(systemName: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LocusTheme.accent)
            } else if case .active = session.status, let sim = session.simulated {
                Text(String(format: "%.4f, %.4f", sim.latitude, sim.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func refreshTunnel() {
        tunnelConnected = LocalDevVPN.isConnected
    }
}

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool
    @State private var showSpeed = false

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 12) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 8) {
                ForEach(TravelMode.allCases) { mode in
                    let selected = session.travelMode == mode
                    Button {
                        session.travelMode = mode
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selected ? .black : .primary)
                            .frame(width: 44, height: 40)
                            .background(
                                Capsule().fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                // 建立起點到終點的路線（只預覽、不出發）
                Button {
                    previewRoute()
                } label: {
                    Group {
                        if session.isBusy && !session.isFollowingRoute {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "road.lanes")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 40)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy || session.isFollowingRoute)
                .accessibilityLabel("建立起點到終點的路線")
                Spacer(minLength: 0)
                Button { showSpeed = true } label: {
                    Text(session.speedLabel)
                        .font(.caption.monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .accessibilityLabel("調整移動速度")
            }

            HStack(spacing: 10) {
                trayIcon("gearshape.fill") { showSettings = true }
                trayIcon("star.fill") { showPlaces = true }

                Button {
                    if session.joystickActive {
                        session.stopJoystick()
                    } else {
                        session.startJoystick(pairing: pairing)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                        Text(session.joystickActive ? "搖桿中" : "搖桿")
                            .lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.joystickActive ? .black : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(session.joystickActive ? LocusTheme.accentSecondary : Color.primary.opacity(0.08))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                if session.isSpoofing {
                    Button {
                        session.stop(pairing: pairing)
                    } label: {
                        Text("停止")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 72)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(LocusTheme.danger))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        guard let pin = session.pin else {
                            session.lastError = "請先點選地圖放置圖釘。"
                            return
                        }
                        session.teleport(to: pin, pairing: pairing)
                    } label: {
                        Text("瞬移")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(minWidth: 96)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(LocusTheme.accent))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                }
            }
            Button {
                startFlowerRoute()
            } label: {
                Label(session.isFollowingRoute ? "種花中" : "開始種花", systemImage: "figure.walk")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(LocusTheme.accentSecondary))
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy || session.isFollowingRoute)
        }
        .sheet(isPresented: $showSpeed) {
            NavigationStack {
                Form { SpeedControlsSection() }
                    .navigationTitle("移動速度")
                    .toolbar { Button("完成") { showSpeed = false } }
            }
        }
        .padding(14)
        .locusGlass(.regular, in: trayShape)
        // Whole tray absorbs taps so near-misses don't fall through to the map.
        .contentShape(trayShape)
    }

    private func startFlowerRoute() {
        if session.preparedRoute.count >= 2 {
            session.followRoute(session.preparedRoute, pairing: pairing)
            return
        }
        // No start set → leave from wherever we are now (spoofed or real GPS).
        guard let start = session.routeStart ?? session.currentCoordinate else {
            session.lastError = "抓不到目前位置。請長按地圖設定起點與終點，或先瞬移到某個地點。"
            return
        }
        guard let end = session.routeEnd else {
            session.lastError = "請長按地圖，選「從目前位置走到這裡」或「設為終點」。"
            return
        }
        session.isBusy = true
        Task {
            do {
                let path = try await RouteBuilder.roadRoute(from: start, to: end,
                                                            mode: session.travelMode)
                session.preparedRoute = path
                session.isBusy = false
                session.followRoute(path, pairing: pairing)
            } catch {
                session.isBusy = false
                session.lastError = "無法建立路線：\(error.localizedDescription)"
            }
        }
    }

    /// Builds the road route and draws it on the map without starting to move.
    private func previewRoute() {
        guard let start = session.routeStart ?? session.currentCoordinate else {
            session.lastError = "抓不到目前位置。請長按地圖設定起點，或先瞬移到某個地點。"
            return
        }
        guard let end = session.routeEnd else {
            session.lastError = "請長按地圖，選「從目前位置走到這裡」或「設為終點」。"
            return
        }
        session.isBusy = true
        Task {
            do {
                let path = try await RouteBuilder.roadRoute(from: start, to: end,
                                                            mode: session.travelMode)
                session.preparedRoute = path
                session.isBusy = false
                NotificationCenter.default.post(name: .kapiFitRoute, object: nil)
            } catch {
                session.isBusy = false
                session.lastError = "無法建立路線：\(error.localizedDescription)"
            }
        }
    }

    private func trayIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
    }
}

extension Notification.Name {
    /// Ask the map to zoom so the whole prepared route is visible.
    static let kapiFitRoute = Notification.Name("kapiFitRoute")
}
