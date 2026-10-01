import Foundation

public enum IdleStatePolicy {
    public static func state(idleDuration: TimeInterval, localHour: Int) -> AvatarStateID {
        let duration = max(0, idleDuration)
        let isNight = localHour >= 23 || localHour < 6

        if isNight {
            if duration < 30 { return .resting }
            if duration < 120 { return .goodnight }
            return .dreaming
        }

        if duration < 30 { return .resting }
        if duration < 120 { return .idle }
        if duration < 300 { return .staringAtOwner }
        return .daydreamingHearts
    }
}
