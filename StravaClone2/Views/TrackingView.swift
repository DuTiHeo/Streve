import Combine
import MapKit
import SwiftUI

struct TrackingView: View {
    @ObservedObject var viewModel: TrackingViewModel
    @EnvironmentObject private var locationService: LocationManagerService
    @State private var cameraPosition: MapCameraPosition = .automatic

    let onClose: () -> Void

    var body: some View {
        Group {
            switch viewModel.state {
            case .completed(let session):
                SummaryView(session: session, onDone: onClose)
            default:
                trackingBody
            }
        }
        .alert("Could not save session", isPresented: Binding(
            get: { viewModel.saveErrorMessage != nil },
            set: { if !$0 { viewModel.saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveErrorMessage ?? "")
        }
    }

    private var trackingBody: some View {
        ZStack(alignment: .bottom) {
            routeMap
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if let message = viewModel.gpsSignalWeakMessage {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                TrackingHUD(viewModel: viewModel, onClose: onClose)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private var routeMap: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.coordinates.indices, id: \.self) { index in
                if viewModel.coordinates[index].count > 1 {
                    MapPolyline(coordinates: viewModel.coordinates[index])
                        .stroke(.orange, lineWidth: 4)
                }
            }

            if let location = locationService.currentLocation {
                Annotation("", coordinate: location.coordinate) {
                    HeadingLocationMarker(headingDegrees: locationService.headingDegrees)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onReceive(locationService.$currentLocation.compactMap { $0 }) { location in
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
            )
        }
    }
}

private struct HeadingLocationMarker: View {
    let headingDegrees: CLLocationDirection?

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)

            Image(systemName: "location.north.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.blue)
                .rotationEffect(.degrees(headingDegrees ?? 0))
                .animation(.easeInOut(duration: 0.12), value: headingDegrees ?? 0)

            Circle()
                .stroke(.blue.opacity(0.18), lineWidth: 10)
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel("Current location heading")
    }
}

private struct TrackingHUD: View {
    @ObservedObject var viewModel: TrackingViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                StatBlock(value: viewModel.elapsedTime, label: "Time")
                StatBlock(value: viewModel.totalDistance, label: "Distance")
                StatBlock(value: "\(viewModel.currentPace) /km", label: "Pace")
            }

            Divider()

            HStack(spacing: 12) {
                pauseResumeButton

                Button(role: .destructive) {
                    viewModel.tapFinish()
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(viewModel.state == .finishing)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if viewModel.state == .finishing {
                ProgressView()
                    .padding(12)
            }
        }
    }

    private var pauseResumeButton: some View {
        Button {
            if viewModel.state == .paused {
                viewModel.tapResume()
            } else {
                viewModel.tapPause()
            }
        } label: {
            Label(
                viewModel.state == .paused ? "Resume" : "Pause",
                systemImage: viewModel.state == .paused ? "play.fill" : "pause.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.state == .finishing)
    }
}

private struct StatBlock: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}
