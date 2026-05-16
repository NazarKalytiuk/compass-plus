import SwiftUI

// MARK: - Theme Tokens — "Compass+ Flat" (mapped from ai_design/.../assets/styles.css)
//
// Hierarchy is communicated through tonal layering (lightness deltas between
// adjacent surfaces) and soft ambient shadows — never through 1px solid
// borders. The dark code surface is reserved for JSON / mongosh / log
// details, never for the sidebar.

enum Theme {

    // MARK: Brand / primary

    /// Brand orange — primary buttons, focus rings, active accents (#F2673C).
    static let primary = Color(red: 0.949, green: 0.404, blue: 0.235)

    /// Deep orange — pressed/hover for primary buttons, accent strip foreground (#D9491F).
    static let primaryDeep = Color(red: 0.851, green: 0.286, blue: 0.122)

    /// Warm primary tint — active row backgrounds, soft accent surfaces (#FEEFE8).
    static let primaryTint = Color(red: 0.996, green: 0.937, blue: 0.910)

    /// Gradient stop on the brand mark only (#F38B3F).
    static let primaryLight = Color(red: 0.953, green: 0.545, blue: 0.247)

    /// Violet — secondary accent for the rare badge that needs distinction (#8B5CF6).
    static let secondaryAccent = Color(red: 0.545, green: 0.361, blue: 0.965)

    // MARK: Surfaces (light)

    /// macOS window background outside chrome (#F2EFEA).
    static let canvas = Color(red: 0.949, green: 0.937, blue: 0.918)

    /// Main canvas / content background — work surface (#FAFAF7).
    static let surface0 = Color(red: 0.980, green: 0.980, blue: 0.969)

    /// Cards, document rows, toolbar (#FFFFFF).
    static let surface1 = Color.white

    /// Sidebar background, status bar, tab bar gutter (#F4F1EC).
    static let surface2 = Color(red: 0.957, green: 0.945, blue: 0.925)

    /// Recessed wells — filters, themed inputs, segmented backgrounds (#EBE7DF).
    static let surface3 = Color(red: 0.922, green: 0.906, blue: 0.875)

    /// Hover lift on rows (#F0ECE5).
    static let surfaceHover = Color(red: 0.941, green: 0.925, blue: 0.898)

    /// Active row / selected nav — primary-tinted (#FEEFE8).
    static let surfaceActive = primaryTint

    // MARK: Code surface (dark recessed)

    /// Code-block background — JSON / mongosh / log details (#1B1F27).
    static let codeBg = Color(red: 0.106, green: 0.122, blue: 0.153)

    /// Code gutter / nested block (#232833).
    static let codeBg2 = Color(red: 0.137, green: 0.157, blue: 0.200)

    /// Code body text on dark surface (#E6E6E6).
    static let codeFg = Color(red: 0.902, green: 0.902, blue: 0.902)

    /// Muted code text — line numbers, gutter labels (#7A8290).
    static let codeMuted = Color(red: 0.478, green: 0.510, blue: 0.565)

    /// Syntax — strings (#8FCB8F).
    static let codeString = Color(red: 0.561, green: 0.796, blue: 0.561)

    /// Syntax — numbers (#F4B860).
    static let codeNumber = Color(red: 0.957, green: 0.722, blue: 0.376)

    /// Syntax — keys / identifiers (#6FB7E0).
    static let codeKey = Color(red: 0.435, green: 0.718, blue: 0.878)

    /// Syntax — keywords (#E58FB7).
    static let codeKeyword = Color(red: 0.898, green: 0.561, blue: 0.718)

    /// Syntax — comments (#5C6675).
    static let codeComment = Color(red: 0.361, green: 0.400, blue: 0.459)

    /// Syntax — booleans / nulls (#B98AE8).
    static let codeBool = Color(red: 0.725, green: 0.541, blue: 0.910)

    /// Syntax — brackets / punctuation (#9CA3AF).
    static let codeBracket = Color(red: 0.612, green: 0.639, blue: 0.686)

    /// Shell prompt — orange (#F2673C).
    static let codePrompt = primary

    // MARK: Text

    /// Primary text on light surfaces (#111827).
    static let textPrimary = Color(red: 0.067, green: 0.094, blue: 0.153)

    /// Slightly softer body text (#1F2937).
    static let textSoft = Color(red: 0.122, green: 0.161, blue: 0.216)

    /// Muted text — secondary labels, host strings, captions (#5B6472).
    static let textSecondary = Color(red: 0.357, green: 0.392, blue: 0.447)

    /// Quieter text — placeholders, badge meta (#8A93A2).
    static let textMuted = Color(red: 0.541, green: 0.576, blue: 0.635)

    // MARK: Status

