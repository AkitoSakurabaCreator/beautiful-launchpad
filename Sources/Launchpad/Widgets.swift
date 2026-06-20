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
        }
    }
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

/// Placeholder until Phase 4 wires live weather (Open-Meteo).
private struct WeatherWidgetView: View {
    let widget: WidgetItem
    let accent: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "cloud.sun").font(.system(size: 22))
            Text("—°").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Weather").font(.system(size: 11)).opacity(0.7)
        }
        .foregroundColor(accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Draggable / resizable tile + layer

/// All widgets on a page, positioned & sized by their normalized values.
struct WidgetLayer: View {
    @EnvironmentObject var store: LaunchpadStore
    let pageIndex: Int
    let areaSize: CGSize

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
    private var baseW: CGFloat { max(60, widget.w * areaSize.width) }
    private var baseH: CGFloat { max(44, widget.h * areaSize.height) }

    var body: some View {
        let w = max(60, baseW + resizeDelta.width)
        let h = max(44, baseH + resizeDelta.height)
        let cx = widget.x * areaSize.width + dragOffset.width
        let cy = widget.y * areaSize.height + dragOffset.height

        VStack(spacing: 0) {
            titleBar
            WidgetContentView(widget: widget)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: w, height: h)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((cyber ? CyberPalette.tile : Color.black).opacity(cyber ? 0.6 : 0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((cyber ? CyberPalette.neon : Color.white).opacity(cyber ? 0.85 : 0.18),
                        lineWidth: cyber ? 1.5 : 1)
        )
        .shadow(color: cyber ? CyberPalette.neon.opacity(0.5) : .black.opacity(0.3),
                radius: cyber ? 8 : 4)
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .position(x: cx, y: cy)
        .onHover { hovering = $0 }
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
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded { v in
                    let center = CGPoint(x: widget.x * areaSize.width + v.translation.width,
                                         y: widget.y * areaSize.height + v.translation.height)
                    store.moveWidget(widget.id, center: center, container: areaSize)
                    dragOffset = .zero
                }
        )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(hovering ? 0.85 : 0.4))
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
}
