import MapKit
import SwiftUI
import UIKit

struct SummaryView: View {
    let session: ActivitySession
    var onDone: (() -> Void)?

    @State private var snapshotImage: UIImage?
    @State private var isExportingPNG = false
    @State private var isExportingVideo = false
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var saveConfirmation: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    snapshot
                    statsGrid
                    exportButtons
                }
                .padding(20)
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: onDone)
                    }
                }
            }
            .task(id: session.id) {
                snapshotImage = await makeSnapshot()
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: item.items)
            }
            .alert("Export failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .alert("Saved", isPresented: Binding(
                get: { saveConfirmation != nil },
                set: { if !$0 { saveConfirmation = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveConfirmation ?? "")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: session.activityType.icon)
                .font(.title)
                .foregroundStyle(.orange)
                .frame(width: 48, height: 48)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.activityType.rawValue)
                    .font(.title2.bold())
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var snapshot: some View {
        Group {
            if let snapshotImage {
                Image(uiImage: snapshotImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryStat(title: "Distance", value: session.totalDistance.kilometersText, icon: "point.topleft.down.curvedto.point.bottomright.up")
            SummaryStat(title: "Duration", value: session.totalDuration.longClockText, icon: "timer")
            SummaryStat(title: "Pace", value: "\(session.averagePace.paceText) /km", icon: "speedometer")
            SummaryStat(title: "Elevation", value: session.elevationGain.metersText, icon: "mountain.2")
        }
    }

    private var exportButtons: some View {
        VStack(spacing: 12) {
            Button {
                exportPNG()
            } label: {
                if isExportingPNG {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Share PNG", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isExportingPNG || isExportingVideo)

            Button {
                savePNGToPhotos()
            } label: {
                if isExportingPNG {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Save PNG to Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExportingPNG || isExportingVideo)

            Button {
                exportFlyover()
            } label: {
                if isExportingVideo {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Share Flyover Video", systemImage: "video")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExportingPNG || isExportingVideo)

            Button {
                saveFlyoverToPhotos()
            } label: {
                if isExportingVideo {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Save Video to Photos", systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExportingPNG || isExportingVideo)
        }
    }

    private func exportPNG() {
        isExportingPNG = true
        Task { @MainActor in
            do {
                let url = try PNGExportService().writePNGFile(session: session)
                isExportingPNG = false
                shareItem = ShareItem(items: [PNGShareItemSource(fileURL: url)])
            } catch {
                isExportingPNG = false
                exportError = error.localizedDescription
            }
        }
    }

    private func savePNGToPhotos() {
        isExportingPNG = true
        Task { @MainActor in
            do {
                let url = try PNGExportService().writePNGFile(session: session)
                try await PhotoLibrarySaveService().savePhoto(fileURL: url)
                isExportingPNG = false
                saveConfirmation = "PNG image was saved to Photos."
            } catch {
                isExportingPNG = false
                exportError = error.localizedDescription
            }
        }
    }

    private func exportFlyover() {
        isExportingVideo = true
        Task { @MainActor in
            do {
                let url = try await FlyoverExportService().export(session: session)
                isExportingVideo = false
                shareItem = ShareItem(items: [url])
            } catch {
                isExportingVideo = false
                exportError = error.localizedDescription
            }
        }
    }

    private func saveFlyoverToPhotos() {
        isExportingVideo = true
        Task { @MainActor in
            do {
                let url = try await FlyoverExportService().export(session: session)
                try await PhotoLibrarySaveService().saveVideo(fileURL: url)
                isExportingVideo = false
                saveConfirmation = "Flyover video was saved to Photos."
            } catch {
                isExportingVideo = false
                exportError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func makeSnapshot() async -> UIImage? {
        let coordinates = session.coordinates
        guard !coordinates.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = coordinates.boundingRegion
        options.size = CGSize(width: 900, height: 540)
        options.scale = UIScreen.main.scale
        options.mapType = .standard

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)

                let path = UIBezierPath()
                for (index, coordinate) in coordinates.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                UIColor.orange.setStroke()
                path.lineWidth = 5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        } catch {
            return nil
        }
    }
}

private struct SummaryStat: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
