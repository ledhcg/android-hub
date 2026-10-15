import CoreGraphics

// Prints "<windowID> <owner> <layer> <bounds>" for the on-screen "Android Hub" windows (layer 0).
// usage: swift winid.swift      -> use the ID with: screencapture -x -o -l <ID> out.png
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for window in windows where (window[kCGWindowOwnerName as String] as? String)?.contains("Android") == true
    && (window[kCGWindowLayer as String] as? Int) == 0
{
    print(window[kCGWindowNumber as String]!, window[kCGWindowOwnerName as String]!, window[kCGWindowBounds as String]!)
}
