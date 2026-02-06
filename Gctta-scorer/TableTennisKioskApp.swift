import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct TableTennisKioskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var path = NavigationPath()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                LobbyView(path: $path)
                    .navigationDestination(for: Fixture.self) { fixture in
                        MatchSetupView(fsManager: FirestoreManager(), fixture: fixture, path: $path)
                    }
                    .navigationDestination(for: ScoreboardConfig.self) { config in
                        ScoreboardView(config: config, path: $path)
                    }
            }
        }
    }
}

struct LobbyView: View {
    @Binding var path: NavigationPath
    @StateObject var fsManager = FirestoreManager()
    @State private var fixtures: [Fixture] = []
    
    var body: some View {
        ScrollView {
            if fixtures.isEmpty {
                ContentUnavailableView("No Matches Today", systemImage: "calendar")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(fixtures) { fixture in
                        Button {
                            path.append(fixture)
                        } label: {
                            VStack(spacing: 10) {
                                Text("Table \(fixture.table)").font(.system(size: 40, weight: .black))
                                Text("\(fixture.homeTeam) vs \(fixture.awayTeam)").font(.headline)
                                Text(fixture.division).font(.subheadline).opacity(0.8)
                            }
                            .frame(height: 180).frame(maxWidth: .infinity)
                            .background(Color.blue.gradient).foregroundColor(.white)
                            .cornerRadius(15).shadow(radius: 5)
                        }
                    }
                }.padding()
            }
        }
        .navigationTitle("Match Lobby")
        .task {
            do { fixtures = try await fsManager.fetchSmartLaunchFixtures() } catch { print("Error: \(error)") }
        }
    }
}
