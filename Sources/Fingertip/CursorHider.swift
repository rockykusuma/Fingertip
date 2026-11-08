import AppKit
import CoreGraphics

/// Hides the system cursor while the hand is shown.
///
/// `CGDisplayHideCursor` is normally ignored for apps that aren't frontmost.
/// Setting the private WindowServer connection property
/// `SetsCursorInBackground` lifts that restriction. This is a private API
/// (fine for a personal tool; not App Store material) and looked up with
/// dlsym so a missing symbol degrades to "cursor stays visible".
enum CursorHider {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SetPropertyFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static let symbols: (MainConnectionFn, SetPropertyFn)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connSym = dlsym(handle, "CGSMainConnectionID"),
              let propSym = dlsym(handle, "CGSSetConnectionProperty") else { return nil }
        return (unsafeBitCast(connSym, to: MainConnectionFn.self),
                unsafeBitCast(propSym, to: SetPropertyFn.self))
    }()

    private static var prepared = false
    private(set) static var isHidden = false

    private static func prepare() {
        guard !prepared, let (mainConnection, setProperty) = symbols else { return }
        prepared = true
        let cid = mainConnection()
        _ = setProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    static func hide() {
        guard !isHidden else { return }
        prepare()
        isHidden = true
        CGDisplayHideCursor(CGMainDisplayID())
    }

    static func show() {
        guard isHidden else { return }
        isHidden = false
        CGDisplayShowCursor(CGMainDisplayID())
    }
}
