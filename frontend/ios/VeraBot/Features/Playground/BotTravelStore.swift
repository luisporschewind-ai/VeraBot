import Foundation
import Observation
import VeraBotCore

enum BotTravelStage: Int, CaseIterable, Codable, Identifiable {
    case departed
    case clue
    case discovery
    case returned

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .departed: "出发"
        case .clue: "途中线索"
        case .discovery: "地点发现"
        case .returned: "归来"
        }
    }

    static func stage(startedAt: Date, duration: TimeInterval, now: Date) -> BotTravelStage {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        if elapsed >= duration { return .returned }
        if elapsed >= duration * 0.6 { return .discovery }
        if elapsed >= duration * 0.2 { return .clue }
        return .departed
    }
}

struct BotTravelDestination: Identifiable, Hashable {
    let id: String
    let city: String
    let region: String
    let symbol: String
    let themes: [String]
    let factTitle: String
    let fact: String
    let sourceTitle: String
    let sourceURL: URL
    let clue: String
    let keepsakeName: String
    let keepsakeSymbol: String
    let keepsakeStory: String
    let imagination: String

    static let all: [BotTravelDestination] = [
        .init(id: "beijing", city: "北京", region: "中国 · 北京", symbol: "building.2", themes: ["胡同与街巷", "城市历史", "慢慢散步"], factTitle: "胡同里的城市记忆", fact: "北京市政府的城市文化介绍将胡同视为北京历史风貌的一部分，并介绍了砖塔胡同、烟袋斜街等老街巷。", sourceTitle: "北京市政府 · 胡同漫步", sourceURL: URL(string: "https://english.beijing.gov.cn/beijinginfo/culture/202005/t20200515_1898145.html")!, clue: "前面有一条老巷，名字里藏着它走过的时间。", keepsakeName: "胡同门环", keepsakeSymbol: "door.left.hand.closed", keepsakeStory: "把老街巷的门环做成一张小小纪念卡。", imagination: "我沿着灰砖墙慢慢走，觉得每个转角都像藏着一段刚要开口的故事。"),
        .init(id: "suzhou", city: "苏州", region: "中国 · 江苏", symbol: "leaf", themes: ["古典园林", "园林里的水景", "建筑与造景"], factTitle: "园林里的水与空间", fact: "苏州市政府介绍的苏州古典园林中，多座园林被列入世界文化遗产名录；园林借助水面、廊道和庭院组织空间。", sourceTitle: "苏州市政府 · Classical Gardens", sourceURL: URL(string: "https://english.suzhou.gov.cn/szsenglish/sjwhyclm/202106/1ef7f477b0b04108b7c8c4f6481732c1.shtml")!, clue: "我看到一片水面，周围的廊和亭像把视线轻轻引向别处。", keepsakeName: "园林花窗", keepsakeSymbol: "squareshape.split.2x2", keepsakeStory: "一扇花窗，把园林的一角留在相册里。", imagination: "我在回廊边停了一会儿，觉得这里的路不是把人带到终点，而是让人多看几眼。"),
        .init(id: "chengdu", city: "成都", region: "中国 · 四川", symbol: "pawprint", themes: ["自然与大熊猫", "动物保护", "慢生活"], factTitle: "从科研到科普", fact: "成都大熊猫繁育研究基地开展大熊猫等珍稀野生动物保护、科研繁育和科普教育工作。", sourceTitle: "成都大熊猫繁育研究基地", sourceURL: URL(string: "https://www.panda.org.cn/en/")!, clue: "这趟旅程遇见了一位黑白相间的特别邻居。", keepsakeName: "竹叶书签", keepsakeSymbol: "bookmark", keepsakeStory: "一枚竹叶形书签，记下这次关于熊猫与保护的发现。", imagination: "我想象自己在竹林边放轻脚步，远远看一眼，再把安静留给这里的居民。"),
        .init(id: "kyoto", city: "京都", region: "日本 · 京都府", symbol: "house.lodge", themes: ["建筑与传统", "寺社与街区", "京都日常"], factTitle: "一座延续千年的古都", fact: "京都市官方旅游指南介绍，京都自公元 794 年起作为日本首都超过一千年，长期历史塑造了当地的文化与城市风貌。", sourceTitle: "京都市官方旅游指南 · About Kyoto", sourceURL: URL(string: "https://kyoto.travel/en/about_kyoto.html")!, clue: "我经过一片老街区，木色的房子和安静的路交错在一起。", keepsakeName: "町家屋檐", keepsakeSymbol: "house", keepsakeStory: "把京都街巷里的木屋檐线条，收进一张纪念卡。", imagination: "我喜欢这段路不急着展示什么，走慢一点，日常的细节就自己浮现出来。"),
        .init(id: "paris", city: "巴黎", region: "法国 · 法兰西岛", symbol: "water.waves", themes: ["塞纳河岸", "城市建筑", "河边散步"], factTitle: "沿河读城市", fact: "巴黎旅游局的塞纳河步行路线介绍，城市发展的历史可以沿着塞纳河两岸观察，路线串起河岸与建筑景观。", sourceTitle: "Paris je t'aime · Seine riverside walk", sourceURL: URL(string: "https://parisjetaime.com/eng/article/paris-river-seine-a921")!, clue: "河面把两岸连在一起，也把不同年代的城市风景串起来。", keepsakeName: "塞纳河小船", keepsakeSymbol: "sailboat", keepsakeStory: "一只沿河的小船，带回这次河岸漫步的记忆。", imagination: "我靠着河边看了一会儿，觉得城市的故事好像就藏在一座桥接到另一座桥之间。"),
        .init(id: "istanbul", city: "伊斯坦布尔", region: "土耳其 · 伊斯坦布尔", symbol: "globe.europe.africa", themes: ["历史街区", "建筑与城市", "博斯普鲁斯海峡"], factTitle: "多段历史交织的街区", fact: "联合国教科文组织列出的伊斯坦布尔历史区域包含考古公园、苏莱曼尼耶、泽雷克及城墙等组成区域，呈现不同时期的建筑遗产。", sourceTitle: "UNESCO · Historic Areas of Istanbul", sourceURL: URL(string: "https://whc.unesco.org/en/list/356")!, clue: "我在几段不同年代留下的街区之间，发现了城市层层叠起的样子。", keepsakeName: "城墙纹样", keepsakeSymbol: "circle.hexagongrid", keepsakeStory: "把历史城墙的轮廓和砖石纹理，留作这次旅行的纪念。", imagination: "我沿着旧城的边缘慢慢走，觉得时间并没有排成一条直线，而是住在彼此相邻的街区里。")
    ]

