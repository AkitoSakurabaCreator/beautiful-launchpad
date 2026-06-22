import SwiftUI
import AppKit
import IOKit.ps

// MARK: - System readers (local, no permissions)

/// Battery percentage + charging state, or nil on a Mac without a battery.
func batteryInfo() -> (percent: Int, charging: Bool)? {
    guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for src in sources {
        guard let desc = IOPSGetPowerSourceDescription(snap, src)?.takeUnretainedValue() as? [String: Any],
              let cap = desc[kIOPSCurrentCapacityKey] as? Int,
              let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
        let pct = Int((Double(cap) / Double(maxCap) * 100).rounded())
        let charging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return (min(max(pct, 0), 100), charging)
    }
    return nil
}

/// Approximate used / total memory in GB (Activity-Monitor-ish: active+wired+compressed).
func memoryUsage() -> (usedGB: Double, totalGB: Double)? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &stats) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    let page = Double(vm_kernel_page_size)
    let total = Double(ProcessInfo.processInfo.physicalMemory)
    let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    return (used / 1_000_000_000, total / 1_000_000_000)
}

/// Human-readable system uptime ("3d 4h", "5h 12m", "8m").
func uptimeString() -> String {
    let s = Int(ProcessInfo.processInfo.systemUptime)
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// MARK: - Per-kind content

/// Renders the content of a widget by kind.
struct WidgetContentView: View {
    @EnvironmentObject var store: LaunchpadStore
    let widget: WidgetItem
    private var cyber: Bool { store.settings.layoutStyle == .cyber }
    private var accent: Color { cyber ? CyberPalette.neon : .white }

    var body: some View {
        switch widget.kind {
        case .clock:   ClockWidgetView(accent: accent)
        case .date:    DateWidgetView(accent: accent)
        case .notes:   NotesWidgetView(widget: widget, accent: accent)
        case .battery: BatteryWidgetView(accent: accent)
        case .system:  SystemWidgetView(accent: accent)
        case .weather: WeatherWidgetView(widget: widget, accent: accent)
        case .image:   ImageWidgetView(path: widget.text)
        case .video:   VideoWidgetView(path: widget.text, muted: widget.muted, volume: widget.volume)
        }
    }
}

private struct ImageWidgetView: View {
    let path: String
    var body: some View {
        if !path.isEmpty, let img = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath) {
            // .fit preserves transparency / shows the whole image (good for PNG logos).
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder(symbol: "photo")
        }
    }
}

private struct VideoWidgetView: View {
    let path: String
    var muted: Bool = true
    var volume: Double = 0.6
    var body: some View {
        if !path.isEmpty, FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) {
            // `.id(path)` swaps the player on file change; mute/volume apply in place.
            VideoBackgroundView(paths: [(path as NSString).expandingTildeInPath], muted: muted, volume: volume)
                .id(path)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholder(symbol: "film")
        }
    }
}

