import Foundation

public enum ToolClassifier {
    public static func classify(toolName: String) -> AvatarStateID {
        let value = toolName.lowercased()

        if containsAny(value, keywords: flightKeywords) {
            return .checkingFlights
        }
        if containsAny(value, keywords: hotelKeywords) {
            return .bookingHotel
        }
        if containsAny(value, keywords: travelKeywords) {
            return .travel
        }
        if containsAny(value, keywords: calendarKeywords) {
            return .calendar
        }
        if containsAny(value, keywords: shoppingKeywords) {
            return .shopping
        }
        if containsAny(value, keywords: foodKeywords) {
            return .foodOrdering
        }
        if containsAny(value, keywords: meetingKeywords) {
            return .meeting
        }
        if containsAny(value, keywords: codeKeywords) {
            return .coding
        }
        if containsAny(value, keywords: fileKeywords) {
            return .findingFiles
        }
        if containsAny(value, keywords: researchKeywords) {
            return .researching
        }
        return .working
    }

    private static func containsAny(_ value: String, keywords: [String]) -> Bool {
        keywords.contains { value.contains($0) }
    }

    private static let flightKeywords = [
        "flight", "airline", "airfare", "airport", "aviation", "skyscanner",
        "trip.com", "ctrip", "航班", "机票", "机场",
    ]

    private static let shoppingKeywords = [
        "shop", "cart", "checkout", "purchase", "commerce", "product", "amazon",
        "taobao", "tmall", "jd.com", "pinduoduo", "购物", "商品", "下单", "比价",
    ]

    private static let hotelKeywords = [
        "hotel", "lodging", "booking.com", "airbnb", "酒店", "住宿",
    ]

    private static let travelKeywords = [
        "itinerary", "travel", "trip_plan", "maps", "行程", "旅行", "攻略",
    ]

    private static let calendarKeywords = [
        "calendar", "schedule", "event.create", "日历", "日程",
    ]

    private static let foodKeywords = [
        "restaurant", "food", "meal", "delivery", "doordash", "外卖", "点餐", "餐厅",
    ]

    private static let meetingKeywords = [
        "meeting", "zoom", "teams", "email", "mail", "会议", "邮件",
    ]

    private static let codeKeywords = [
        "terminal", "shell", "exec", "command", "code", "compile", "build", "test", "git",
    ]

    private static let fileKeywords = [
        "file", "folder", "filesystem", "read_file", "write_file", "glob", "find", "文件", "目录",
    ]

    private static let researchKeywords = [
        "browser", "browse", "search", "research", "web", "fetch", "crawl", "scrape",
        "read_url", "perplexity", "google", "bing", "搜索", "查找", "资料", "网页",
    ]
}
