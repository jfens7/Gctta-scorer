import SwiftUI

struct FixtureMatch: Identifiable, Equatable {
    let id = UUID()
    let homeLetters: [String]
    let awayLetters: [String]
    let isDoubles: Bool
}

struct MatchSetupView: View {
    @ObservedObject var fsManager: FirestoreManager
    let fixture: Fixture
    @Binding var path: NavigationPath
    
    @State private var homeRoster: [String] = []
    @State private var awayRoster: [String] = []
    
    // Explicit Letter Mappings
    @State private var homeLetters: [String: String] = [:]
    @State private var awayLetters: [String: String] = [:]
    
    @State private var playedPairs: Set<String> = []
    @State private var fixtureStats = FixtureStats()
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Sequence State
    @State private var matchSequence: [FixtureMatch] = []
    @State private var isReordering = false
    
    // Toss State
    @State private var activeMatchToStart: FixtureMatch?
    @State private var activeHomePlayers: [String] = []
    @State private var activeAwayPlayers: [String] = []
    @State private var selectedBestOf: Int = 5
    @State private var selectedInitialServer = ""
    @State private var selectedInitialReceiver = ""
    @State private var serverStartsOnWall = true
    @State private var isTestMatch = false
    
    // Search State
    @State private var showingSearchSheet = false
    @State private var activeSearchTeamIsHome = true
    
    // Rank Selection State
    @State private var playerPendingRank: Player? = nil
    @State private var showRankDialog = false
    
    @State private var refreshTrigger = false

    var isDiv1: Bool {
        fixture.division.lowercased().contains("div 1") || fixture.division.lowercased().contains("premier")
    }

