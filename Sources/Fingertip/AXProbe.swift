import AppKit
import ApplicationServices

/// Asks the Accessibility API what sits under a screen point. Only
/// clickable roles count; everything else returns nil so the hand keeps
/// following the cursor.
enum AXProbe {
    struct Target {
        /// CG coordinates: top-left origin on the primary display.
        let frameCG: CGRect
        let label: String
    }

    private static let roles: Set<String> = [
        kAXButtonRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXCheckBoxRole,
        kAXRadioButtonRole, kAXPopUpButtonRole, "AXLink",
        kAXDisclosureTriangleRole, "AXMenuButton", "AXTab",
    ]

    private static let system: AXUIElement = {
        let s = AXUIElementCreateSystemWide()
        // Never let a hung app stall the probe queue for long.
        AXUIElementSetMessagingTimeout(s, 0.05)
        return s
    }()

    static func target(atCG p: CGPoint) -> Target? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &ref) == .success,
              let el = ref else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard pid != getpid() else { return nil }  // our own overlay window
        guard let role: String = attr(el, kAXRoleAttribute), roles.contains(role),
              let origin: CGPoint = axValue(el, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(el, kAXSizeAttribute, .cgSize),
              size.width > 0, size.height > 0 else { return nil }

        let title: String? = attr(el, kAXTitleAttribute)
            ?? attr(el, kAXDescriptionAttribute)
            ?? (attr(el, kAXValueAttribute) as String?)
        let kind: String = attr(el, kAXRoleDescriptionAttribute) ?? role
        let label = [kind.capitalized, title?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Target(frameCG: CGRect(origin: origin, size: size), label: label)
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func axValue<T>(_ el: AXUIElement, _ name: String, _ type: AXValueType) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success,
              let value = v, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == type else { return nil }
        switch type {
        case .cgPoint: var out = CGPoint.zero; return AXValueGetValue(ax, type, &out) ? out as? T : nil
        case .cgSize: var out = CGSize.zero; return AXValueGetValue(ax, type, &out) ? out as? T : nil
        default: return nil
        }
    }
}
