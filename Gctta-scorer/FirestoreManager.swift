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
    var matchStatus: String?
    
    enum CodingKeys: String, CodingKey {
        case id, table, date, division
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case matchStatus = "match_status"
    }
}

// Data object to restore a match
struct SavedMatchState {
    let homeScore: Int
    let awayScore: Int
    let setHistory: [SetRecord]
    let leftPlayers: [String]
    let rightPlayers: [String]
    let server: String
    let receiver: String
    let totalTime: Int
    let activeTime: Int
    let lastSetServer: String
    let lastSetReceiver: String
    let initialMatchServer: String
    let initialMatchReceiver: String
}

struct ScoreboardConfig: Hashable, Codable {
    let fixture: Fixture
    let homePlayers: [String]
    let awayPlayers: [String]
    let initialServerName: String
    let initialReceiverName: String
    let serverIsOnLeft: Bool
    let bestOf: Int
    let isTest: Bool
    var isResume: Bool = false
}

struct SetRecord: Identifiable, Hashable, Codable {
    var id = UUID()
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        let today = formatter.string(from: Date())
        
        listener = db.collection("fixture_schedule")
            .whereField("date", isEqualTo: today)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                self?.liveFixtures = documents.compactMap { try? $0.data(as: Fixture.self) }
                    .sorted { $0.table.localizedStandardCompare($1.table) == .orderedAscending }
            }
    }
    
    // MARK: - RESUME & REVIEW LOGIC
    func fetchSavedState(fixtureId: String) async -> SavedMatchState? {
        do {
            let doc = try await db.collection("fixture_schedule").document(fixtureId).getDocument()
            guard let data = doc.data() else { return nil }
            
            var history: [SetRecord] = []
            if let jsonString = data["set_history_json"] as? String,
               let jsonData = jsonString.data(using: .utf8) {
                history = (try? JSONDecoder().decode([SetRecord].self, from: jsonData)) ?? []
            }
            
            let tStr = data["total_duration"] as? String ?? "00:00"
            let aStr = data["play_duration"] as? String ?? "00:00"
            
            return SavedMatchState(
                homeScore: data["live_home_score"] as? Int ?? 0,
                awayScore: data["live_away_score"] as? Int ?? 0,
                setHistory: history,
                leftPlayers: data["left_players"] as? [String] ?? [],
                rightPlayers: data["right_players"] as? [String] ?? [],
                server: data["current_server"] as? String ?? "",
                receiver: data["current_receiver"] as? String ?? "",
                totalTime: parseTime(tStr),
                activeTime: parseTime(aStr),
                lastSetServer: data["last_set_start_server"] as? String ?? "",
                lastSetReceiver: data["last_set_start_receiver"] as? String ?? "",
                initialMatchServer: data["initial_match_server"] as? String ?? "",
                initialMatchReceiver: data["initial_match_receiver"] as? String ?? ""
            )
        } catch { return nil }
    }
    
    func flagMatchForReview(fixtureId: String) {
        db.collection("fixture_schedule").document(fixtureId).updateData([
            "match_status": "REVIEW NEEDED",
            "admin_note": "iPad app closed mid-match and user declined to resume."
        ])
    }
    
    private func parseTime(_ str: String) -> Int {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return 0
    }
    
    // MARK: - PLAYERS & DATA
    func fetchAllPlayers() async throws -> [Player] {
        let snapshot = try await db.collection("players").order(by: "name").limit(to: 100).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Player.self) }
    }

    func searchPlayers(query: String) async throws -> [Player] {
        guard query.count >= 1 else { return [] }
        let snapshot = try await db.collection("players").order(by: "name").start(at: [query]).end(at: [query + "\u{f8ff}"]).limit(to: 10).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Player.self) }
    }
    
    func addNewPlayer(name: String) async throws -> Player {
        let newRef = db.collection("players").document()
        let player = Player(id: newRef.documentID, name: name, active: true, isProvisional: true)
        try newRef.setData(from: player)
        return player
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
    
    func fetchPlayedPairs(fixture: Fixture) async -> Set<String> {
        guard let fid = fixture.id else { return [] }
        let snapshot = try? await db.collection("match_results").whereField("fixture_id", isEqualTo: fid).getDocuments()
        var played = Set<String>()
        snapshot?.documents.forEach { doc in
            let data = doc.data()
            if let h = data["home_players"] as? [String], let homeP = h.first,
               let a = data["away_players"] as? [String], let awayP = a.first {
                played.insert("\(homeP) vs \(awayP)")
                played.insert("\(awayP) vs \(homeP)")
            }
        }
        return played
    }
    
    // MARK: - TIMELINE LOGGING
    func saveTimelineEvent(fixtureId: String?, data: [String: Any]) {
        guard let fid = fixtureId else { return }
        var eventData = data
        eventData["timestamp"] = FieldValue.serverTimestamp()
        
        db.collection("fixture_schedule").document(fid)
            .collection("timeline")
            .addDocument(data: eventData)
    }
    
    // MARK: - UPDATE LIVE
    func updateLiveScore(fixtureId: String?, homeScore: Int, awayScore: Int, homeSets: Int, awaySets: Int, server: String, receiver: String, timerLabel: String?, timerValue: Int, totalTime: String, activeTime: String, homePlayers: [String], awayPlayers: [String], leftPlayers: [String], rightPlayers: [String], matchStatus: String, gameStats: [String: Any], setHistory: [SetRecord], lastSetServer: String, lastSetReceiver: String, initialMatchServer: String, initialMatchReceiver: String, gameHistoryString: String) {
        
        guard let fid = fixtureId else { return }
        
        let historyJson = (try? JSONEncoder().encode(setHistory)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        
        var data: [String: Any] = [
            "live_home_score": homeScore,
            "live_away_score": awayScore,
            "live_home_sets": homeSets,
            "live_away_sets": awaySets,
            "current_server": server,
            "current_receiver": receiver,
            "timer_label": timerLabel ?? "",
            "timer_value": timerValue,
            "total_duration": totalTime,
            "play_duration": activeTime,
            "match_status": matchStatus,
            "last_live_update": FieldValue.serverTimestamp(),
            "home_players": homePlayers,
            "away_players": awayPlayers,
            "left_players": leftPlayers,
            "right_players": rightPlayers,
            "set_history_json": historyJson,
            "game_scores_history": gameHistoryString,
            "last_set_start_server": lastSetServer,
            "last_set_start_receiver": lastSetReceiver,
            "initial_match_server": initialMatchServer,
            "initial_match_receiver": initialMatchReceiver
        ]
        
        for (key, value) in gameStats { data[key] = value }
        
        db.collection("fixture_schedule").document(fid).updateData(data)
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
        
        db.collection("match_results").addDocument(data: data)
        
        if let fid = fixture.id {
            db.collection("fixture_schedule").document(fid).updateData([
                "match_status": "Finished",
                "game_scores_history": gameHistoryString,
                "live_home_sets": history.filter { $0.homeScore > $0.awayScore }.count,
                "live_away_sets": history.filter { $0.awayScore > $0.homeScore }.count,
                "home_players": homePlayers,
                "away_players": awayPlayers
            ])
        }
    }
}
