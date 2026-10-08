import Foundation

struct BotAvatarTemplate: Sendable {
    enum Geometry: Sendable { case cxRobot }
    struct Capabilities: OptionSet, Sendable {
        let rawValue: Int
        static let antenna = Self(rawValue:1)
        static let hearts = Self(rawValue:2)
        static let squeeze = Self(rawValue:4)
    }
    let id: String
    let version: Int
    let title: String
    let geometry: Geometry
    var leftEyeAnchor: CGPoint
    var rightEyeAnchor: CGPoint
    var antennaAnchor: CGPoint
    var antennaRadius: Double
    var drawingMargin: Double
    var capabilities: Capabilities

    func adapt(_ original: RobotAvatarMotion.Frame) -> RobotAvatarMotion.Frame {
        var f=original
        for (i,anchor) in [leftEyeAnchor,rightEyeAnchor].enumerated() {
            f.eyes[i].x += anchor.x - (i == 0 ? 86 : 154)
            f.eyes[i].y += anchor.y - 126
        }
        return f
    }
    static let robot = Self(id:"cx-robot",version:1,title:"机器人",geometry:.cxRobot,
                            leftEyeAnchor:CGPoint(x:86,y:126),rightEyeAnchor:CGPoint(x:154,y:126),
                            antennaAnchor:CGPoint(x:120,y:12),antennaRadius:15,drawingMargin:40,
                            capabilities:[.antenna,.hearts,.squeeze])
}

enum BotAvatarTemplateRegistry {
    static let templates = [BotAvatarTemplate.robot]
    static func resolve(id: String, version: Int) -> BotAvatarTemplate? {
        templates.first { $0.id == id && $0.version == version }
    }
}
