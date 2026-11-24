import Foundation

/// 한 시점의 연결 상태. rawValue가 클수록 나쁜 상태.
enum LinkState: Int, Comparable {
    case wifi, cellular, offline

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 최근 60분을 1분 단위로 기록한다. 한 분 안에서는 가장 나빴던 상태를 남긴다.
/// ponytail: 메모리에만 보관 — 앱을 다시 켜면 비워진다. 장기 기록이 필요하면 파일 저장 추가.
struct ConnectionHistory {
    struct Minute {
        var state: LinkState
        var downSeconds: Double = 0
        var switches = 0
    }

    static let window = 60
    private var minutes: [Int: Minute] = [:]

    mutating func record(_ state: LinkState, at date: Date, elapsed: TimeInterval, switched: Bool) {
        let key = Self.minuteKey(date)
        var minute = minutes[key] ?? Minute(state: state)
        minute.state = max(minute.state, state)
        if state == .offline { minute.downSeconds += elapsed }
        if switched { minute.switches += 1 }
        minutes[key] = minute
        minutes = minutes.filter { $0.key > key - Self.window }
    }

    /// 오래된 것부터 60칸. 기록이 없는 분(앱 꺼짐·잠자기)은 nil.
    func slots(now: Date) -> [LinkState?] {
        let key = Self.minuteKey(now)
        return ((key - Self.window + 1)...key).map { minutes[$0]?.state }
    }

    func switches(now: Date) -> Int { recent(now).reduce(0) { $0 + $1.switches } }
    func downSeconds(now: Date) -> Double { recent(now).reduce(0) { $0 + $1.downSeconds } }

    private func recent(_ now: Date) -> [Minute] {
        let key = Self.minuteKey(now)
        return minutes.filter { $0.key > key - Self.window }.map(\.value)
    }

    private static func minuteKey(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 60) }
}
