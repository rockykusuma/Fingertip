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
        // Never let a hung app stall the probe queue for long. Electron and
        // Chromium regularly need >50 ms to answer, so this is generous.
        AXUIElementSetMessagingTimeout(s, 0.25)
        return s
    }()

    static func target(atCG p: CGPoint) -> Target? {
        guard let hit = element(atCG: p) else { return nil }
        // The hit is usually the deepest element (a button's label or icon);
        // climb to the nearest clickable ancestor.
        var el = hit
        var role: String? = attr(el, kAXRoleAttribute)
        var climbed = 0
        while let r = role, !roles.contains(r), climbed < 4, let parent = parent(of: el) {
            el = parent
            role = attr(el, kAXRoleAttribute)
            climbed += 1
        }
        guard let role, roles.contains(role),
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

    /// Breadth-first search of an app's windows and menu bar for a clickable
    /// element whose title contains `query` (case-insensitive). Exact title
    /// wins over a substring match. Bounded so a huge web page cannot hang us.
    static func find(titleContaining query: String, inApp pid: pid_t) -> Target? {
        let q = query.lowercased()
        let app = AXUIElementCreateApplication(pid)
        var queue: [AXUIElement] = []
        if let windows: [AXUIElement] = attrArray(app, kAXWindowsAttribute) { queue += windows }
        if let bar: AXUIElement = attrElement(app, kAXMenuBarAttribute) { queue.append(bar) }
        var best: (Target, Int)?  // target, score (2 exact, 1 contains)
        var visited = 0
        while !queue.isEmpty, visited < 2500 {
            let el = queue.removeFirst()
            visited += 1
            if let role: String = attr(el, kAXRoleAttribute), roles.contains(role) {
                let title: String? = attr(el, kAXTitleAttribute) ?? attr(el, kAXDescriptionAttribute)
                if let t = title?.lowercased(), !t.isEmpty {
                    let score = t == q ? 2 : (t.contains(q) ? 1 : 0)
                    if score > (best?.1 ?? 0),
                       let origin: CGPoint = axValue(el, kAXPositionAttribute, .cgPoint),
                       let size: CGSize = axValue(el, kAXSizeAttribute, .cgSize), size.width > 0, size.height > 0 {
                        let kind: String = attr(el, kAXRoleDescriptionAttribute) ?? role
                        best = (Target(frameCG: CGRect(origin: origin, size: size), label: "\(kind.capitalized) · \(title!)"), score)
                        if score == 2 { return best?.0 }
                    }
                }
            }
            if let kids: [AXUIElement] = attrArray(el, kAXChildrenAttribute) { queue += kids }
        }
        return best?.0
    }

    private static func attrArray(_ el: AXUIElement, _ name: String) -> [AXUIElement]? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success,
              let arr = v, CFGetTypeID(arr) == CFArrayGetTypeID() else { return nil }
        return (arr as! [AnyObject]).compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private static func attrElement(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success,
              let value = v, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Our overlay windows cover every pixel, so hit-test the topmost window
    /// that is not ours and ask its app directly; fall back to system-wide.
    private static func element(atCG p: CGPoint) -> AXUIElement? {
        var ref: AXUIElement?
        if let pid = ownerPID(ofWindowAtCG: p),
           AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(p.x), Float(p.y), &ref) == .success,
           let el = ref {
            return el
        }
        ref = nil
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &ref) == .success, let el = ref else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        return pid == getpid() ? nil : el
    }

    private static func ownerPID(ofWindowAtCG p: CGPoint) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let me = getpid()
        for w in list {  // front to back
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (w[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b), rect.contains(p) else { continue }
            return pid
        }
        return nil
    }

    private static func parent(of el: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &v) == .success,
              let value = v, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
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
