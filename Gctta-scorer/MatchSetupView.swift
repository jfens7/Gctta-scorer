import SwiftUI

struct MatchSetupView: View {
    @ObservedObject var fsManager: FirestoreManager
    let fixture: Fixture
    @Binding var path: NavigationPath
    
    @State private var homeRoster: [String] = []
    @State private var awayRoster: [String] = []
    @State private var selectedHome: Set<String> = []
    @State private var selectedAway: Set<String> = []
    
    @State private var playedPairs: Set<String> = []
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    @State private var matchType: MatchType = .singles
    @State private var selectedBestOf: Int = 5
    
    @State private var showingToss = false
    @State private var selectedInitialServer = ""
    @State private var selectedInitialReceiver = ""
    @State private var serverStartsOnWall = true
    @State private var isTestMatch = false
    
    @State private var showingSearchSheet = false
    @State private var activeSearchTeamIsHome = true
    
    enum MatchType: String, CaseIterable { case singles = "Singles", doubles = "Doubles" }

    var body: some View {
        VStack(spacing: 20) {
            Text("Table \(fixture.table) Setup").font(.system(size: 40, weight: .black))
            
            HStack(spacing: 20) {
                Picker("Type", selection: $matchType) {
                    ForEach(MatchType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 250)
                .onChange(of: matchType) { _, _ in
                    selectedHome.removeAll(); selectedAway.removeAll()
                    autoSelectBestOf()
                }
                
                Picker("Format", selection: $selectedBestOf) {
                    Text("Best of 3").tag(3)
                    Text("Best of 5").tag(5)
                    Text("Best of 7").tag(7)
                }
                .pickerStyle(.segmented).frame(width: 300)
            }

            Text("Select \(slotsNeeded) Player\(slotsNeeded > 1 ? "s" : "") per Team").font(.headline).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 0) {
                TeamSelectionColumn(
                    teamName: fixture.homeTeam,
                    roster: homeRoster,
                    selected: $selectedHome,
                    limit: slotsNeeded,
                    disabledPlayers: getDisabledPlayers(forHome: true),
                    color: .blue
                ) {
                    activeSearchTeamIsHome = true; showingSearchSheet = true
                }
                .frame(maxWidth: .infinity)
                
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1).padding(.horizontal, 20)
                
                TeamSelectionColumn(
                    teamName: fixture.awayTeam,
                    roster: awayRoster,
                    selected: $selectedAway,
                    limit: slotsNeeded,
                    disabledPlayers: getDisabledPlayers(forHome: false),
                    color: .red
                ) {
                    activeSearchTeamIsHome = false; showingSearchSheet = true
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            
            Button(action: validateAndProceed) {
                Text("PROCEED TO TOSS").font(.title2.bold()).frame(width: 350, height: 70)
                    .background(canProceed ? Color.green : Color.gray.opacity(0.3)).foregroundColor(.white).cornerRadius(15)
            }
            .disabled(!canProceed)
        }
        .padding()
        .onAppear {
            Task {
                playedPairs = await fsManager.fetchPlayedPairs(fixture: fixture)
                if homeRoster.isEmpty {
                    let rosters = await fsManager.fetchMatchRosters(homeTeam: fixture.homeTeam, awayTeam: fixture.awayTeam)
                    homeRoster = rosters.home; awayRoster = rosters.away
                    autoSelectBestOf()
                }
            }
        }
        .alert("Invalid Matchup", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingToss) {
            TossView(
                selectedHome: Array(selectedHome),
                selectedAway: Array(selectedAway),
                matchType: matchType,
                isTestMatch: $isTestMatch,
                serverStartsOnWall: $serverStartsOnWall,
                selectedInitialServer: $selectedInitialServer,
                selectedInitialReceiver: $selectedInitialReceiver,
                onStart: { launchScoreboard() }
            )
        }
        .sheet(isPresented: $showingSearchSheet) {
            PlayerSearchSheet(fsManager: fsManager) { player in
                if activeSearchTeamIsHome {
                    if !homeRoster.contains(player.name) { homeRoster.append(player.name) }
                    if matchType == .singles { selectedHome = [player.name] }
                    else if selectedHome.count < slotsNeeded { selectedHome.insert(player.name) }
                } else {
                    if !awayRoster.contains(player.name) { awayRoster.append(player.name) }
                    if matchType == .singles { selectedAway = [player.name] }
                    else if selectedAway.count < slotsNeeded { selectedAway.insert(player.name) }
                }
            }
        }
    }

    var slotsNeeded: Int { matchType == .singles ? 1 : 2 }
    var canProceed: Bool { selectedHome.count == slotsNeeded && selectedAway.count == slotsNeeded }
    
    // MARK: - Validation Logic
    func validateAndProceed() {
        if matchType == .singles {
            if let homeP = selectedHome.first, let awayP = selectedAway.first {
                let pairKey = "\(homeP) vs \(awayP)"
                if playedPairs.contains(pairKey) {
                    errorMessage = "\(homeP) and \(awayP) have already played. Please select a different matchup."
                    showingErrorAlert = true
                    return
                }
            }
        }
        selectedInitialServer = Array(selectedHome).first ?? ""
        selectedInitialReceiver = Array(selectedAway).first ?? ""
        showingToss = true
    }
    
    func getDisabledPlayers(forHome: Bool) -> Set<String> {
        guard matchType == .singles else { return [] }
        var disabled = Set<String>()
        if forHome {
            if let opponent = selectedAway.first {
                for player in homeRoster {
                    if playedPairs.contains("\(player) vs \(opponent)") { disabled.insert(player) }
                }
            }
        } else {
            if let opponent = selectedHome.first {
                for player in awayRoster {
                    if playedPairs.contains("\(player) vs \(opponent)") { disabled.insert(player) }
                }
            }
        }
        return disabled
    }
    
    func autoSelectBestOf() {
        let div = fixture.division.lowercased()
        let isDiv1 = div.contains("div 1") || div.contains("premier")
        selectedBestOf = isDiv1 ? (matchType == .singles ? 7 : 5) : (matchType == .singles ? 5 : 3)
    }
    
    func launchScoreboard() {
        let wallSide = VenueMapper.wallSide(for: fixture.table)
        let serverIsOnLeft = (serverStartsOnWall && wallSide == .left) || (!serverStartsOnWall && wallSide == .right)
        
        let config = ScoreboardConfig(
            fixture: fixture,
            homePlayers: Array(selectedHome),
            awayPlayers: Array(selectedAway),
            initialServerName: selectedInitialServer,
            initialReceiverName: selectedInitialReceiver,
            serverIsOnLeft: serverIsOnLeft,
            bestOf: selectedBestOf,
            isTest: isTestMatch
        )
        path.append(config)
        showingToss = false
    }
}

// MARK: - HELPERS

struct TeamSelectionColumn: View {
    let teamName: String; let roster: [String]; @Binding var selected: Set<String>
    let limit: Int; var disabledPlayers: Set<String>; let color: Color; let onAdd: () -> Void
    var selectedArray: [String] { Array(selected).sorted() }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(teamName).font(.title2.bold()).foregroundColor(color)
            HStack(spacing: 10) {
                ForEach(0..<limit, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)).stroke(color, lineWidth: 2)
                        if index < selectedArray.count { Text(selectedArray[index]).font(.headline) }
                        else { Text("Select").font(.caption).foregroundStyle(.secondary) }
                    }.frame(height: 50)
                }
            }.padding(.bottom, 10)
            
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(roster, id: \.self) { name in
                        let isDisabled = disabledPlayers.contains(name)
                        Button(action: { if !isDisabled { toggleSelection(name) } }) {
                            HStack {
                                Text(name).font(.headline)
                                Spacer()
                                if selected.contains(name) { Image(systemName: "checkmark.circle.fill") }
                                if isDisabled { Text("Played").font(.caption).bold() }
                            }
                            .padding().frame(maxWidth: .infinity)
                            .background(selected.contains(name) ? color : Color.gray.opacity(isDisabled ? 0.05 : 0.1))
                            .foregroundColor(selected.contains(name) ? .white : (isDisabled ? .gray.opacity(0.4) : .primary))
                            .cornerRadius(10).contentShape(Rectangle())
                        }
                        .disabled(isDisabled)
                    }
                    Button(action: onAdd) { Label("Add / Search Player", systemImage: "person.badge.plus").frame(maxWidth: .infinity).padding().background(Color.gray.opacity(0.1)).foregroundColor(.primary).cornerRadius(10) }
                }
            }
        }
    }
    func toggleSelection(_ name: String) {
        if limit == 1 { if selected.contains(name) { selected.remove(name) } else { selected = [name] } }
        else { if selected.contains(name) { selected.remove(name) } else if selected.count < limit { selected.insert(name) } }
    }
}

