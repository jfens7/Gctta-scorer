//
//  MatchListView.swift
//  Gctta-scorer
//
//  Created by Jakob Fensom on 6/2/2026.
//


import SwiftUI

struct MatchListView: View {
    @StateObject var fsManager = FirestoreManager()
    @State private var path = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                if fsManager.liveFixtures.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Waiting for Matches...")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Add a match in Firebase\nwith today's date (dd/MM/yyyy)")
                            .multilineTextAlignment(.center)
                            .font(.caption)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 20) {
                            ForEach(fsManager.liveFixtures) { fixture in
                                NavigationLink(value: fixture) {
                                    FixtureCard(fixture: fixture)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Today's Fixtures")
            .navigationDestination(for: Fixture.self) { fixture in
                MatchSetupView(fsManager: fsManager, fixture: fixture, path: $path)
            }
            .navigationDestination(for: ScoreboardConfig.self) { config in
                ScoreboardView(config: config, path: $path)
            }
        }
    }
}

struct FixtureCard: View {
    let fixture: Fixture
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TABLE \(fixture.table)")
                    .font(.caption)
                    .fontWeight(.black)
                    .padding(5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(5)
                Spacer()
                Text(fixture.division)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(fixture.homeTeam)
                    .font(.title2.bold())
                    .foregroundColor(.blue)
                Text("vs")
                    .foregroundColor(.gray)
                Text(fixture.awayTeam)
                    .font(.title2.bold())
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