    static func find(_ id: String) -> BotTravelDestination? { all.first { $0.id == id } }
}

struct BotTravelTrip: Codable, Identifiable, Hashable {
    let id: UUID
    let botID: Int
    let botName: String
    let botAvatar: String
    let destinationID: String
    let theme: String
    let note: String
    let startedAt: Date
    let duration: TimeInterval

    var destination: BotTravelDestination? { BotTravelDestination.find(destinationID) }
    func stage(at now: Date) -> BotTravelStage { BotTravelStage.stage(startedAt: startedAt, duration: duration, now: now) }
    func progress(at now: Date) -> Double { min(1, max(0, now.timeIntervalSince(startedAt) / duration)) }
    func remaining(at now: Date) -> TimeInterval { max(0, duration - now.timeIntervalSince(startedAt)) }
}

@MainActor @Observable
final class BotTravelStore {
    static let testDuration: TimeInterval = 5 * 60
    private(set) var trips: [BotTravelTrip] = []
    private(set) var userID: Int?
    var now = Date()

    func configure(userID: Int?) {
        guard self.userID != userID else { refresh(); return }
        self.userID = userID
        guard let userID else { trips = []; now = Date(); return }
        let key = Self.storageKey(userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([BotTravelTrip].self, from: data) else {
            trips = []
            now = Date()
            return
        }
        trips = saved.sorted { $0.startedAt > $1.startedAt }
        now = Date()
    }

    func refresh() { now = Date() }

    func activeTrip(botID: Int, at date: Date? = nil) -> BotTravelTrip? {
        let instant = date ?? now
        return trips.first { $0.botID == botID && $0.stage(at: instant) != .returned }
    }

    func startTrip(bot: Bot, destinationID: String, theme: String, note: String) throws -> BotTravelTrip {
        guard let userID else { throw BotTravelStoreError.accountUnavailable }
        guard activeTrip(botID: bot.id) == nil else { throw BotTravelStoreError.botAlreadyTraveling }
        guard BotTravelDestination.find(destinationID) != nil else { throw BotTravelStoreError.destinationUnavailable }
        let trip = BotTravelTrip(id: UUID(), botID: bot.id, botName: bot.name, botAvatar: bot.avatar,
                                 destinationID: destinationID, theme: theme,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                 startedAt: Date(), duration: Self.testDuration)
        trips.insert(trip, at: 0)
        persist(for: userID)
        refresh()
        return trip
    }

    func deleteTrip(id: UUID) {
        trips.removeAll { $0.id == id }
        if let userID { persist(for: userID) }
    }

    private func persist(for userID: Int) {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey(userID))
    }

    private static func storageKey(_ userID: Int) -> String { "verabot.bot-travel.v1.user.\(userID)" }
}

enum BotTravelStoreError: LocalizedError {
    case accountUnavailable
    case botAlreadyTraveling
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .accountUnavailable: "账号信息还没准备好，请稍后再试。"
        case .botAlreadyTraveling: "这位 Bot 还在旅途中，等它回来再开始下一趟吧。"
        case .destinationUnavailable: "这个目的地暂时不可用，请重新选择。"
        }
    }
}
