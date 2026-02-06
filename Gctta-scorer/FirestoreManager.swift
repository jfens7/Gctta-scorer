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
    @Published var liveFixtures: [Fixture] = []
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    init() {
        listenToTodayFixtures()
    }
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - LISTENER
    func listenToTodayFixtures() {
        // Logic: Listen for fixtures with today's date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        let today = formatter.string(from: Date())
        
        // NOTE: If you are testing and dates don't match, you can remove the .whereField line temporarily
        listener = db.collection("fixtures")
            .whereField("date", isEqualTo: today)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching fixtures: \(error?.localizedDescription ?? "Unknown")")
                    return
                }
                self?.liveFixtures = documents.compactMap { try? $0.data(as: Fixture.self) }
                    .sorted { $0.table.localizedStandardCompare($1.table) == .orderedAscending }
            }
    }
    
    // MARK: - DATA FETCHING
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
    
    // MARK: - PLAYERS
    func searchPlayers(query: String) async throws -> [Player] {
        guard query.count >= 1 else { return [] }
        // Note: Firestore text search is limited. This is a prefix match.
        let snapshot = try await db.collection("players")
            .order(by: "name")
            .start(at: [query])
            .end(at: [query + "\u{f8ff}"])
            .limit(to: 10)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Player.self) }
    }
    
    func addNewPlayer(name: String) async throws -> Player {
        let newRef = db.collection("players").document()
        let player = Player(id: newRef.documentID, name: name, active: true, isProvisional: true)
        try newRef.setData(from: player)
        return player
    }
    
    // MARK: - LIVE SYNC
    func updateLiveScore(fixtureId: String?, homeScore: Int, awayScore: Int, homeSets: Int, awaySets: Int, server: String, timerLabel: String?, timerValue: Int, totalTime: String, activeTime: String) {
        guard let fid = fixtureId else { return }
        
        let data: [String: Any] = [
            "live_home_score": homeScore,
            "live_away_score": awayScore,
            "live_home_sets": homeSets,
            "live_away_sets": awaySets,
            "current_server": server,
            "timer_label": timerLabel ?? "",
            "timer_value": timerValue,
            "total_duration": totalTime,
            "play_duration": activeTime,
            "match_status": "Live",
            "last_live_update": FieldValue.serverTimestamp()
        ]
        
        db.collection("fixtures").document(fid).updateData(data)
    }
    
    // MARK: - FINAL UPLOAD
    func uploadFinalScore(fixture: Fixture, homePlayers: [String], awayPlayers: [String], history: [SetRecord], isTest: Bool, totalTime: String, activeTime: String) {
        let gameHistoryString = history.map { "\($0.homeScore)-\($0.awayScore)" }.joined(separator: ", ")
        
        let data: [String: Any] = [
            "fixture_id": fixture.id ?? "",
            "table": fixture.table,
            "division": fixture.division,
            "home_team": fixture.homeTeam,
            "away_team": fixture.awayTeam,
            "home_players": homePlayers,
            "away_players": awayPlayers,
            "set_scores": history.map { ["home": $0.homeScore, "away": $0.awayScore] },
            "game_scores_history": gameHistoryString,
            "total_duration": totalTime,
            "play_duration": activeTime,
            "is_test": isTest,
            "timestamp": FieldValue.serverTimestamp(),
            "date": fixture.date,
            "match_status": "Finished"
        ]
        
        // 1. Save to Results History
        db.collection("match_results").addDocument(data: data)
        
        // 2. Update Fixture Status to 'Finished'
        if let fid = fixture.id {
            db.collection("fixtures").document(fid).updateData([
                "match_status": "Finished",
                "game_scores_history": gameHistoryString,
                "live_home_sets": history.filter { $0.homeScore > $0.awayScore }.count,
                "live_away_sets": history.filter { $0.awayScore > $0.homeScore }.count
            ])
        }
    }
}