struct TossView: View {
    let selectedHome: [String]; let selectedAway: [String]; let matchType: MatchSetupView.MatchType
    @Binding var isTestMatch: Bool; @Binding var serverStartsOnWall: Bool
    @Binding var selectedInitialServer: String; @Binding var selectedInitialReceiver: String
    let onStart: () -> Void
    var body: some View {
        VStack(spacing: 25) {
            Text("Match Toss").font(.largeTitle.bold())
            Toggle("Test Match (No Stats)", isOn: $isTestMatch).padding().background(Color.orange.opacity(0.1)).cornerRadius(8)
            VStack(alignment: .leading, spacing: 20) {
                Text("1. Who is serving first?").font(.headline)
                Picker("Server", selection: $selectedInitialServer) { ForEach(selectedHome + selectedAway, id: \.self) { Text($0).tag($0) } }.pickerStyle(.wheel).frame(height: 100)
                if matchType == .doubles {
                    Text("2. Who is receiving?").font(.headline)
                    let validReceivers = selectedHome.contains(selectedInitialServer) ? selectedAway : selectedHome
                    Picker("Receiver", selection: $selectedInitialReceiver) { ForEach(validReceivers, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                }
                Text("Position of \(selectedInitialServer)?").font(.headline)
                HStack {
                    Button("Wall Side") { serverStartsOnWall = true }.padding().frame(maxWidth: .infinity).background(serverStartsOnWall ? Color.blue : Color.gray.opacity(0.2)).foregroundColor(serverStartsOnWall ? .white : .primary).cornerRadius(10)
                    Button("Grandstand Side") { serverStartsOnWall = false }.padding().frame(maxWidth: .infinity).background(!serverStartsOnWall ? Color.blue : Color.gray.opacity(0.2)).foregroundColor(!serverStartsOnWall ? .white : .primary).cornerRadius(10)
                }
            }.padding()
            Button("START MATCH") { onStart() }.font(.title2.bold()).frame(maxWidth: .infinity, maxHeight: 60).background(Color.green).foregroundColor(.white).cornerRadius(15).padding()
        }
    }
}

// MARK: - UPDATED SEARCH SHEET
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
                // LOAD ALL PLAYERS INITIALLY
                if let players = try? await fsManager.fetchAllPlayers() {
                    searchResults = players
                }
            }
            .onChange(of: searchText) { _, nv in
                Task {
                    if nv.isEmpty {
                        // RE-LOAD ALL IF SEARCH CLEARED
                        searchResults = (try? await fsManager.fetchAllPlayers()) ?? []
                    } else {
                        searchResults = (try? await fsManager.searchPlayers(query: nv)) ?? []
                    }
                }
            }
            .navigationTitle("Search Players")
        }
    }
    
    func addNewPlayer() {
        Task {
            if let p = try? await fsManager.addNewPlayer(name: searchText) {
                onSelect(p)
                dismiss()
            }
        }
    }
}
