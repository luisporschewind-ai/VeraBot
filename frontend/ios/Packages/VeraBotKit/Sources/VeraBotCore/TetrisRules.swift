import Foundation

enum TetrisRules {
    static let version = "vera-tetris-2"
    // Custom clockwise kick order, with rows increasing downward. This is not SRS.
    static let kicks = [(0,0),(-1,0),(1,0),(-2,0),(2,0),(0,-1),(-1,-1),(1,-1),(0,-2)]

    static func cells(kind: TetrisKind, rotation: Int, version: String) -> [TetrisCell] {
        guard version == Self.version else { return kind.cells(rotation: rotation) }
        let base = kind.cells(rotation: 0)
        guard kind != .yellow else { return base }
        let axis = kind == .cyan ? 3 : 2
        return (0..<rotation).reduce(base) { cells, _ in
            cells.map { .init(column: axis - $0.row, row: $0.column) }
        }
    }

    private static func random(_ state: inout TetrisState) -> UInt32 {
        var value = state.rngState
        value ^= value << 13; value ^= value >> 17; value ^= value << 5
        state.rngState = value
        return value
    }

    private static func uniform(_ count: Int, state: inout TetrisState) -> Int {
        let space = UInt64(UInt32.max) + 1
        let limit = space - space % UInt64(count)
        var value = UInt64(random(&state))
        while value >= limit { value = UInt64(random(&state)) }
        return Int(value % UInt64(count))
    }

    static func draw(_ state: inout TetrisState) -> TetrisKind {
        guard state.ruleVersion == version else {
            return TetrisKind(rawValue: uniform(7, state: &state) + 1)!
        }
        if state.bag.isEmpty {
            state.bag = TetrisKind.allCases
            for index in stride(from: 6, through: 1, by: -1) {
                let other = uniform(index + 1, state: &state)
                state.bag.swapAt(index, other)
            }
        }
        return state.bag.removeFirst()
    }
}