    /// Connected / healthy (#16A34A).
    static let success = Color(red: 0.086, green: 0.639, blue: 0.290)

    /// Degraded / slow (#D97706).
    static let warning = Color(red: 0.851, green: 0.467, blue: 0.024)

    /// Down / destructive (#DC2626).
    static let danger = Color(red: 0.863, green: 0.149, blue: 0.149)

    /// Informational / links (#2563EB).
    static let info = Color(red: 0.145, green: 0.388, blue: 0.922)

    // MARK: Pill tints (status & semantic backgrounds)

    static let infoTint    = Color(red: 0.878, green: 0.922, blue: 0.984)   // #E0EBFB
    static let infoDeep    = Color(red: 0.114, green: 0.306, blue: 0.847)   // #1D4ED8
    static let successTint = Color(red: 0.863, green: 0.988, blue: 0.906)   // #DCFCE7
    static let successDeep = Color(red: 0.082, green: 0.502, blue: 0.239)   // #15803D
    static let warningTint = Color(red: 0.996, green: 0.953, blue: 0.780)   // #FEF3C7
    static let warningDeep = Color(red: 0.706, green: 0.325, blue: 0.035)   // #B45309
    static let dangerTint  = Color(red: 0.996, green: 0.886, blue: 0.886)   // #FEE2E2
    static let dangerDeep  = Color(red: 0.725, green: 0.110, blue: 0.110)   // #B91C1C
    static let violetTint  = Color(red: 0.929, green: 0.914, blue: 0.996)   // #EDE9FE
    static let violetDeep  = Color(red: 0.427, green: 0.157, blue: 0.851)   // #6D28D9

    // MARK: Lines / shadows

    /// Hairline rule — `rgba(17,24,39,0.06)`. Used only when a divider is
    /// truly necessary — prefer tonal layering instead.
    static let hairline = Color(red: 0.067, green: 0.094, blue: 0.153).opacity(0.06)

    /// Soft ambient shadow — matches `--shadow-sm` (a single softer drop).
    static let shadowAmbient = Color(red: 0.067, green: 0.094, blue: 0.153).opacity(0.06)

    /// Stronger lift — matches `--shadow-md`.
    static let shadowElevated = Color(red: 0.067, green: 0.094, blue: 0.153).opacity(0.10)

    // MARK: Brand gradient (used on the wordmark mark only)

    static let brandGradient = LinearGradient(
        colors: [primary, primaryLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Backwards-compat aliases
    //
    // The codebase still references the old "Leaf & Midnight" names. Each
    // alias resolves to the closest semantic equivalent under the new
    // Flat token set so other Views compile until they're migrated.

    static let accent       = primary
    static let accentDeep   = primaryDeep
    static let green        = primary
    static let amber        = warning
    static let skyBlue      = info
    static let crimson      = danger

    static let midnight       = codeBg
    static let sidebarBg      = surface2
    static let sidebarSurface = surface1
    static let surface        = surface1
    static let surfaceLow     = surface3
    static let surfaceMid     = surface2
    static let surfaceHigh    = surfaceHover

    static let textOnDark      = codeFg
    static let textOnDarkMuted = codeMuted

    static let ghostBorder = Color(red: 0.067, green: 0.094, blue: 0.153).opacity(0.08)
    static let border      = hairline
    static let outline     = primary.opacity(0.45)

    static let ambientShadow  = shadowAmbient
    static let elevatedShadow = shadowElevated

    /// Primary CTA gradient — kept for old AccentButtonStyle callers.
    /// New design uses a flat fill; this gradient now resolves to a
    /// near-flat primary→primary so existing buttons stay on-brand.
    static let accentGradient = LinearGradient(
        colors: [primary, primaryDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Card Style — tonal, borderless

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface1)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Theme.shadowAmbient, radius: 6, y: 2)
    }
}

extension View {
    /// White card on the warm canvas — separation by tonal lift, never a border.
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 8) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }

    /// Recessed well — a mount for code editors / filter inputs.
    func wellStyle(padding: CGFloat = 10, cornerRadius: CGFloat = 8) -> some View {
        self
            .padding(padding)
            .background(Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Pill Badge

enum BadgeKind {
    case neutral, accent, info, success, warning, danger, violet

    var foreground: Color {
        switch self {
        case .neutral: return Theme.textSecondary
        case .accent:  return Theme.primaryDeep
        case .info:    return Theme.infoDeep
        case .success: return Theme.successDeep
        case .warning: return Theme.warningDeep
        case .danger:  return Theme.dangerDeep
        case .violet:  return Theme.violetDeep
        }
    }

    var background: Color {
        switch self {
        case .neutral: return Theme.surface3
        case .accent:  return Theme.primaryTint
        case .info:    return Theme.infoTint
        case .success: return Theme.successTint
        case .warning: return Theme.warningTint
        case .danger:  return Theme.dangerTint
        case .violet:  return Theme.violetTint
        }
    }
}

struct PillBadge: ViewModifier {
    var kind: BadgeKind = .neutral

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(kind.background)
            .foregroundStyle(kind.foreground)
            .clipShape(Capsule())
    }
}

extension View {
    /// Capsule label — uppercase metadata badge (PRODUCTION / ACTIVE / etc.)
    func pillBadge(_ kind: BadgeKind = .neutral) -> some View {
        modifier(PillBadge(kind: kind))
    }

    /// Custom-color pill for callers that need an explicit colour pair.
    func pillBadge(color: Color, textColor: Color = .white) -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color)
            .foregroundStyle(textColor)
            .clipShape(Capsule())
    }
}