private func placeholder(symbol: String) -> some View {
    Image(systemName: symbol)
        .font(.system(size: 22))
        .foregroundColor(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private struct ClockWidgetView: View {
    let accent: Color
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            VStack(spacing: 2) {
                Text(ctx.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.4).lineLimit(1)
            }
            .foregroundColor(accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DateWidgetView: View {
    let accent: Color
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { ctx in
            VStack(spacing: 2) {
                Text(ctx.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 14, weight: .medium))
                Text(ctx.date, format: .dateTime.month().day())
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4).lineLimit(1)
            }
            .foregroundColor(accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NotesWidgetView: View {
    @EnvironmentObject var store: LaunchpadStore
    let widget: WidgetItem
    let accent: Color
    @State private var text: String = ""
    @State private var loaded = false

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(6)
            .onAppear {
                if !loaded { text = widget.text; loaded = true }
            }
            .onChange(of: text) { newValue in
                store.updateWidgetText(widget.id, newValue)
            }
    }
}

private struct BatteryWidgetView: View {
    let accent: Color
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { _ in
            let info = batteryInfo()
            VStack(spacing: 4) {
                Image(systemName: batterySymbol(info))
                    .font(.system(size: 22))
                if let info {
                    Text("\(info.percent)%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(info.charging ? "Charging" : "Battery")
                        .font(.system(size: 11)).opacity(0.7)
                } else {
                    Text("AC").font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(accent)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func batterySymbol(_ info: (percent: Int, charging: Bool)?) -> String {
        guard let info else { return "powerplug" }
        if info.charging { return "battery.100.bolt" }
        switch info.percent {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<70: return "battery.50"
        case ..<90: return "battery.75"
        default:    return "battery.100"
        }
    }
}

private struct SystemWidgetView: View {
    let accent: Color
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 5)) { _ in
            let mem = memoryUsage()
            VStack(spacing: 4) {
                Image(systemName: "memorychip").font(.system(size: 18))
                if let mem {
                    Text(String(format: "%.1f / %.0f GB", mem.usedGB, mem.totalGB))
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    ProgressView(value: min(mem.usedGB / max(mem.totalGB, 0.001), 1))
                        .tint(accent)
                        .frame(maxWidth: 120)
                }
                Text("up \(uptimeString())").font(.system(size: 11)).opacity(0.7)
            }
            .foregroundColor(accent)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Live current weather via Open-Meteo (no API key), auto-located by IP (no Location
/// permission). Refreshes every 15 minutes; shows "—" offline.
private struct WeatherWidgetView: View {
    let widget: WidgetItem
    let accent: Color
    @State private var temp: Double? = nil
    @State private var code: Int = 0
    @State private var place: String = ""
    @State private var failed = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: weatherSymbol(code)).font(.system(size: 22))
            if let temp {
                Text("\(Int(temp.rounded()))°")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(place.isEmpty ? weatherCondition(code) : place)
                    .font(.system(size: 11)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.6)
            } else if failed {
                Text("—°").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("offline").font(.system(size: 10)).opacity(0.6)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .foregroundColor(accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if !loaded { await load() } }
        .onReceive(Timer.publish(every: 900, on: .main, in: .common).autoconnect()) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        do {
            let loc = try await ipGeolocate()
            let wx = try await fetchWeather(lat: loc.lat, lon: loc.lon)
            await MainActor.run {
                temp = wx.temp; code = wx.code; place = loc.city; failed = false; loaded = true
            }
        } catch {
            await MainActor.run { failed = true; loaded = true }
        }
    }
}

private func ipGeolocate() async throws -> (lat: Double, lon: Double, city: String) {
    let url = URL(string: "https://ipapi.co/json/")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let lat = j?["latitude"] as? Double
    let lon = j?["longitude"] as? Double
    guard let lat, let lon else { throw URLError(.cannotParseResponse) }
    return (lat, lon, (j?["city"] as? String) ?? "")
}

private func fetchWeather(lat: Double, lon: Double) async throws -> (temp: Double, code: Int) {
    let str = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code"
    guard let url = URL(string: str) else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let cur = j?["current"] as? [String: Any]
    guard let temp = cur?["temperature_2m"] as? Double else { throw URLError(.cannotParseResponse) }
    let code = (cur?["weather_code"] as? Int) ?? 0
    return (temp, code)
}

/// WMO weather code → SF Symbol.
private func weatherSymbol(_ code: Int) -> String {
    switch code {
    case 0:        return "sun.max"
    case 1, 2:     return "cloud.sun"
    case 3:        return "cloud"
    case 45, 48:   return "cloud.fog"
    case 51...67:  return "cloud.drizzle"
    case 71...77:  return "cloud.snow"
    case 80...82:  return "cloud.heavyrain"
    case 85, 86:   return "cloud.snow"
    case 95...99:  return "cloud.bolt.rain"
    default:       return "cloud.sun"
    }
}

/// WMO weather code → short label.
private func weatherCondition(_ code: Int) -> String {
    switch code {
    case 0:        return "Clear"
    case 1, 2:     return "Partly cloudy"
    case 3:        return "Cloudy"
    case 45, 48:   return "Fog"
    case 51...67:  return "Rain"
    case 71...77, 85, 86: return "Snow"
    case 80...82:  return "Showers"
    case 95...99:  return "Storm"
    default:       return "—"
    }
}

// MARK: - Draggable / resizable tile + layer

/// All widgets on a page, positioned & sized by their normalized values.
struct WidgetLayer: View {
    @EnvironmentObject var store: LaunchpadStore
    let pageIndex: Int
    let areaSize: CGSize

    /// Named coordinate space (page-local, origin = page top-left) used by the rotation
    /// handle to read the cursor position in the same space as widget centres.
    static let coordinateSpace = "widgetPage"

    var body: some View {
        ForEach(store.widgetsOnPage(pageIndex)) { w in
            WidgetTileView(widget: w, areaSize: areaSize)
        }
    }
}

/// One widget: title-bar drag to move, corner handle to resize, hover ✕ to remove.
struct WidgetTileView: View {
    @EnvironmentObject var store: LaunchpadStore
    let widget: WidgetItem
    let areaSize: CGSize

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var hovering = false

    private var cyber: Bool { store.settings.layoutStyle == .cyber }
    private var glass: Bool { store.settings.layoutStyle == .glass }
    private var baseW: CGFloat { max(60, widget.w * areaSize.width) }
    private var baseH: CGFloat { max(44, widget.h * areaSize.height) }

    // Body split into helpers — a single giant modifier chain made the type-checker
    // crawl (53s clean build); extracting subviews keeps it fast.
    var body: some View {
        let w = max(60, baseW + resizeDelta.width)
        let h = max(44, baseH + resizeDelta.height)
        let cx = widget.x * areaSize.width + dragOffset.width
        let cy = widget.y * areaSize.height + dragOffset.height
        let locked = widget.locked

        let handleZone: CGFloat = 26   // reserved space ABOVE the card for the handle

        // The handle lives in a zone ABOVE the card but still WITHIN the tile frame, so
        // it protrudes outside the card yet stays hit-testable (offsetting it outside the
        // frame rendered it but made it un-grabbable). The card rotates in place; the
        // handle stays upright above it (computing rotation from the absolute cursor
        // angle, so it never jitters).
        VStack(spacing: 0) {
            rotationHandleView(zone: handleZone)
                .opacity(locked ? 0 : 1)
                .allowsHitTesting(!locked)
            card(w, h)
                .rotationEffect(.degrees(widget.rotation))
                .overlay(alignment: .bottomTrailing) { if !locked { resizeHandle } }
                .overlay(alignment: .bottom) { if hovering && !locked && isMedia { controlBar } }
        }
        .frame(width: w, height: h + handleZone)
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        // Frame includes the top handle zone; shift up so the CARD centre (not the
        // frame centre) sits at the widget's stored position.
        .position(x: cx, y: cy - handleZone / 2)
    }

    /// The visible card: title bar + content + frame/background/border/shadow.
    private func card(_ w: CGFloat, _ h: CGFloat) -> some View {
        let transparent = widget.transparent
        let locked = widget.locked
        return VStack(spacing: 0) {
            titleBar
                .opacity(locked ? 0 : (transparent && !hovering ? 0 : 1))
                .allowsHitTesting(!locked)
            WidgetContentView(widget: widget)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .opacity(widget.opacity)
                .contentShape(Rectangle())
                // Grab the body (the media itself) to move it too — except Notes (whose
                // editor needs clicks) and while locked. The hover sliders / resize
                // handle are overlays on top, so they still capture their own drags.
                .gesture(moveGesture, including: (widget.kind == .notes || locked) ? .subviews : .all)
        }
        .frame(width: w, height: h)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: transparent ? .clear : shadowColor,
                radius: transparent ? 0 : (cyber ? 8 : (glass ? 14 : 4)),
                x: 0, y: glass ? 8 : 0)
    }

    private var shadowColor: Color {
        if cyber { return CyberPalette.neon.opacity(0.5) }
        if glass { return GlassPalette.coolEdge.opacity(0.18) }
        return .black.opacity(0.3)
    }

    @ViewBuilder private var cardBackground: some View {
        if !widget.transparent {
            if glass {
                LiquidGlassBackground(
                    shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    tint: GlassPalette.coolEdge,
                    transparency: store.settings.glassTransparency,
                    strokeOpacity: 0.34,
                    shadowOpacity: 0.12
                )
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill((cyber ? CyberPalette.tile : Color.black).opacity(cyber ? 0.6 : 0.4))
            }
        }
    }

    @ViewBuilder private var cardBorder: some View {
        if !widget.transparent {
            RoundedRectangle(cornerRadius: glass ? 16 : 14, style: .continuous)
                .stroke((cyber ? CyberPalette.neon : (glass ? GlassPalette.sheen : Color.white)).opacity(cyber ? 0.85 : (glass ? 0.30 : 0.18)),
                        lineWidth: (cyber || glass) ? 1.5 : 1)
        }
    }

    @ViewBuilder private var menuItems: some View {
        if widget.kind == .image || widget.kind == .video {
            Button(store.t(.chooseFile)) { store.chooseWidgetMedia(widget.id) }
        }
        if widget.kind == .video {
            Button(widget.muted ? store.t(.videoSound) : store.t(.mute)) {
                store.toggleWidgetMuted(widget.id)
            }
        }
        Button(widget.transparent ? store.t(.widgetShowWindow) : store.t(.widgetTransparent)) {
            store.toggleWidgetTransparent(widget.id)
        }
        Button(widget.locked ? store.t(.unlock) : store.t(.lock)) { store.toggleWidgetLocked(widget.id) }
        Divider()
        Button(store.t(.deleteItem), role: .destructive) { store.removeWidget(widget.id) }
    }

    private var titleBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            if hovering {
                Button { store.removeWidget(widget.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 18)
        .contentShape(Rectangle())
        .gesture(moveGesture)
    }

    /// Drag-to-move. Global space so the translation is a screen-space delta (offset-
    /// invariant and unaffected by the tile's rotationEffect) → correct while rotated.
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { v in
                let center = CGPoint(x: widget.x * areaSize.width + v.translation.width,
                                     y: widget.y * areaSize.height + v.translation.height)
                store.moveWidget(widget.id, center: center, container: areaSize)
                dragOffset = .zero
            }
    }

    /// Grab-to-rotate knob near the top of the widget. Rotation is computed from the
    /// angle of the cursor around the widget centre (absolute, not incremental), so it
    /// tracks the pointer smoothly instead of jittering.
    private func rotationHandleView(zone: CGFloat) -> some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black.opacity(0.6)))
            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
            .opacity(hovering ? 1 : 0.45)
            // Small visible knob, but a wide transparent grab zone filling the handle
            // area above the card (it's inside the tile frame, so it stays hit-testable).
            .frame(width: 80, height: zone, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .named(WidgetLayer.coordinateSpace))
                    .onChanged { v in
                        let cx = widget.x * areaSize.width
                        let cy = widget.y * areaSize.height
                        var deg = atan2(v.location.y - cy, v.location.x - cx) * 180 / .pi + 90
                        while deg > 180 { deg -= 360 }
                        while deg < -180 { deg += 360 }
                        store.setWidgetRotation(widget.id, deg)
                    }
            )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(hovering ? 0.85 : (widget.transparent ? 0 : 0.4)))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { resizeDelta = $0.translation }
                    .onEnded { v in
                        store.resizeWidget(widget.id,
                                           size: CGSize(width: baseW + v.translation.width,
                                                        height: baseH + v.translation.height),
                                           container: areaSize)
                        resizeDelta = .zero
                    }
            )
    }

    /// Inline hover controls for media widgets: an opacity fader (image & video) plus a
    /// mute + volume fader for video.
    private var isMedia: Bool { widget.kind == .image || widget.kind == .video }

    private var controlBar: some View {
        VStack(spacing: 4) {
            // Opacity fader (image & video).
            if isMedia {
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11)).foregroundColor(.white)
                    Slider(value: Binding(get: { widget.opacity },
                                          set: { store.setWidgetOpacity(widget.id, $0) }),
                           in: 0.05...1)
                        .controlSize(.mini).tint(.white)
                }
            }
            if widget.kind == .video {
                HStack(spacing: 6) {
                    Button { store.toggleWidgetMuted(widget.id) } label: {
                        Image(systemName: widget.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11)).foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    Slider(value: Binding(get: { widget.volume },
                                          set: { store.setWidgetVolume(widget.id, $0) }),
                           in: 0...1)
                        .controlSize(.mini).tint(.white)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            if glass {
                LiquidGlassBackground(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                      tint: GlassPalette.coolEdge,
                                      transparency: store.settings.glassTransparency,
                                      strokeOpacity: 0.34,
                                      shadowOpacity: 0.10)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .padding(.bottom, 6)
        .padding(.horizontal, 8)
        .padding(.trailing, 14)   // keep clear of the resize handle
    }
}
