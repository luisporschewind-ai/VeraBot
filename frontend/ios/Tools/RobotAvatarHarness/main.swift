import Foundation
@main struct Harness {
    static var failures = 0
    static var checks = 0
    static func expect(_ value: Bool, _ name: String) {
        checks += 1
        if !value { failures += 1; print("FAIL",name) }
    }
    static func main() {
        let original = ["idle","bored","waiting","waiting-wrap","input","send","success","failure","warning","inspect","blocked","error","surprise","sleep","wake","love","random"]
        expect(Array(RobotAvatarAction.allCases.prefix(17)).map(\.rawValue) == original,"original action order")
        expect(RobotAvatarAction.allCases.count == 23,"all 23 states exist")
        let newIDs = ["thinking","recalling","working","delegating","replying","awaiting-confirmation"]
        let work = newIDs.compactMap(RobotAvatarAction.init(rawValue:))
        expect(work.count == 6,"all six work states selectable")
        #if AVATAR_SYSTEM
        let periods=[2400.0,2800,1800,2400,1200,2400]
        for (index,state) in work.enumerated() {
            expect(state.continuous && RobotAvatarMotion.duration(state).isInfinite,"work stays active")
            expect(RobotAvatarMotion.demoDuration(state) == 4800,"demo observes work state")
            let period=periods[index]
            for t in stride(from:0.0,through:60000.0,by:17) {
                let f=RobotAvatarMotion.sample(state,ms:t)
                expect(f.eyes.allSatisfy { [$0.x,$0.y,$0.width,$0.height].allSatisfy(\.isFinite) && $0.width>=0 && $0.height>=0 },"finite work geometry")
                let still=RobotAvatarMotion.sample(state,ms:t,reduced:true)
                expect(still.antennaOpacity == 1 && still.headRotation == 0,"reduced motion stable")
            }
            let before=RobotAvatarMotion.sample(state,ms:200+period-0.01)
            let after=RobotAvatarMotion.sample(state,ms:200+period+0.01)
            let next=RobotAvatarMotion.sample(state,ms:200+period+0.02)
            let earlier=RobotAvatarMotion.sample(state,ms:200+period-0.02)
            for i in 0..<2 {
                expect(abs(before.eyes[i].x-after.eyes[i].x)<0.05 && abs(before.eyes[i].y-after.eyes[i].y)<0.05,"seamless cycle position")
                expect(abs((before.eyes[i].x-earlier.eyes[i].x)/0.01 - (next.eyes[i].x-after.eyes[i].x)/0.01)<0.01,"seamless cycle velocity")
            }
            expect(abs(before.antennaOffsetY-after.antennaOffsetY)<0.05,"antenna cycle matches head")
        }
        #endif
        #if AVATAR_SYSTEM
        let previousPose = RobotAvatarMotion.sample(.love,ms:1000)
        let workPose = RobotAvatarMotion.sample(.thinking,ms:200)
        let entryStart = BotAvatarWorkMotion.enter(from:previousPose,to:workPose,ms:0)
        let entryEnd = BotAvatarWorkMotion.enter(from:previousPose,to:workPose,ms:200)
        expect(entryStart.eyes[0].heart == previousPose.eyes[0].heart && entryStart.headY == previousPose.headY,"work entry begins from visible pose")
        expect(entryEnd.eyes[0].heart == workPose.eyes[0].heart && entryEnd.headY == workPose.headY,"work entry reaches current timeline at 200ms")
        var playback = BotAvatarLabPlayback()
        playback.start(.all, current: .love)
        let oldSerial = playback.serial
        expect(playback.sequence == BotAvatarState.allCases, "full playback covers 23 states")
        expect(playback.holdMS(.thinking) == 4800 && playback.holdMS(.send) == RobotAvatarMotion.duration(.send) + 800, "playback holds match descriptors")
        playback.stop()
        expect(playback.serial != oldSerial && playback.mode == .none, "stop invalidates previous playback")
        playback.start(.transitions, current: .idle)
        expect(playback.sequence == [.thinking,.working,.delegating,.replying,.awaitingConfirmation,.success,.idle], "transition sequence")
        playback.start(.currentLoop, current: .love)
        expect(playback.sequence == [.love], "current loop preserves selected state")
        #endif
        let flash:[(String,Double)]=[("input",1000),("send",900),("success",950),("warning",900),("blocked",800),("error",700),("surprise",700)]
        for (name,time) in flash { if let action=RobotAvatarAction(rawValue:name) { expect(RobotAvatarMotion.sample(action,ms:time).antennaOpacity == 0,"original antenna off window") } }
        for action in RobotAvatarAction.allCases {
            expect(RobotAvatarMotion.demoDuration(action).isFinite,"finite demo duration")
            for t in stride(from:0.0,through:12000.0,by:16) {
                let f=RobotAvatarMotion.sample(action,ms:t)
                expect(f.eyes.allSatisfy { [$0.x,$0.y,$0.width,$0.height,$0.scaleX,$0.scaleY].allSatisfy(\.isFinite) && $0.width>=0 && $0.height>=0 },"all finite geometry")
            }
        }
        expect(RobotAvatarMotion.sample(.send,ms:650).eyes[0].y==37 && RobotAvatarMotion.sample(.send,ms:950).eyes[0].y==37,"two nods preserved")
        expect(RobotAvatarMotion.sample(.love,ms:1000).eyes.allSatisfy{$0.heart==1},"double hearts preserved")
        expect(RobotAvatarMotion.sample(.success,ms:880).antennaOpacity == 1,"preserve baseline flash boundary precision")
        for (point,delta) in [(CGPoint(x:120,y:120),CGSize.zero),
                              (CGPoint(x:200,y:120),CGSize(width:50,height:25)),
                              (CGPoint(x:120,y:12),CGSize(width:30,height:-15))] {
            var reducedGesture = RobotAvatarInteraction()
            reducedGesture.begin(at:point,size:160,antenna:CGPoint(x:120,y:12),antennaVisible:true,reduced:true)
            reducedGesture.move(translation:delta,reduced:true)
            expect(reducedGesture.overridesAction,"reduced gesture gives static feedback while held")
            _ = reducedGesture.end(reduced:true)
            // No subsequent tick exists when Reduce Motion disables the view's clock.
            expect(reducedGesture.kind == .none && !reducedGesture.overridesAction && reducedGesture.reaction == nil,
                   "reduced gesture release restores selected static expression without a tick")
        }
        for center in [false,true] {
            var fx=RobotAvatarInteraction()
            let point=center ? CGPoint(x:120,y:120) : CGPoint(x:120,y:12)
            fx.begin(at:point,size:160,antenna:CGPoint(x:120,y:12),antennaVisible:true,reduced:false)
            if !center { fx.move(translation:CGSize(width:30,height:15),reduced:false) }
            for _ in 0..<40 { fx.advance(dt:1.0/60,reduced:false) }
            _=fx.end(reduced:false)
            for _ in 0..<600 { fx.advance(dt:1.0/60,reduced:false) }
            expect(fx.kind == .none && !fx.overridesAction,"released interaction restores current state")
        }
        #if AVATAR_TEMPLATE
        var custom = BotAvatarTemplate.robot
        custom.leftEyeAnchor = CGPoint(x:80,y:130)
        custom.rightEyeAnchor = CGPoint(x:160,y:130)
        let adapted=custom.adapt(RobotAvatarMotion.Frame())
        expect(adapted.eyes[0].x == -40 && adapted.eyes[1].x == 40 && adapted.eyes[0].y == 10,"custom template eye anchors used")
        expect(BotAvatarTemplateRegistry.resolve(id:"cx-robot",version:1) != nil && BotAvatarTemplateRegistry.resolve(id:"unknown",version:1) == nil,"unknown templates remain unsupported")
        #endif
        let directions: [CGSize] = [.init(width:100,height:0),.init(width:-100,height:0),.init(width:0,height:100),.init(width:0,height:-100),.init(width:100,height:100),.init(width:-100,height:100),.init(width:100,height:-100),.init(width:-100,height:-100)]
        for size in [32.0,44,96,160] {
            for delta in directions {
                var head = RobotAvatarInteraction()
                let home = CGPoint(x:120,y:12), hot = CGPoint(x:200,y:125)
                head.begin(at:hot,size:size,antenna:home,antennaVisible:true,reduced:false)
                head.move(translation:delta,reduced:false)
                for _ in 0..<24 { head.advance(dt:1.0/60,reduced:false) }
                let near = head.deformation(at:hot), far = head.deformation(at:CGPoint(x:35,y:125))
                expect(hypot(near.x,near.y)>8 && hypot(near.x,near.y)>hypot(far.x,far.y)*3,"eight-direction local head deformation")
                _ = head.end(reduced:false)
                for _ in 0..<600 { head.advance(dt:1.0/60,reduced:false) }
                expect(head.kind == .none && !head.overridesAction,"head release restores current state at all sizes")
                var ant = RobotAvatarInteraction()
                ant.begin(at:home,size:size,antenna:home,antennaVisible:true,reduced:false)
                ant.move(translation:delta,reduced:false)
                for _ in 0..<6 { ant.advance(dt:1.0/60,reduced:false) }
                expect(ant.kind == .antenna && hypot(ant.x.position,ant.y.position)>hypot(ant.headX.position,ant.headY.position)*2,"antenna leads head follower")
                _ = ant.end(reduced:false)
                for _ in 0..<600 {
                    ant.advance(dt:1.0/60,reduced:false)
                    let dot = CGPoint(x:home.x+ant.x.position,y:home.y+ant.y.position)
                    expect(dot.x-16 >= -40 && dot.y-16 >= -40 && dot.x+16 <= 280 && dot.y+16 <= 280,"full antenna stays within canvas")
                }
                expect(ant.kind == .none && !ant.overridesAction,"antenna release restores current state at all sizes")
            }
        }
        for state in RobotAvatarAction.allCases {
            for pull in [(0.0,0.0),(-22.0,-18.0),(22.0,-18.0),(-22.0,18.0),(22.0,18.0)] {
                var x = 120.0, y = 12.0, vx = 0.0, vy = 0.0
                let dt = 1.0/60
                for i in 0..<720 {
                    let frame = RobotAvatarMotion.sample(state,ms:Double(i)*1000*dt)
                    let px = i<180 ? pull.0 : 0, py = i<180 ? pull.1 : 0
                    let angle = (frame.headRotation+px*0.18)*Double.pi/180
                    let sx = frame.antennaOffsetX*frame.headScale
                    let sy = (-108+frame.antennaOffsetY)*frame.headScale*(1-hypot(px,py)/180*0.5)
                    let tx = 120+frame.headX+px*0.28+sx*cos(angle)-sy*sin(angle)
                    let ty = 120+frame.headY+py*0.3+sx*sin(angle)+sy*cos(angle)
                    vx += ((tx-x)*180-vx*5.6)*dt; vy += ((ty-y)*180-vy*5.6)*dt
                    x += vx*dt; y += vy*dt
                    expect(x-15 >= -40 && y-15 >= -40 && x+15 <= 280 && y+15 <= 280,"all states full antenna bounds including work offsets")
                }
            }
        }
        print("RobotAvatarHarness: \(checks-failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
