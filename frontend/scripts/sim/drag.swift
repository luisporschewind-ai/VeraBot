import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { Double($0)! }
let p0 = CGPoint(x: a[0], y: a[1]), p1 = CGPoint(x: a[2], y: a[3])
let src = CGEventSource(stateID: .hidSystemState)
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
post(.mouseMoved, p0); usleep(100000)
post(.leftMouseDown, p0); usleep(150000)
let n = 30
for i in 1...n { let f = Double(i)/Double(n); post(.leftMouseDragged, CGPoint(x: p0.x + (p1.x-p0.x)*f, y: p0.y + (p1.y-p0.y)*f)); usleep(16000) }
usleep(200000); post(.leftMouseUp, p1)
