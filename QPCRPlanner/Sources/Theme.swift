import SwiftUI
import AppKit

// MARK: - Brand (shared look with the ICC Plate Planner)

enum Brand {
    static let appName = "qPCR Planner"
    static let department = "Department of Regenerative Medicine Research"
    static let hospital = "Kobe City Medical Center General Hospital"
    static let author = "Joey Russell"

    // Palette taken from the department's slide banner: navy -> blue -> pale blue-white; in dark mode,
    // the navy of the splash and the waiting panel.
    static let navy = Color.dynamic("1E4A83", "2D62AE")       // fills: buttons, selected tabs
    static let accent = Color.dynamic("1E4A83", "8DB8F2")     // navy text and icons
    static let mid = Color.dynamic("4A78B8", "7FA9E6")
    static let pale = Color.dynamic("E8EEF6", "16365F")
    static let rule = Color.dynamic("D5DEEB", "27507F")
    static let ink = Color.dynamic("172033", "E8EFF8")
    static let card = Color.dynamic("FFFFFF", "102B50")
    static let page = Color.dynamic("F7F9FC", "0A1D38")
    static let chartInk = Color.dynamic("262626", "D9E2EE")
    static let chartGrey = Color.dynamic("595959", "93A4BC")
    static let grid = Color.dynamic("E9EDF3", "1E3D66")
    static let barEdge = Color.black.opacity(0.85)
    static let errorBar = Color.dynamic("000000", "E8EFF8")
    static let plateBody = Color.dynamic("F3F6FA", "13315A")
    static let tooltip = Color(fixed: "172033")
    static let gradient = LinearGradient(
        stops: [.init(color: .dynamic("1E4A83", "0B1F3A"), location: 0), .init(color: .dynamic("4A78B8", "17437A"), location: 0.5),
                .init(color: .dynamic("E8EEF6", "2F5F9E"), location: 1)],
        startPoint: .leading, endPoint: .trailing)

    /// Department logo shipped inside the app bundle (the same image used on the slide banner).
    static let logo: NSImage? = Bundle.main.url(forResource: "DeptLogo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
}

/// Small navy square + letter-spaced serif capitals, like the eyebrow line on the department's slides.
struct Eyebrow: View {
    let text: String
    var color: Color = Brand.accent
    var size: CGFloat = 10
    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: size * 0.8, height: size * 0.8)
            Text(text.uppercased()).font(.system(size: size, weight: .bold, design: .serif)).tracking(size * 0.2).foregroundColor(color)
        }
    }
}

/// The light design's own greys, inks and pale fills, and what each becomes in dark mode. Gene colours and
/// the parts that are always dark (splash, waiting panel, bench mode) are not listed, so they never change.
let darkShades: [String: String] = [
    "F7F9FC": "0A1D38", "F4F7FB": "0E2647", "F2F6FB": "0E2647", "F3F6FA": "13315A", "EEF2F7": "1A3A66",
    "E9EEF5": "0F2A4E", "E9EDF3": "1E3D66", "E8EEF6": "16365F", "E3EAF4": "1C3E6A", "E3E9F2": "1C3E6A",
    "DCE3EC": "23466F", "DDF3E4": "16402F", "D5DEEB": "27507F", "D3DDEA": "27507F", "D2DBE7": "2A4D78",
    "CDD7E5": "2C527F", "C9D4E3": "3A5F8C", "B8C4D6": "4A6A95", "B7C5D8": "4A6A95", "AFBFD4": "4F6F9A",
    "C9D1DC": "4A5B73", "172033": "E8EFF8", "262626": "D9E2EE", "595959": "93A4BC", "6B7A90": "9AAEC8",
    "8A99AF": "8FA3BE", "9AA8BC": "7F93B0", "9AA3B2": "7F93B0",
]

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension Color {
    /// A colour of the light design, adapting to dark mode when it is one of the shades above.
    init(hex: String) {
        if let d = darkShades[hex.uppercased()], !d.isEmpty { self = .dynamic(hex, d) } else { self.init(fixed: hex) }
    }

    /// Always this colour.
    init(fixed hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0xCCCCCC
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}


let plain = FloatingPointFormatStyle<Double>.number.grouping(.never)

extension Binding where Value: MutableCollection, Value.Element: Identifiable {
    /// A binding to one row that is looked up by id every time it is read or written. A row that has
    /// just been deleted can therefore never be reached through a stale index.
    func row(_ element: Value.Element) -> Binding<Value.Element> {
        Binding<Value.Element>(
            get: { wrappedValue.first(where: { $0.id == element.id }) ?? element },
            set: { new in
                if let i = wrappedValue.firstIndex(where: { $0.id == element.id }) { wrappedValue[i] = new }
            })
    }
}

// MARK: - Building blocks

struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Brand.card)
            .shadow(color: Brand.navy.opacity(0.10), radius: 7, x: 0, y: 2)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.rule, lineWidth: 1))
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Rectangle().fill(Brand.navy).frame(width: 9, height: 9)
                Text(title).font(.system(size: 18, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                Spacer()
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundColor(Brand.mid)
            }
            Rectangle().fill(Brand.rule).frame(height: 1)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 0.75))
    }
}


/// A pointer position for development snapshots (--hover x y); nil in normal use.
var debugHoverPoint: CGPoint?

/// A transparent layer that follows the pointer and paints only what depends on it (a highlight, a
/// read-out). Keeping the pointer here means moving the mouse redraws this layer alone, not the
/// drawing underneath.
struct HoverCanvas: View {
    let paint: (inout GraphicsContext, CGSize, CGPoint) -> Void
    let onTap: ((CGPoint, CGSize) -> Void)?
    private let point = State<CGPoint?>(initialValue: nil)

    init(_ paint: @escaping (inout GraphicsContext, CGSize, CGPoint) -> Void, onTap: ((CGPoint, CGSize) -> Void)? = nil) {
        self.paint = paint
        self.onTap = onTap
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { g, size in
                if let p = point.wrappedValue ?? debugHoverPoint { paint(&g, size, p) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): point.wrappedValue = p
                case .ended: point.wrappedValue = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { p in onTap?(p, geo.size) }
        }
    }
}

extension View {
    /// Digits roll to their new value (an odometer) when `value` changes.
    func rolling<V: Equatable>(_ value: V, _ on: Bool) -> some View {
        self.contentTransition(.numericText())
            .animation(on ? .spring(response: 0.5, dampingFraction: 0.78) : nil, value: value)
    }
}
