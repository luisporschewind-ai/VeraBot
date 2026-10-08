import Foundation
@main struct Samples {
 static func main() {
  for action in RobotAvatarAction.allCases.prefix(17) {
   print(action.rawValue,RobotAvatarMotion.duration(action),RobotAvatarMotion.demoDuration(action))
   for reduced in [false,true] {
    for t in stride(from:0.0,through:12000.0,by:16) {
     let f=RobotAvatarMotion.sample(action,ms:t,reduced:reduced)
     print([f.headX,f.headY,f.headScale,f.headRotation,f.antennaOpacity])
     for e in f.eyes { print([e.x,e.y,e.width,e.height,e.top,e.bottom,e.topAngle,e.bottomAngle,e.scaleX,e.scaleY,e.opacity,e.cursor,e.heart]) }
    }
   }
  }
 }
}
