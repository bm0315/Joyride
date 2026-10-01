import Foundation

public enum ToolClassifier {
    public static func classify(toolName: String) -> AvatarStateID {
        let value = toolName.lowercased()

        if containsAny(value, keywords: flightKeywords) {
            return .checkingFlights
        }
        if containsAny(value, keywords: shoppingKeywords) {
            return .shopping
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

    private static let researchKeywords = [
        "browser", "browse", "search", "research", "web", "fetch", "crawl", "scrape",
        "read_url", "perplexity", "google", "bing", "搜索", "查找", "资料", "网页",
    ]
}