// MARK: - Buttons

/// Primary CTA — flat brand orange, white text, md radius (6pt), warm shadow.
struct AccentButtonStyle: ButtonStyle {
    /// `nil` uses the brand primary. Provide a flat color for status
    /// variants (e.g. destructive crimson).
    var color: Color? = nil
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let fill = color ?? Theme.primary
        let shadowTint = (color ?? Theme.primaryDeep).opacity(configuration.isPressed ? 0.0 : 0.30)

        return configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? 12 : 16)
            .padding(.vertical, isCompact ? 6 : 8)
            .background(configuration.isPressed ? fill.opacity(0.92) : fill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: shadowTint, radius: 4, y: 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    /// Primary call-to-action — flat brand orange.
    static var accent: AccentButtonStyle { AccentButtonStyle() }

    /// Compact accent for toolbars and inline actions.
    static var accentCompact: AccentButtonStyle { AccentButtonStyle(isCompact: true) }

    /// Destructive flat-fill (red).
    static var destructive: AccentButtonStyle { AccentButtonStyle(color: Theme.danger) }
}

/// Ghost — text-only with hover fill (no border).
struct GhostButtonStyle: ButtonStyle {
    var color: Color = Theme.textSoft

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Theme.surface3 : Theme.surfaceHover.opacity(0.0))
            )
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Toolbar Icon Button

struct ToolbarIconButton: ViewModifier {
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Theme.primaryDeep : Theme.textSecondary)
            .frame(width: 30, height: 30)
            .background(isActive ? Theme.primaryTint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

extension View {
    /// Toolbar icon button.
    func toolbarIconButton(isActive: Bool = false) -> some View {
        modifier(ToolbarIconButton(isActive: isActive))
    }
}

// MARK: - Themed Text Field

struct ThemedTextFieldStyle: TextFieldStyle {
    var monospaced: Bool = true

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: monospaced ? .monospaced : .default))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surface3)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension TextFieldStyle where Self == ThemedTextFieldStyle {
    /// Recessed field, monospaced — for queries / URIs / values.
    static var themed: ThemedTextFieldStyle { ThemedTextFieldStyle() }

    /// Recessed field, sans-serif — for names / labels.
    static var themedSans: ThemedTextFieldStyle { ThemedTextFieldStyle(monospaced: false) }
}

// MARK: - Section Header

struct SectionHeaderStyle: ViewModifier {
    /// `onDark` keeps the muted contrast for headers placed on the dark
    /// code surface. The sidebar is now light, so default callers stay
    /// readable without changes.
    var onDark: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(onDark ? Theme.codeMuted : Theme.textMuted)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

extension View {
    func sectionHeaderStyle(onDark: Bool = false) -> some View {
        modifier(SectionHeaderStyle(onDark: onDark))
    }
}

// MARK: - Status Dot — filled circle with soft halo of the same hue

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color.opacity(0.18))
            .frame(width: size + 6, height: size + 6)
            .overlay(
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            )
    }
}

// MARK: - Themed Divider — hairline only

struct ThemedDivider: View {
    var vertical: Bool = false
    var onDark: Bool = false

    var body: some View {
        Rectangle()
            .fill(onDark ? Color.white.opacity(0.06) : Theme.hairline)
            .frame(
                width: vertical ? 1 : nil,
                height: vertical ? nil : 1
            )
    }
}

// MARK: - Code Surface

struct CodeSurface: ViewModifier {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .foregroundStyle(Theme.codeFg)
            .font(.system(size: 12, design: .monospaced))
    }
}

extension View {
    /// Recessed dark surface for code blocks. Pair with `Theme.codeString`,
    /// `Theme.codeKey`, `Theme.codeKeyword`, etc. for syntax.
    func codeSurface(padding: CGFloat = 14, cornerRadius: CGFloat = 8) -> some View {
        modifier(CodeSurface(padding: padding, cornerRadius: cornerRadius))
    }
}
