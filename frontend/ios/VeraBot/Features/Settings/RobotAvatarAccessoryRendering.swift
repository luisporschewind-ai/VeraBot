import SwiftUI
import VeraBotCore

/// Accessories derive their anchors from the current deformed body, before its shared motion transform.
enum RobotAvatarAccessoryRendering {
    static func draw(_ accessory:BotAvatarAccessory,head:Path,color:Color,bodyColor:Color,in context:inout GraphicsContext) {
        guard accessory != .none else { return }
        let bounds = head.boundingRect
        switch accessory {
        case .none: break
        case .headphones:
            let y = bounds.midY
            let (left,right) = edges(head,at:y,fallback:bounds)
            var band = Path()
            band.move(to:CGPoint(x:left-2,y:y))
            for point in contour(head).filter({ $0.y <= y }).sorted(by:{ $0.x < $1.x }) {
                band.addLine(to:CGPoint(x:point.x,y:point.y-3))
            }
            band.addLine(to:CGPoint(x:right+2,y:y))
            context.stroke(band,with:.color(bodyColor.opacity(0.8)),style:StrokeStyle(lineWidth:8,lineCap:.round))
            context.stroke(band,with:.color(color),style:StrokeStyle(lineWidth:6,lineCap:.round))
            for x in [left-7,right-7] {
                let pad = Path(roundedRect:CGRect(x:x,y:y-20,width:14,height:40),cornerRadius:6)
                context.fill(pad,with:.color(color))
                context.stroke(pad,with:.color(bodyColor.opacity(0.65)),lineWidth:2)
            }
        case .badge:
            let y = bounds.maxY-27
            let (_,right) = edges(head,at:y,fallback:bounds)
            let center = CGPoint(x:right-17,y:y)
            let rim = Path(ellipseIn:CGRect(x:center.x-10,y:center.y-10,width:20,height:20))
            context.fill(rim,with:.color(color))
            context.stroke(rim,with:.color(bodyColor.opacity(0.6)),lineWidth:1.5)
            var mark = Path()
            mark.move(to:CGPoint(x:center.x,y:center.y-5))
            mark.addLine(to:CGPoint(x:center.x+4,y:center.y))
            mark.addLine(to:CGPoint(x:center.x,y:center.y+5))
            mark.addLine(to:CGPoint(x:center.x-4,y:center.y))
            mark.closeSubpath()
            context.fill(mark,with:.color(bodyColor))
        }
    }

    private static func edges(_ head:Path,at y:CGFloat,fallback:CGRect) -> (CGFloat,CGFloat) {
        let points = contour(head)
        guard var previous = points.last else { return (fallback.minX,fallback.maxX) }
        var crossings = [CGFloat]()
        for point in points {
            if (previous.y <= y && point.y > y) || (point.y <= y && previous.y > y) {
                crossings.append(previous.x + (y-previous.y)*(point.x-previous.x)/(point.y-previous.y))
            }
            previous = point
        }
        return (crossings.min() ?? fallback.minX,crossings.max() ?? fallback.maxX)
    }

    private static func contour(_ head:Path) -> [CGPoint] {
        var points = [CGPoint]()
        head.forEach { element in
            switch element {
            case .move(to:let point), .line(to:let point): points.append(point)
            default: break // Both avatar silhouettes are closed polylines.
            }
        }
        return points
    }
}
