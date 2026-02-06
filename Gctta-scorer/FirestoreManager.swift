import SwiftUI
import FirebaseFirestore
import Combine
// MARK: - SHARED MODELS

struct Player: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var name: String
    var active: Bool
    var isProvisional: Bool?
}

struct Fixture: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var table: String
    var date: String
    var homeTeam: String
    var awayTeam: String
    var division: String
    
    enum CodingKeys: String, CodingKey {
        case id, table, date, division
        case homeTeam = "home_team"
        case awayTeam = "away_team"
    }
}

struct ScoreboardConfig: Hashable {
    let fixture: Fixture
    let homePlayers: [String]
    let awayPlayers: [String]
    let initialServerName: String
    let initialReceiverName: String
    let serverIsOnLeft: Bool
    let bestOf: Int
    let isTest: Bool
}

struct SetRecord: Identifiable, Hashable {
    let id = UUID()
    let setNumber: Int
    var homeScore: Int
    var awayScore: Int
}

// MARK: - MANAGER CLASS

@MainActor
class FirestoreManager: ObservableObject {
    private let db = Firestore.firestore()
    
    func fetchSmartLaunchFixtures() async throws -> [Fixture] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        let today = formatter.string(from: Date())
        
        let snapshot = try await db.collection("fixtures")
            .whereField("date", isEqualTo: today)
            .getDocuments()
        
        return snapshot.documents.compactMap { try? $0.data(as: Fixture.self) }
    }
    
    func fetchMatchRosters(homeTeam: String, awayTeam: String) async -> (home: [String], away: [String]) {
        async let homeRoster = fetchRoster(for: homeTeam)
        async let awayRoster = fetchRoster(for: awayTeam)
        return await (homeRoster, awayRoster)
    }
    
    private func fetchRoster(for teamName: String) async -> [String] {
        do {
            let doc = try await db.collection("teams").document(teamName).getDocument()
            return doc.data()?["players"] as? [String] ?? []
        } catch { return [] }
    }
    
    // Checks history to prevent duplicates
    func fetchPlayedPairs(fixture: Fixture) async -> Set<String> {
        guard let fid = fixture.id else { return [] }
        do {
            let snapshot = try await db.collection("match_results")
                .whereField("fixture_id", isEqualTo: fid)
                .getDocuments()
            
            var played = Set<String>()
            for doc in snapshot.documents {
                let data = doc.data()
                if let h = data["home_players"] as? [String], let homeP = h.first,
                   let a = data["away_players"] as? [String], let awayP = a.first {
                    played.insert("\(homeP) vs \(awayP)")
                    played.insert("\(awayP) vs \(homeP)")
                }
            }
            return played
        } catch { return [] }
    }
    
    func searchPlayers(query: String) async throws -> [Player] {
        guard query.count >= 2 else { return [] }
        let snapshot = try await db.collection("players")
            .order(by: "name")
            .start(at: [query])
            .end(at: [query + "\u{f8ff}"])
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Player.self) }
    }
    
    // MARK: - LIVE SYNC (CRITICAL FIX 1)
    func updateLiveScore(fixtureId: String?, homeScore: Int, awayScore: Int, homeSets: Int, awaySets: Int, server: String) {
        guard let fid = fixtureId else { return }
        
        let data: [String: Any] = [
            "live_home_score": homeScore,
            "live_away_score": awayScore,
            "live_home_sets": homeSets,
            "live_away_sets": awaySets,
            "current_server": server,
            "last_live_update": FieldValue.serverTimestamp()
        ]
        
        // This updates the ACTUAL fixture document the website is listening to
        db.collection("fixtures").document(fid).updateData(data)
    }
    
    func uploadFinalScore(fixture: Fixture, homePlayers: [String], awayPlayers: [String], history: [SetRecord], isTest: Bool) {
        let data: [String: Any] = [
            "fixture_id": fixture.id ?? "",
            "table": fixture.table,
            "division": fixture.division,
            "home_team": fixture.homeTeam,
            "away_team": fixture.awayTeam,
            "home_players": homePlayers,
            "away_players": awayPlayers,
            "set_scores": history.map { ["home": $0.homeScore, "away": $0.awayScore] },
            "is_test": isTest,
            "timestamp": FieldValue.serverTimestamp(),
            "season": "Summer 2026"
        ]
        db.collection("match_results").addDocument(data: data)
    }
}
