import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: (URL) -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @State private var showGPXImporter = false
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                SpeedControlsSection()
                Section("道路路線") {
                    Button {
                        if let current = session.currentCoordinate {
                            start = current
                            session.preparedRoute = []
                        } else {
                            session.lastError = "目前抓不到位置。請允許定位權限，或先瞬移到某個地點。"
                        }
                    } label: {
                        Label("以目前位置作為起點", systemImage: "figure.walk.departure")
                    }
                    Button("使用目前圖釘作為起點") {
                        start = session.pin
                        session.preparedRoute = []
                    }
                    Button("使用目前圖釘作為終點") {
                        end = session.pin
                        session.preparedRoute = []
                    }
                    LabeledContent("起點") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent("終點") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("建立沿道路行走／開車路線", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section("行走／繪製／GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("使用地圖上繪製的路線", systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label("沿路線行走", systemImage: "play.fill")
                    }
                    Button { showGPXImporter = true } label: {
                        Label("匯入 GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("匯出 GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("路線使用 Apple 地圖服務。自訂速度適用於路線與搖桿；可選擇固定速度或 ±10% 波動。搖桿推動幅度也會影響速度。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("路線")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showGPXImporter,
                          allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { onImportGPX(url) }
                case .failure(let error):
                    session.lastError = "無法選取 GPX：\(error.localizedDescription)"
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
