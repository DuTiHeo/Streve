import CoreLocation
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .tint(.orange)
    }
}

struct HomeView: View {
    @EnvironmentObject private var locationService: LocationManagerService
    @StateObject private var trackingViewModel = TrackingViewModel()
    @State private var selectedType: ActivityType = .run
    @State private var showingTracking = false

    private var startIsDisabled: Bool {
        locationService.authStatus == .denied || locationService.authStatus == .restricted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity Tracker")
                        .font(.largeTitle.bold())
                    Text("Track a run, walk, or ride with GPS, live stats, and local history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    ForEach(ActivityType.allCases) { type in
                        ActivityTypeButton(
                            type: type,
                            isSelected: selectedType == type
                        ) {
                            selectedType = type
                        }
                    }
                }

                if startIsDisabled {
                    PermissionDeniedView()
                }

                Button {
                    trackingViewModel.tapStart(type: selectedType)
                    showingTracking = true
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(startIsDisabled)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                locationService.requestAuthorization()
            }
            .fullScreenCover(isPresented: $showingTracking) {
                TrackingView(viewModel: trackingViewModel) {
                    showingTracking = false
                    trackingViewModel.reset()
                }
            }
        }
    }
}

private struct ActivityTypeButton: View {
    let type: ActivityType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.title2)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.orange : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color(.separator), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Location permission is required to record a route.", systemImage: "location.slash")
                .font(.subheadline)

            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
