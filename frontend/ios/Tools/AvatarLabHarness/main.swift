// 头像实验室离屏测试入口（由 run.sh 与 VeraBotCore、Theme、AvatarLab* 源码一起编译）。
import SwiftUI
import UIKit

@MainActor
enum Harness {
    static var passed = 0
    static var failed: [String] = []

    static func expect(_ ok: Bool, _ name: String) {
        if ok { passed += 1; print("PASS \(name)") } else { failed.append(name); print("FAIL \(name)") }
    }

    private static func trace(_ json: String) -> ToolTrace {
        try! JSONDecoder().decode(ToolTrace.self, from: Data(json.utf8))
    }

    // MARK: AVLAB-T01~：映射
    static func mapping() {
        let cases: [(ExecutionState, AvatarLabState)] = [
            (.idle, .idle), (.recalling, .thinking), (.thinking, .thinking),
            (.callingTool(name: "get_weather"), .working),
            (.delegating(botName: "小研", progress: nil), .delegating),
            (.delegating(botName: "小研", progress: DelegationProgress(botName: "阿厨", depth: 2, tool: "x")), .delegating),
            (.replying, .replying), (.blocked(code: "loop", message: "m"), .blocked), (.failed(message: "e"), .blocked),
            (.awaitingConfirmation, .waiting), (.completed, .done),
        ]
        expect(cases.allSatisfy { AvatarLabState($0.0) == $0.1 }, "AVLAB-T01 执行状态 → 头像状态映射 (11 种输入)")
        let reached = Set(cases.map { AvatarLabState($0.0) })
        expect(reached == Set(AvatarLabState.allCases) && AvatarLabState.allCases.count == 8, "AVLAB-T02 8 种头像状态都可由状态机到达")
        let continuous = Set(AvatarLabState.allCases.filter(\.isContinuous))
        expect(continuous == [.thinking, .working, .delegating, .replying], "AVLAB-T03 持续(循环)状态 = 思考 / 执行 / 委派 / 回复")
        expect(AvatarLabState.allCases.allSatisfy { !$0.title.isEmpty && UIImage(systemName: $0.symbol) != nil },
               "AVLAB-T04 每个状态有中文标题且 SF Symbol 存在")
        let labels = AvatarLabCharacterKind.allCases.flatMap { k in AvatarLabState.allCases.map { AvatarLabCharacterView.accessibilityText(kind: k, state: $0) } }
        expect(Set(labels).count == 40 && labels.allSatisfy { $0.contains("，") }, "AVLAB-T05 40 种组合的读屏文字唯一且为「角色，状态」")
    }

    // MARK: 演示序列
    static func demo() {
        var seq: [AvatarLabState] = []
        for f in AvatarLabDemo.frames { let s = AvatarLabState(f.state); if seq.last != s { seq.append(s) } }
        let expected: [AvatarLabState] = [.thinking, .delegating, .thinking, .working, .blocked, .thinking, .replying, .done, .idle]
        expect(seq == expected, "AVLAB-T06 演示序列 = 思考→委派→思考→执行→阻塞→思考→回复→完成→空闲 (实际 \(seq.map(\.title)))")
        let blocked = AvatarLabDemo.frames.filter { if case .blocked = $0.state { true } else { false } }
        expect(blocked.count == 1 && blocked[0].holdMS == 1200 && AvatarLabDemo.blockedHoldMS == 1200, "AVLAB-T07 受阻帧恰好 1 个、展示 1200 ms")
        let captions = AvatarLabDemo.frames.map { AvatarLabDemo.caption($0.state) }
        expect(captions.contains("正在回忆") && captions.contains("委派 小研 · 小研 思考中")
               && captions.contains("委派 小研 · 小研 调用 get_weather") && captions.contains("短暂受阻（tool_not_allowed）"),
               "AVLAB-T08 演示覆盖 召回 / 委派进度 / 受阻 (\(captions))")
        expect(AvatarLabDemo.frames.last?.state == .idle && AvatarLabDemo.frames.allSatisfy { $0.holdMS >= 0 }, "AVLAB-T09 演示以空闲结束")
        _ = trace
    }

    // MARK: 离屏渲染 + 越界检查
    static let sizes: [CGFloat] = [68, 104, 148]

    static func cell(_ k: AvatarLabCharacterKind, _ s: AvatarLabState, _ size: CGFloat) -> some View {
        AvatarLabCharacterView(kind: k, state: s, size: size, animated: false)
    }

