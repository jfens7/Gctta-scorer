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
    @StateObject var fsManager = FirestoreManager()
    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                VStack {
                    if fsManager.liveFixtures.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("No Fixtures Found for Today")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("Ensure the iPad date matches the Fixture date in Firebase.")
                                .font(.caption)
                        }
                    } else {
                        List(fsManager.liveFixtures) { fixture in
                            NavigationLink(value: fixture) {
                                HStack {
                                    Text("Table \(fixture.table)")
                                        .font(.title3.bold())
                                        .frame(width: 80, alignment: .leading)
                                        .foregroundColor(.yellow)
                                    
                                    VStack(alignment: .leading) {
                                        Text("\(fixture.homeTeam) vs \(fixture.awayTeam)")
                                            .font(.headline)
                                        Text(fixture.division)
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                .navigationTitle("Select Fixture")
                .navigationDestination(for: Fixture.self) { fixture in
                    MatchSetupView(fsManager: fsManager, fixture: fixture, path: $path)
                }
                .navigationDestination(for: ScoreboardConfig.self) { config in
                    ScoreboardView(config: config, path: $path)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