    var body: some View {
        VStack(spacing: 15) {
            
            // --- LIVE NIGHT SCOREBOARD ---
            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text(fixture.homeTeam.uppercased()).font(.title2.bold()).foregroundColor(.blue)
                    Text("SCORE: \(fixtureStats.homeTeamScore)").font(.headline).foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .center) {
                    Text("TABLE \(fixture.table)").font(.system(size: 35, weight: .black))
                    Text("MATCH SETUP").font(.caption).foregroundColor(.gray).tracking(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(fixture.awayTeam.uppercased()).font(.title2.bold()).foregroundColor(.red)
                    Text("SCORE: \(fixtureStats.awayTeamScore)").font(.headline).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // --- ROSTER RANKING SYSTEM ---
            HStack(alignment: .top, spacing: 0) {
                TeamSelectionColumn(
                    teamName: fixture.homeTeam,
                    roster: $homeRoster,
                    isHome: true,
                    color: .blue,
                    playerStats: fixtureStats.playerStats,
                    getLetter: getLetter,
                    onMoveUp: { movePlayerUp(name: $0, isHome: true) },
                    onMoveDown: { movePlayerDown(name: $0, isHome: true) },
                    onDelete: { removePlayer(name: $0, isHome: true) },
                    onAdd: { activeSearchTeamIsHome = true; showingSearchSheet = true }
                )
                .frame(maxWidth: .infinity)
                
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1).padding(.horizontal, 15)
                
                TeamSelectionColumn(
                    teamName: fixture.awayTeam,
                    roster: $awayRoster,
                    isHome: false,
                    color: .red,
                    playerStats: fixtureStats.playerStats,
                    getLetter: getLetter,
                    onMoveUp: { movePlayerUp(name: $0, isHome: false) },
                    onMoveDown: { movePlayerDown(name: $0, isHome: false) },
                    onDelete: { removePlayer(name: $0, isHome: false) },
                    onAdd: { activeSearchTeamIsHome = false; showingSearchSheet = true }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .frame(height: 250)
            .id(refreshTrigger)
            
            Divider().padding(.vertical, 5)
            
            // --- MATCH SEQUENCE HEADER ---
            HStack {
                VStack(alignment: .leading) {
                    Text("NIGHT'S FIXTURE")
                        .font(.title2.bold())
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Text("Matches will dynamically appear below as you assign players to their ranks.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: { isReordering.toggle() }) {
                    HStack {
                        Image(systemName: isReordering ? "checkmark.circle.fill" : "arrow.up.arrow.down")
                        Text(isReordering ? "DONE" : "REORDER SEQUENCE")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isReordering ? Color.green : Color.orange.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            // --- AUTOMATED MATCH LIST (DYNAMIC VISIBILITY) ---
            let visibleCount = matchSequence.filter { canMatchStart(match: $0) }.count
            
            if visibleCount == 0 && !isReordering {
                VStack {
                    Spacer()
                    Image(systemName: "person.fill.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                        .padding(.bottom, 5)
                    Text("Add players above and assign their ranks to generate matches.")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(matchSequence) { match in
                        let index = matchSequence.firstIndex(of: match) ?? 0
                        let hNames = match.homeLetters.compactMap { getPlayerWithLetter(letter: $0, isHome: true) }
                        let aNames = match.awayLetters.compactMap { getPlayerWithLetter(letter: $0, isHome: false) }
                        let canStart = hNames.count == match.homeLetters.count && aNames.count == match.awayLetters.count
                        
                        // SMART VISIBILITY: Only show the match if players exist, or if we are actively reordering
                        if canStart || isReordering {
                            HStack {
                                Text("\(index + 1).")
                                    .font(.title3.bold())
                                    .frame(width: 35, alignment: .leading)
                                    .foregroundColor(.gray)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.isDoubles ? "DOUBLES" : "SINGLES")
                                        .font(.caption.bold())
                                        .foregroundColor(match.isDoubles ? .purple : .blue)
                                        .tracking(1)
                                    
                                    HStack {
                                        Text("\(hNames.joined(separator: " & "))")
                                            .font(.headline.bold())
                                            .foregroundColor(hNames.isEmpty ? .gray : .white)
                                        Text("(\(match.homeLetters.joined(separator: "&")))")
                                            .font(.caption).foregroundColor(.blue)
                                        
                                        Text(" vs ").foregroundColor(.gray).font(.caption.bold())
                                        
                                        Text("\(aNames.joined(separator: " & "))")
                                            .font(.headline.bold())
                                            .foregroundColor(aNames.isEmpty ? .gray : .white)
                                        Text("(\(match.awayLetters.joined(separator: "&")))")
                                            .font(.caption).foregroundColor(.red)
                                    }
                                }
                                Spacer()
                                
                                if !isReordering {
                                    if canStart {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 35))
                                            .foregroundColor(.green)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                startMatch(match: match, hNames: hNames, aNames: aNames)
                                            }
                                    } else {
                                        Text("Assign Players")
                                            .font(.caption.bold())
                                            .foregroundColor(.orange)
                                    }
                                } else {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundColor(.gray)
                                        .font(.title2)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .onMove { from, to in
                        matchSequence.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(isReordering ? .active : .inactive))
            }
        }
        .onAppear {
            Task {
                playedPairs = await fsManager.fetchPlayedPairs(fixture: fixture)
                if let fid = fixture.id {
                    fixtureStats = await fsManager.fetchFixtureStats(fixtureId: fid)
                }
                
                if homeRoster.isEmpty {
                    let rosters = await fsManager.fetchMatchRosters(homeTeam: fixture.homeTeam, awayTeam: fixture.awayTeam)
                    homeRoster = rosters.home
                    awayRoster = rosters.away
                    autoAssignLetters()
                }
                generateSequence()
            }
        }
        
        .alert("Missing Players", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
        
        // RANK SELECTION DIALOG
        .confirmationDialog("Select Rank for \(playerPendingRank?.name ?? "")", isPresented: $showRankDialog, titleVisibility: .visible) {
            if isDiv1 {
                Button("Rank 1 (\(activeSearchTeamIsHome ? "A" : "X"))") { assignRank(1) }
                Button("Rank 2 (\(activeSearchTeamIsHome ? "B" : "Y"))") { assignRank(2) }
            } else {
                Button("Rank 1 (\(activeSearchTeamIsHome ? "B" : "Z"))") { assignRank(1) }
                Button("Rank 2 (\(activeSearchTeamIsHome ? "C" : "X"))") { assignRank(2) }
                Button("Rank 3 (\(activeSearchTeamIsHome ? "A" : "Y"))") { assignRank(3) }
            }
            Button("Cancel", role: .cancel) { playerPendingRank = nil }
        }
        
        .sheet(item: $activeMatchToStart) { match in
            TossView(
                selectedHome: activeHomePlayers,
                selectedAway: activeAwayPlayers,
                isDoubles: match.isDoubles,
                selectedBestOf: $selectedBestOf,
                isTestMatch: $isTestMatch,
                serverStartsOnWall: $serverStartsOnWall,
                selectedInitialServer: $selectedInitialServer,
                selectedInitialReceiver: $selectedInitialReceiver,
                onStart: { launchScoreboard() }
            )
        }
        
        .sheet(isPresented: $showingSearchSheet) {
            PlayerSearchSheet(fsManager: fsManager) { player in
                playerPendingRank = player
                showRankDialog = true
            }
        }
    }
    
    // MARK: - RANKING ASSIGNMENT LOGIC
    
    func assignRank(_ rank: Int) {
        guard let p = playerPendingRank else { return }
        let letter: String
        
        // Map the selected rank to the specific explicit letter
        if isDiv1 {
            if activeSearchTeamIsHome { letter = rank == 1 ? "A" : "B" }
            else { letter = rank == 1 ? "X" : "Y" }
        } else {
            if activeSearchTeamIsHome {
                if rank == 1 { letter = "B" } else if rank == 2 { letter = "C" } else { letter = "A" }
            } else {
                if rank == 1 { letter = "Z" } else if rank == 2 { letter = "X" } else { letter = "Y" }
            }
        }
        
        // If this letter is already taken, remove the old player to allow substitutions
        if activeSearchTeamIsHome {
            homeLetters.forEach { k, v in if v == letter { homeLetters.removeValue(forKey: k); homeRoster.removeAll(where: { $0 == k }) } }
            homeLetters[p.name] = letter
            if !homeRoster.contains(p.name) { homeRoster.append(p.name) }
        } else {
            awayLetters.forEach { k, v in if v == letter { awayLetters.removeValue(forKey: k); awayRoster.removeAll(where: { $0 == k }) } }
            awayLetters[p.name] = letter
            if !awayRoster.contains(p.name) { awayRoster.append(p.name) }
        }
        
        sortRosters()
        refreshTrigger.toggle()
    }
    
    // Ranks values (1, 2, 3) to sort the UI column intelligently
    func rankValue(for letter: String, isHome: Bool) -> Int {
        if isDiv1 {
            if isHome { return letter == "A" ? 1 : 2 }
            else { return letter == "X" ? 1 : 2 }
        } else {
            if isHome {
                if letter == "B" { return 1 }
                if letter == "C" { return 2 }
                if letter == "A" { return 3 }
            } else {
                if letter == "Z" { return 1 }
                if letter == "X" { return 2 }
                if letter == "Y" { return 3 }
            }
        }
        return 99
    }
    
    func sortRosters() {
        homeRoster.sort { rankValue(for: homeLetters[$0] ?? "?", isHome: true) < rankValue(for: homeLetters[$1] ?? "?", isHome: true) }
        awayRoster.sort { rankValue(for: awayLetters[$0] ?? "?", isHome: false) < rankValue(for: awayLetters[$1] ?? "?", isHome: false) }
    }
    
    // Auto-assigns default letters if we pull an existing roster from the database
    func autoAssignLetters() {
        for (idx, name) in homeRoster.enumerated() {
            if homeLetters[name] == nil {
                if isDiv1 { homeLetters[name] = idx == 0 ? "A" : "B" }
                else { homeLetters[name] = idx == 0 ? "B" : (idx == 1 ? "C" : "A") }
            }
        }
        for (idx, name) in awayRoster.enumerated() {
            if awayLetters[name] == nil {
                if isDiv1 { awayLetters[name] = idx == 0 ? "X" : "Y" }
                else { awayLetters[name] = idx == 0 ? "Z" : (idx == 1 ? "X" : "Y") }
            }
        }
        sortRosters()
    }

    func getLetter(for name: String, isHome: Bool) -> String {
        return isHome ? (homeLetters[name] ?? "?") : (awayLetters[name] ?? "?")
    }

    func getPlayerWithLetter(letter: String, isHome: Bool) -> String? {
        let dict = isHome ? homeLetters : awayLetters
        let roster = isHome ? homeRoster : awayRoster
        for (name, l) in dict {
            if l == letter && roster.contains(name) { return name }
        }
        return nil
    }

    func canMatchStart(match: FixtureMatch) -> Bool {
        let hNames = match.homeLetters.compactMap { getPlayerWithLetter(letter: $0, isHome: true) }
        let aNames = match.awayLetters.compactMap { getPlayerWithLetter(letter: $0, isHome: false) }
        return hNames.count == match.homeLetters.count && aNames.count == match.awayLetters.count
    }

    // MARK: - SEQUENCE GENERATOR
    func generateSequence() {
        // We always generate the FULL sequence.
        // The List will intelligently hide matches if players aren't assigned yet.
        if isDiv1 {
            matchSequence = [
                FixtureMatch(homeLetters: ["A"], awayLetters: ["X"], isDoubles: false),
                FixtureMatch(homeLetters: ["B"], awayLetters: ["Y"], isDoubles: false),
                FixtureMatch(homeLetters: ["B"], awayLetters: ["X"], isDoubles: false),
                FixtureMatch(homeLetters: ["A"], awayLetters: ["Y"], isDoubles: false),
                FixtureMatch(homeLetters: ["A", "B"], awayLetters: ["X", "Y"], isDoubles: true)
            ]
        } else {
            matchSequence = [
                FixtureMatch(homeLetters: ["A"], awayLetters: ["X"], isDoubles: false), // 1
                FixtureMatch(homeLetters: ["B"], awayLetters: ["Y"], isDoubles: false), // 2
                FixtureMatch(homeLetters: ["C"], awayLetters: ["Z"], isDoubles: false), // 3
                FixtureMatch(homeLetters: ["B", "C"], awayLetters: ["Z", "X"], isDoubles: true), // 4
                FixtureMatch(homeLetters: ["B"], awayLetters: ["X"], isDoubles: false), // 5
                FixtureMatch(homeLetters: ["A"], awayLetters: ["Z"], isDoubles: false), // 6
                FixtureMatch(homeLetters: ["C"], awayLetters: ["Y"], isDoubles: false), // 7
                FixtureMatch(homeLetters: ["B", "A"], awayLetters: ["Z", "Y"], isDoubles: true), // 8
                FixtureMatch(homeLetters: ["B"], awayLetters: ["Z"], isDoubles: false), // 9
                FixtureMatch(homeLetters: ["C"], awayLetters: ["X"], isDoubles: false), // 10
                FixtureMatch(homeLetters: ["A"], awayLetters: ["Y"], isDoubles: false)  // 11
            ]
        }
    }
    
    // MARK: - MOVEMENT CONTROLS
    // Up/Down arrows now directly swap the assigned letters between players and re-sorts
    func movePlayerUp(name: String, isHome: Bool) {
        var roster = isHome ? homeRoster : awayRoster
        var dict = isHome ? homeLetters : awayLetters
        if let idx = roster.firstIndex(of: name), idx > 0 {
            let otherName = roster[idx - 1]
            
            let tempLetter = dict[name]
            dict[name] = dict[otherName]
            dict[otherName] = tempLetter
            
            if isHome { homeLetters = dict } else { awayLetters = dict }
            sortRosters()
            refreshTrigger.toggle()
        }
    }

    func movePlayerDown(name: String, isHome: Bool) {
        var roster = isHome ? homeRoster : awayRoster
        var dict = isHome ? homeLetters : awayLetters
        if let idx = roster.firstIndex(of: name), idx < roster.count - 1 {
            let otherName = roster[idx + 1]
            
            let tempLetter = dict[name]
            dict[name] = dict[otherName]
            dict[otherName] = tempLetter
            
            if isHome { homeLetters = dict } else { awayLetters = dict }
            sortRosters()
            refreshTrigger.toggle()
        }
    }
    
    func removePlayer(name: String, isHome: Bool) {
        if isHome {
            homeRoster.removeAll { $0 == name }
            homeLetters.removeValue(forKey: name)
        } else {
            awayRoster.removeAll { $0 == name }
            awayLetters.removeValue(forKey: name)
        }
        sortRosters()
        refreshTrigger.toggle()
    }

    func startMatch(match: FixtureMatch, hNames: [String], aNames: [String]) {
        self.activeHomePlayers = hNames
        self.activeAwayPlayers = aNames
        self.selectedInitialServer = hNames.first ?? ""
        self.selectedInitialReceiver = aNames.first ?? ""
        
        let maxPlayers = max(homeRoster.count, awayRoster.count)
        if maxPlayers <= 1 {
            self.selectedBestOf = 7
        } else if maxPlayers == 2 {
            self.selectedBestOf = match.isDoubles ? 5 : 7
        } else {
            self.selectedBestOf = 5
        }
        
        self.activeMatchToStart = match
    }
    
    func launchScoreboard() {
        let wallSide = VenueMapper.wallSide(for: fixture.table)
        let serverIsOnLeft = (serverStartsOnWall && wallSide == .left) || (!serverStartsOnWall && wallSide == .right)
        
        let config = ScoreboardConfig(
            fixture: fixture,
            homePlayers: activeHomePlayers,
            awayPlayers: activeAwayPlayers,
            initialServerName: selectedInitialServer,
            initialReceiverName: selectedInitialReceiver,
            serverIsOnLeft: serverIsOnLeft,
            bestOf: selectedBestOf,
            isTest: isTestMatch
        )
        
        activeMatchToStart = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { path.append(config) }
    }
}

// MARK: - RANKING UI HELPER

struct TeamSelectionColumn: View {
    let teamName: String
    @Binding var roster: [String]
    let isHome: Bool
    let color: Color
    let playerStats: [String: PlayerNightStat]
    let getLetter: (String, Bool) -> String
    let onMoveUp: (String) -> Void
    let onMoveDown: (String) -> Void
    let onDelete: (String) -> Void
    let onAdd: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(roster, id: \.self) { name in
                        let idx = roster.firstIndex(of: name) ?? 0
                        let stats = playerStats[name] ?? PlayerNightStat()
                        
                        HStack(spacing: 10) {
                            
                            // RANK IDENTIFIER & LETTER
                            VStack(spacing: 2) {
                                Text("RANK \(idx + 1)")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.gray)
                                Text(getLetter(name, isHome))
                                    .font(.system(size: 20, weight: .black))
                                    .frame(width: 50, height: 40)
                                    .background(color.opacity(0.2))
                                    .foregroundColor(color)
                                    .cornerRadius(8)
                            }
                            
                            // PLAYER NAME & STATS
                            HStack {
                                Text(name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                                
                                if stats.played > 0 {
                                    Text("\(stats.wins)W - \(stats.played)P")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(4)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                            
                            // RANK REORDER ARROWS & DELETE
                            VStack(spacing: 5) {
                                HStack(spacing: 5) {
                                    Button(action: { onMoveUp(name) }) {
                                        Image(systemName: "chevron.up").font(.caption).padding(6).background(Color.white.opacity(0.1)).cornerRadius(5)
                                    }.disabled(idx == 0)
                                    
                                    Button(action: { onMoveDown(name) }) {
                                        Image(systemName: "chevron.down").font(.caption).padding(6).background(Color.white.opacity(0.1)).cornerRadius(5)
                                    }.disabled(idx == roster.count - 1)
                                }
                                Button(action: { onDelete(name) }) {
                                    Image(systemName: "trash.fill").font(.caption).foregroundColor(.red).padding(6).frame(maxWidth: .infinity).background(Color.red.opacity(0.1)).cornerRadius(5)
                                }
                            }
                        }
                    }
                    Button(action: onAdd) {
                        Label("Add / Substitute Player", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity).padding().background(Color.gray.opacity(0.1)).foregroundColor(.primary).cornerRadius(10)
                    }
                }
            }
        }
    }
}

struct TossView: View {
    let selectedHome: [String]
    let selectedAway: [String]
    let isDoubles: Bool
    @Binding var selectedBestOf: Int
    @Binding var isTestMatch: Bool
    @Binding var serverStartsOnWall: Bool
    @Binding var selectedInitialServer: String
    @Binding var selectedInitialReceiver: String
    let onStart: () -> Void
    
    @State private var showingConfirmAlert = false
    
    var body: some View {
        VStack(spacing: 25) {
            Text("Match Toss").font(.largeTitle.bold())
            
            HStack {
                Picker("Format", selection: $selectedBestOf) {
                    Text("Best of 3").tag(3)
                    Text("Best of 5").tag(5)
                    Text("Best of 7").tag(7)
                }.pickerStyle(.segmented).frame(width: 300)
                
                Toggle("Test Match (No Stats)", isOn: $isTestMatch).padding(.horizontal).background(Color.orange.opacity(0.1)).cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                Text("1. Who is serving first?").font(.headline)
                
                HStack(spacing: 15) {
                    ForEach(selectedHome + selectedAway, id: \.self) { player in
                        Button(action: {
                            selectedInitialServer = player
                            if isDoubles {
                                let validReceivers = selectedHome.contains(player) ? selectedAway : selectedHome
                                if !validReceivers.contains(selectedInitialReceiver) {
                                    selectedInitialReceiver = validReceivers.first ?? ""
                                }
                            }
                        }) {
                            Text(player)
                                .font(.title3.bold())
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedInitialServer == player ? Color.yellow : Color.gray.opacity(0.3))
                                .foregroundColor(selectedInitialServer == player ? .black : .white)
                                .cornerRadius(10)
                        }
                    }
                }
                
                if isDoubles {
                    Text("2. Who is receiving?").font(.headline)
                    let validReceivers = selectedHome.contains(selectedInitialServer) ? selectedAway : selectedHome
                    
                    HStack(spacing: 15) {
                        ForEach(validReceivers, id: \.self) { player in
                            Button(action: {
                                selectedInitialReceiver = player
                            }) {
                                Text(player)
                                    .font(.title3.bold())
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(selectedInitialReceiver == player ? Color.cyan : Color.gray.opacity(0.3))
                                    .foregroundColor(selectedInitialReceiver == player ? .black : .white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
                
                Text("Position of \(selectedInitialServer.isEmpty ? "Server" : selectedInitialServer)?").font(.headline)
                HStack {
                    Button("Wall Side") { serverStartsOnWall = true }.padding().frame(maxWidth: .infinity).background(serverStartsOnWall ? Color.blue : Color.gray.opacity(0.2)).foregroundColor(serverStartsOnWall ? .white : .primary).cornerRadius(10)
                    Button("Grandstand Side") { serverStartsOnWall = false }.padding().frame(maxWidth: .infinity).background(!serverStartsOnWall ? Color.blue : Color.gray.opacity(0.2)).foregroundColor(!serverStartsOnWall ? .white : .primary).cornerRadius(10)
                }
            }.padding()
            
            Button("START MATCH") {
                if selectedInitialServer.isEmpty {
                    selectedInitialServer = selectedHome.first ?? ""
                }
                showingConfirmAlert = true
            }
            .font(.title2.bold())
            .frame(maxWidth: .infinity, maxHeight: 60)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(15)
            .padding()
        }
        .alert("Confirm First Server", isPresented: $showingConfirmAlert) {
            Button("No, Wait", role: .cancel) { }
            Button("Yes, Start Match") { onStart() }
        } message: {
            Text("Are you sure '\(selectedInitialServer)' is serving first?")
        }
    }
}

struct PlayerSearchSheet: View {
    @ObservedObject var fsManager: FirestoreManager
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [Player] = []
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(searchResults) { player in
                    Button(action: { onSelect(player); dismiss() }) {
                        HStack {
                            Text(player.name)
                            if player.isProvisional == true { Text("(New)").font(.caption).foregroundColor(.orange) }
                        }
                    }
                }
                
                if !searchText.isEmpty && searchResults.isEmpty {
                    Section {
                        Button(action: addNewPlayer) {
                            Label("Add new player: \"\(searchText)\"", systemImage: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .task {
                if let players = try? await fsManager.fetchAllPlayers() { searchResults = players }
            }
            .onChange(of: searchText) { _, nv in
                Task {
                    if nv.isEmpty { searchResults = (try? await fsManager.fetchAllPlayers()) ?? [] }
                    else { searchResults = (try? await fsManager.searchPlayers(query: nv)) ?? [] }
                }
            }
            .navigationTitle("Search Players")
        }
    }
    
    func addNewPlayer() {
        Task {
            if let p = try? await fsManager.addNewPlayer(name: searchText) { onSelect(p); dismiss() }
        }
    }
}
