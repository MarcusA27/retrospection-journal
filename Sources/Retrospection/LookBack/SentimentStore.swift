import Foundation

/// One day's sentiment score, read from the journal's sentiment.json (written by Scripts/sentiment.py).
struct SentimentPoint: Identifiable, Hashable {
    let date: String   // YYYY-MM-DD logical day
    let score: Double  // average VADER compound of the user's messages that day (~ -1…1)
    let n: Int         // how many messages backed the score (low n = noisy)
    var id: String { date }
}

enum SentimentStore {
    static func load() -> [SentimentPoint] {
        let url = JournalStore.journalDirectory().appendingPathComponent("sentiment.json")
        guard let data = try? Data(contentsOf: url),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return raw.compactMap { d -> SentimentPoint? in
            guard let date = d["date"] as? String,
                  let score = (d["score"] as? NSNumber)?.doubleValue else { return nil }
            return SentimentPoint(date: date, score: score, n: (d["n"] as? NSNumber)?.intValue ?? 0)
        }.sorted { $0.date < $1.date }
    }
}
