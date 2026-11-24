enum Decision: Equatable {
    case stay
    case connect(String)
}

/// 다음에 연결할 네트워크를 고른다.
/// - priority: 앞쪽일수록 우선. 셀룰러(핫스팟)는 맨 뒤.
/// - cooling: 최근 인터넷 불통·연결 실패로 잠시 제외된 SSID.
func decide(current: String?, online: Bool, visible: Set<String>, priority: [String], cooling: Set<String>) -> Decision {
    guard let bestRank = priority.firstIndex(where: { visible.contains($0) && !cooling.contains($0) }) else {
        return .stay
    }
    let best = priority[bestRank]
    if current == best { return .stay }
    if online, let current, let currentRank = priority.firstIndex(of: current), currentRank < bestRank {
        return .stay
    }
    return .connect(best)
}
