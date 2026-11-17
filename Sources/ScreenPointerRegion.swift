import AppKit

enum ScreenPointerRegion {
    /// AppKit reports maxY when the pointer touches a display's top edge.
    /// CGRect.contains excludes that boundary, making an edge-triggered panel
    /// fail precisely when the user pushes the pointer all the way up.
    /// Include the top without extending into the display above. Keep maxX
    /// exclusive so side-by-side displays retain unambiguous ownership.
    static func contains(_ point: NSPoint, in frame: NSRect) -> Bool {
        guard !frame.isNull, !frame.isEmpty else { return false }
        return point.x >= frame.minX && point.x < frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }
}
