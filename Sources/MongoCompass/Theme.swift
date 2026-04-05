import SwiftUI

// MARK: - Theme Colors

enum Theme {
    /// Primary accent — MongoDB brand green (#00ED64)
    static let green = Color(red: 0.0, green: 0.929, blue: 0.392)

    /// Dark background — deep midnight (#001E2B)
    static let midnight = Color(red: 0.0, green: 0.118, blue: 0.169)

    /// Destructive / danger (#DB3030)
    static let crimson = Color(red: 0.859, green: 0.188, blue: 0.188)

    /// Warning (#F5A623)
    static let amber = Color(red: 0.961, green: 0.651, blue: 0.137)

    /// Info / links (#0498EC)
    static let skyBlue = Color(red: 0.016, green: 0.596, blue: 0.925)

    /// Card / panel backgrounds — slightly lighter than midnight (#112733)
    static let surface = Color(red: 0.067, green: 0.153, blue: 0.2)

    /// Subtle borders (#1C3A4A)
    static let border = Color(red: 0.110, green: 0.227, blue: 0.290)

    /// Muted text color
    static let textSecondary = Color.white.opacity(0.5)

    /// Dimmed surface for hover states
    static let surfaceHover = Color(red: 0.09, green: 0.19, blue: 0.25)
}

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    /// Applies a dark card style with surface background and subtle border.
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 10) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Pill Badge Modifier

struct PillBadge: ViewModifier {
    var color: Color
    var textColor: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

extension View {
    /// Wraps the view in a pill-shaped badge with the given background and text color.
    func pillBadge(color: Color = Theme.green, textColor: Color = .white) -> some View {
        modifier(PillBadge(color: color, textColor: textColor))
    }
}

// MARK: - Accent Button Style

struct AccentButtonStyle: ButtonStyle {
    var color: Color = Theme.green
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
            .foregroundStyle(Theme.midnight)
            .padding(.horizontal, isCompact ? 12 : 20)
            .padding(.vertical, isCompact ? 6 : 10)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    /// A prominent button with the accent color background.
    static var accent: AccentButtonStyle { AccentButtonStyle() }

    /// A compact accent button for toolbars and inline actions.
    static var accentCompact: AccentButtonStyle { AccentButtonStyle(isCompact: true) }

    /// A destructive button using crimson.
    static var destructive: AccentButtonStyle { AccentButtonStyle(color: Theme.crimson) }
}

// MARK: - Ghost Button Style (outlined / subtle)

struct GhostButtonStyle: ButtonStyle {
    var color: Color = Theme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.15 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    /// An outlined / ghost button style.
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Toolbar Icon Button Modifier

struct ToolbarIconButton: ViewModifier {
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .foregroundStyle(isActive ? Theme.green : .secondary)
            .frame(width: 32, height: 32)
            .background(isActive ? Theme.green.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

extension View {
    /// Styles a view as a toolbar icon button with optional active state.
    func toolbarIconButton(isActive: Bool = false) -> some View {
        modifier(ToolbarIconButton(isActive: isActive))
    }
}

// MARK: - Themed Text Field Style

struct ThemedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .padding(10)
            .background(Theme.midnight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .foregroundStyle(.white)
    }
}

extension TextFieldStyle where Self == ThemedTextFieldStyle {
    /// A dark themed text field matching the app's design language.
    static var themed: ThemedTextFieldStyle { ThemedTextFieldStyle() }
}

// MARK: - Section Header Modifier

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

extension View {
    /// Styles text as an uppercase section header.
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.5), radius: 3)
    }
}

// MARK: - Divider

struct ThemedDivider: View {
    var vertical: Bool = false

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(
                width: vertical ? 1 : nil,
                height: vertical ? nil : 1
            )
    }
}