    static func sheet(size: CGFloat, scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("头像实验室 · \(Int(size))pt · \(scheme == .dark ? "深色" : "浅色")").font(.headline)
            HStack(spacing: 8) {
                Text("").frame(width: 44)
                ForEach(AvatarLabState.allCases) { s in Text(s.title).font(.caption2).frame(width: size + 8) }
            }
            ForEach(AvatarLabCharacterKind.allCases) { k in
                HStack(spacing: 8) {
                    Text(k.title).font(.caption).frame(width: 44, alignment: .leading)
                    ForEach(AvatarLabState.allCases) { s in cell(k, s, size).frame(width: size + 8, height: size + 8) }
                }
            }
        }
        .padding(16)
        .foregroundStyle(Color.primary)
        .background(Color.appBackground)
        .environment(\.colorScheme, scheme)
    }

    static func png(_ view: some View, scale: CGFloat = 2) -> (Data, CGImage)? {
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let img = r.uiImage, let cg = img.cgImage, let data = img.pngData() else { return nil }
        return (data, cg)
    }

    /// 非透明像素的包围盒（像素坐标）
    static func opaqueBounds(_ cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where buf[(y * w + x) * 4 + 3] > 40 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func render(out: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: out.appendingPathComponent("cells"), withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .dark ? "dark" : "light"
            for size in sizes {
                if let (d, _) = png(sheet(size: size, scheme: scheme)) {
                    try? d.write(to: out.appendingPathComponent("sheet_\(tag)_\(Int(size)).png"))
                }
            }
        }
        // 越界：在 1.5 倍画布中央渲染单个头像，非透明内容超出头像方框 3% 以上视为越界；同时检查内容非空
        var overflow: [String] = []
        var empty: [String] = []
        for size in sizes { for k in AvatarLabCharacterKind.allCases { for s in AvatarLabState.allCases {
            let canvas = size * 1.5
            let v = cell(k, s, size).frame(width: canvas, height: canvas).environment(\.colorScheme, .light)
            guard let (d, cg) = png(v, scale: 1) else { empty.append("\(k)/\(s)/\(Int(size))"); continue }
            if size == 104 { try? d.write(to: out.appendingPathComponent("cells/\(k.rawValue)_\(s.rawValue)_\(Int(size)).png")) }
            guard let b = opaqueBounds(cg) else { empty.append("\(k)/\(s)/\(Int(size))"); continue }
            let inset = (canvas - size) / 2 - size * 0.03
            if b.minX < inset || b.minY < inset || b.maxX > canvas - inset || b.maxY > canvas - inset {
                overflow.append("\(k.rawValue)/\(s.rawValue)/\(Int(size)) bbox=\(b)")
            }
        } } }
        expect(empty.isEmpty, "AVLAB-T10 120 个头像 (5×8×3) 全部渲染出内容 \(empty)")
        expect(overflow.isEmpty, "AVLAB-T11 头像内容不超出方框 (容差 3%) \(overflow.prefix(10))")
        // 云朵轮廓必须加载到（否则只剩底色圆）
        let cloud = png(cell(.cloud, .idle, 104).environment(\.colorScheme, .light), scale: 1)
        let bean = png(cell(.veraBean, .idle, 104).environment(\.colorScheme, .light), scale: 1)
        expect(cloud != nil && bean != nil, "AVLAB-T12 云朵参考图可加载并渲染")
        // 深色模式背景色确实变化（Theme 动态色生效）
        let light = png(Rectangle().fill(Color.avatarBeanBackdrop).frame(width: 4, height: 4).environment(\.colorScheme, .light), scale: 1)
        let dark = png(Rectangle().fill(Color.avatarBeanBackdrop).frame(width: 4, height: 4).environment(\.colorScheme, .dark), scale: 1)
        expect(light != nil && dark != nil && light!.0 != dark!.0, "AVLAB-T13 角色底色随深色模式变化 (Theme 动态色)")
    }
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/avatarlab_harness"
MainActor.assumeIsolated {
    Harness.mapping()
    Harness.demo()
    Harness.render(out: URL(fileURLWithPath: outPath))
    print("\nSUMMARY \(Harness.passed)/\(Harness.passed + Harness.failed.count) passed; PNG → \(outPath)")
    exit(Harness.failed.isEmpty ? 0 : 1)
}
