import SwiftUI
import VeraBotCore

/// Accessories derive their anchors from the current deformed body, before its shared motion transform.
enum RobotAvatarAccessoryRendering {
    static func draw(_ accessory:BotAvatarAccessory,badge:BotAvatarBadgeStyle,head:Path,color:Color,bodyColor:Color,in context:inout GraphicsContext) {
        guard accessory != .none else { return }
        let bounds = head.boundingRect
        switch accessory {
        case .none: break
        case .headphones: headphones(head:head,bounds:bounds,accent:color,in:&context)
        case .badge:
            let y=bounds.maxY-28
            let (_,right)=edges(head,at:y,fallback:bounds)
            let center=CGPoint(x:right-20,y:y)
            let disc=Path(ellipseIn:CGRect(x:center.x-13,y:center.y-13,width:26,height:26))
            context.fill(disc,with:.color(color))
            context.stroke(disc,with:.color(.black.opacity(0.25)),lineWidth:1.5)
            var glyph=context
            glyph.translateBy(x:center.x,y:center.y)
            drawBadge(badge,in:&glyph)
        }
    }

    private static func headphones(head:Path,bounds:CGRect,accent:Color,in context:inout GraphicsContext) {
        let y=bounds.midY+2
        let (left,right)=edges(head,at:y,fallback:bounds)
        let shell=Color(red:0.20,green:0.21,blue:0.25)
        let cushion=Color(red:0.07,green:0.08,blue:0.10)
        var band=Path(); band.move(to:CGPoint(x:left-2,y:y))
        for point in contour(head).filter({ $0.y <= y }).sorted(by:{ $0.x < $1.x }) {
            band.addLine(to:CGPoint(x:point.x,y:point.y-3))
        }
        band.addLine(to:CGPoint(x:right+2,y:y))
        context.stroke(band,with:.color(shell),style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
        context.stroke(band,with:.color(accent.opacity(0.32)),style:StrokeStyle(lineWidth:1.2,lineCap:.round,lineJoin:.round))
        for (x,side) in [(left-8,CGFloat(-1)),(right-8,CGFloat(1))] {
            let cup=Path(roundedRect:CGRect(x:x,y:y-18,width:16,height:36),cornerRadius:8)
            context.fill(cup,with:.linearGradient(Gradient(colors:[shell,shell.opacity(0.95),cushion]),
                startPoint:CGPoint(x:x,y:y-18),endPoint:CGPoint(x:x+16,y:y+18)))
            context.stroke(cup,with:.color(cushion.opacity(0.85)),lineWidth:1)
            let padding=Path(roundedRect:CGRect(x:x+3,y:y-12,width:10,height:24),cornerRadius:5)
            context.fill(padding,with:.color(cushion))
            var seam=Path(); seam.move(to:CGPoint(x:x+8+side*4,y:y-8)); seam.addLine(to:CGPoint(x:x+8+side*4,y:y+8))
            context.stroke(seam,with:.color(accent.opacity(0.48)),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
            let joint=Path(ellipseIn:CGRect(x:x+6,y:y-17,width:4,height:4))
            context.fill(joint,with:.color(accent.opacity(0.5)))
        }
    }

    private static func drawBadge(_ style:BotAvatarBadgeStyle,in glyph:inout GraphicsContext) {
        let ink=Color(red:0.13,green:0.14,blue:0.18)
        var mark=Path()
        switch style {
        case .spark:
            mark.move(to:CGPoint(x:0,y:-7))
            mark.addQuadCurve(to:CGPoint(x:6,y:0),control:CGPoint(x:1.5,y:-1.5))
            mark.addQuadCurve(to:CGPoint(x:0,y:7),control:CGPoint(x:1.5,y:1.5))
            mark.addQuadCurve(to:CGPoint(x:-6,y:0),control:CGPoint(x:-1.5,y:1.5))
            mark.addQuadCurve(to:CGPoint(x:0,y:-7),control:CGPoint(x:-1.5,y:-1.5))
            mark.closeSubpath()
        case .heart:
            mark.move(to:CGPoint(x:0,y:6))
            mark.addCurve(to:CGPoint(x:0,y:-3),control1:CGPoint(x:-13,y:-1),control2:CGPoint(x:-5,y:-10))
            mark.addCurve(to:CGPoint(x:0,y:6),control1:CGPoint(x:5,y:-10),control2:CGPoint(x:13,y:-1))
            mark.closeSubpath()
        case .bolt:
            mark.move(to:CGPoint(x:2,y:-7)); mark.addLine(to:CGPoint(x:-5,y:1))
            mark.addLine(to:CGPoint(x:0,y:1)); mark.addLine(to:CGPoint(x:-2,y:7))
            mark.addLine(to:CGPoint(x:5,y:-1)); mark.addLine(to:CGPoint(x:0,y:-1)); mark.closeSubpath()
        case .leaf:
            mark.move(to:CGPoint(x:-5,y:5))
            mark.addCurve(to:CGPoint(x:6,y:-6),control1:CGPoint(x:-9,y:-5),control2:CGPoint(x:2,y:-8))
            mark.addCurve(to:CGPoint(x:-5,y:5),control1:CGPoint(x:8,y:2),control2:CGPoint(x:3,y:9))
            mark.closeSubpath()
        }
        glyph.fill(mark,with:.color(ink))
        glyph.stroke(mark,with:.color(ink),style:StrokeStyle(lineWidth:0.7,lineCap:.round,lineJoin:.round))
        if style == .leaf {
            var vein=Path(); vein.move(to:CGPoint(x:-3,y:3)); vein.addLine(to:CGPoint(x:3,y:-3))
            glyph.stroke(vein,with:.color(.white.opacity(0.8)),style:StrokeStyle(lineWidth:1,lineCap:.round))
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
