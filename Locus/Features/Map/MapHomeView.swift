import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = PlaceSearchCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var isRouting = false
    @State private var showRouteSheet = false
    @State private var longPressedCoordinate: CLLocationCoordinate2D?
    @State private var showLongPressMenu = false
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?
    /// Short confirmation shown under the top chrome ("已將目前位置設為起點").
    @State private var toast: String?
    @State private var isResolvingLink = false

    /// Pasted / typed text that is a Google Maps link or a "lat, lng" pair.
    private var linkInput: GoogleMapsLink.Input? {
        GoogleMapsLink.classify(searchText)
    }

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onRemove: {
                                    suppressNextMapTap = true
                                    withAnimation {
                                        session.pin = nil
                                        pinSelected = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    pinSelected = false
                                    isDraggingPin = true
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        session.pin = coord
                                    }
                                },
                                onDragEnded: {
                                    isDraggingPin = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }
                    if let start = session.routeStart {
                        Annotation("起點", coordinate: start) {
                            Label("起點", systemImage: "figure.walk.circle.fill")
                                .font(.caption.bold()).padding(6)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    if let end = session.routeEnd {
                        Annotation("終點", coordinate: end) {
                            Label("終點", systemImage: "flag.checkered.circle.fill")
                                .font(.caption.bold()).padding(6)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    if let sim = session.simulated {
                        Annotation("模擬位置", coordinate: sim) {
                            ZStack {
                                Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                                Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    if session.preparedRoute.count > 1 {
                        MapPolyline(coordinates: session.preparedRoute)
                            .stroke(LocusTheme.accent, lineWidth: 5)
                    }
                    if drawnPath.count > 1 {
                        MapPolyline(coordinates: drawnPath)
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onEnded { value in
                            guard case .second(true, let drag?) = value,
                                  let coord = proxy.convert(drag.location, from: .local),
                                  !isDraggingPin, !drawMode else { return }
                            suppressNextMapTap = true
                            longPressedCoordinate = coord
                            showLongPressMenu = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                suppressNextMapTap = false
                            }
                        }
                )
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
            }
            .background(Color.black.ignoresSafeArea())

            topChrome
        }
        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kapiFitRoute)) { _ in
            fitCamera(to: session.preparedRoute)
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .confirmationDialog("設定路線座標", isPresented: $showLongPressMenu,
                            titleVisibility: .visible) {
            Button("從目前位置走到這裡") { routeFromCurrent() }
            Button("設為起點") { assignLongPress(isStart: true) }
            Button("設為終點") { assignLongPress(isStart: false) }
            Button("取消", role: .cancel) { longPressedCoordinate = nil }
        } message: {
            Text("長按位置可設為路線終點，從目前位置出發；也可分別設定起點、終點")
        }
        .sheet(isPresented: $showRouteSheet) {
            RoutePlannerSheet(
                start: $session.routeStart,
                end: $session.routeEnd,
                isRouting: $isRouting,
                onBuild: buildRoadRoute,
                onPlay: playRoute,
                onImportGPX: importGPX,
                onExportGPX: exportGPX,
                onUseDrawn: {
                    routeCoords = RouteBuilder.sample(coordinates: drawnPath, every: 10)
                    session.preparedRoute = routeCoords
                    drawnPath.removeAll()
                    drawMode = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func assignLongPress(isStart: Bool) {
        guard let coord = longPressedCoordinate else { return }
        if isStart { session.routeStart = coord } else { session.routeEnd = coord }
        session.preparedRoute = []
        routeCoords = []
        longPressedCoordinate = nil
    }

    /// Long-press target becomes the end; the start is wherever the user is now
    /// (spoofed position while spoofing, real GPS otherwise).
    private func routeFromCurrent() {
        guard let coord = longPressedCoordinate else { return }
        longPressedCoordinate = nil
        guard let current = session.currentCoordinate else {
            session.lastError = "目前抓不到位置。請允許卡皮定位使用定位權限，或先瞬移到某個地點。"
            return
        }
        session.routeStart = current
        session.routeEnd = coord
        session.preparedRoute = []
        routeCoords = []
        showToast("起點：目前位置｜終點：長按的位置。按「開始種花」出發")
    }

    private func useCurrentAsStart() {
        guard let current = session.currentCoordinate else {
            session.lastError = "目前抓不到位置。請允許卡皮定位使用定位權限，或先瞬移到某個地點。"
            return
        }
        session.routeStart = current
        session.preparedRoute = []
        routeCoords = []
        showToast(session.routeEnd == nil
                  ? "已將目前位置設為起點。長按地圖設定終點"
                  : "已將目前位置設為起點")
    }

    private func fitCamera(to path: [CLLocationCoordinate2D]) {
        guard path.count > 1 else { return }
        let lats = path.map(\.latitude), lons = path.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // Extra margin so the route isn't hidden under the top bar and bottom tray.
        let span = MKCoordinateSpan(latitudeDelta: max(0.003, (maxLat - minLat) * 1.9),
                                    longitudeDelta: max(0.003, (maxLon - minLon) * 1.5))
        withAnimation(.easeInOut(duration: 0.4)) {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) { toast = text }
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if toast == shown {
                withAnimation(.easeInOut(duration: 0.2)) { toast = nil }
            }
        }
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if drawMode {
            drawnPath.append(coord)
        } else {
            session.pin = coord
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            StatusBarView()

            searchBar

            if !searchText.isEmpty && (linkInput != nil || !search.results.isEmpty) {
                searchResults
            }

            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }

            if let toastText = toast {
                Text(toastText)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .locusGlass(.regular, in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜尋地點或貼上 Google 地圖連結", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                    if let input = linkInput { openLinkInput(input) }
                }
                .onChange(of: searchText) { _, value in
                    search.query = value
                }
            if isResolvingLink {
                ProgressView().controlSize(.small)
            }
            if searchText.isEmpty && !searchFocused {
                // PasteButton reads the clipboard without iOS's "Allow Paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in pasteFromGoogleMaps(text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(LocusTheme.accent)
                .controlSize(.small)
                .accessibilityLabel("貼上 Google 地圖連結")
            }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜尋並收起鍵盤")
            }
            if searchFocused {
                Button("完成") {
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let input = linkInput {
                Button {
                    openLinkInput(input)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .font(.title3)
                            .foregroundStyle(LocusTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(linkRowTitle(input))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("點這裡把圖釘放到這個位置")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isResolvingLink)
                Divider().opacity(0.3)
            }
            ForEach(search.results.prefix(linkInput == nil ? 5 : 3), id: \.self) { item in
                Button {
                    select(completion: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapChromeButtons: some View {
        HStack(spacing: 4) {
            chromeIconButton("square.3.layers.3d") {
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }
            chromeIconButton("point.topleft.down.to.point.bottomright.curvepath") {
                showRouteSheet = true
            }
            chromeIconButton("figure.walk.departure") {
                searchFocused = false
                useCurrentAsStart()
            }
            .accessibilityLabel("以目前位置作為起點")
            chromeIconButton(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle") {
                drawMode.toggle()
                if !drawMode { drawnPath.removeAll() }
            }
            .foregroundStyle(drawMode ? LocusTheme.accentSecondary : .primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
                    if let pin = session.pin {
                        let name = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
                        session.addFavorite(name: name, coordinate: pin)
                    }
                }
            }
        }
        .padding(6)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            goToCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .contentShape(Circle())
        .accessibilityLabel("目前位置")
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func select(completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                let title = item.name ?? completion.title
                await MainActor.run {
                    session.pin = coord
                    pinPlaceName = title
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    session.addFavorite(name: title, coordinate: coord)
                    session.pushNamedRecent(name: title, coordinate: coord)
                }
            }
        }
    }

    // MARK: Google Maps links / coordinates

    private func linkRowTitle(_ input: GoogleMapsLink.Input) -> String {
        switch input {
        case .coordinate(let c):
            return String(format: "前往座標 %.5f, %.5f", c.latitude, c.longitude)
        case .link:
            return isResolvingLink ? "正在讀取 Google 地圖連結…" : "前往 Google 地圖連結的位置"
        }
    }

    private func pasteFromGoogleMaps(_ text: String) {
        guard let input = GoogleMapsLink.classify(text) else {
            searchText = text
            search.query = text
            searchFocused = true
            return
        }
        openLinkInput(input)
    }

    private func openLinkInput(_ input: GoogleMapsLink.Input) {
        switch input {
        case .coordinate(let c):
            dropPin(at: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), name: nil)
        case .link(let url):
            guard !isResolvingLink else { return }
            isResolvingLink = true
            Task {
                defer { isResolvingLink = false }
                do {
                    let resolved = try await GoogleMapsLink.resolve(url)
                    if let c = resolved.coordinate {
                        dropPin(at: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                                name: resolved.placeName)
                    } else if let name = resolved.placeName {
                        // Link only named the place: look it up by name instead.
                        await searchByName(name)
                    } else {
                        session.lastError = "這個 Google 地圖連結讀不到座標。請在 Google 地圖長按該地點，複製畫面上的座標再貼上。"
                    }
                } catch {
                    session.lastError = "無法開啟 Google 地圖連結：\(error.localizedDescription)"
                }
            }
        }
    }

    private func searchByName(_ name: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        if let response = try? await MKLocalSearch(request: request).start(),
           let item = response.mapItems.first {
            dropPin(at: item.placemark.coordinate, name: item.name ?? name)
        } else {
            session.lastError = "找不到「\(name)」的座標。請在 Google 地圖長按該地點，複製座標再貼上。"
        }
    }

    private func dropPin(at coord: CLLocationCoordinate2D, name: String?) {
        guard CLLocationCoordinate2DIsValid(coord) else { return }
        session.pin = coord
        pinPlaceName = name
        pinSelected = false
        position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
        searchText = ""
        search.query = ""
        searchFocused = false
        if let name {
            session.pushNamedRecent(name: name, coordinate: coord)
        }
        showToast(name.map { "已放置圖釘：\($0)" } ?? "已放置圖釘，按「瞬移」前往")
    }

    private func buildRoadRoute() {
        guard let start = session.routeStart ?? session.currentCoordinate ?? session.pin,
              let end = session.routeEnd else {
            session.lastError = "請設定路線的起點和終點。"
            return
        }
        isRouting = true
        Task {
            do {
                let coords = try await RouteBuilder.roadRoute(from: start, to: end, mode: session.travelMode)
                await MainActor.run {
                    routeCoords = coords
                    session.preparedRoute = coords
                    isRouting = false
                }
            } catch {
                await MainActor.run {
                    isRouting = false
                    session.lastError = error.localizedDescription
                }
            }
        }
    }

    private func playRoute() {
        let path = session.preparedRoute.isEmpty ? drawnPath : session.preparedRoute
        guard path.count >= 2 else {
            session.lastError = "請先建立或繪製路線。"
            return
        }
        showRouteSheet = false
        session.preparedRoute = path
        session.followRoute(path, pairing: pairing)
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
            guard coords.count >= 2 else {
                session.lastError = "GPX 路線至少需要兩個座標點。"
                return
            }
            routeCoords = RouteBuilder.sample(coordinates: coords, every: 10)
            session.preparedRoute = routeCoords
            session.routeStart = coords.first
            session.routeEnd = coords.last
            showRouteSheet = false
            if let first = coords.first {
                session.pin = first
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private func exportGPX() {
        let path = session.preparedRoute.isEmpty ? drawnPath : session.preparedRoute
        guard !path.isEmpty else {
            session.lastError = "沒有可匯出的路線。"
            return
        }
        let gpx = GPXCodec.export(path)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Route.gpx")
        do {
            try gpx.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
