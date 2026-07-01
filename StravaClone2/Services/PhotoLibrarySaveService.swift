import Foundation
import Photos

enum PhotoLibrarySaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo Library permission was not granted."
        case .saveFailed:
            return "Could not save the export to Photos."
        }
    }
}

final class PhotoLibrarySaveService {
    func savePhoto(fileURL: URL) async throws {
        try await save(fileURL: fileURL, resourceType: .photo)
    }

    func saveVideo(fileURL: URL) async throws {
        try await save(fileURL: fileURL, resourceType: .video)
    }

    private func save(fileURL: URL, resourceType: PHAssetResourceType) async throws {
        try await requestAddPermission()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: resourceType, fileURL: fileURL, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoLibrarySaveError.saveFailed)
                }
            }
        }
    }

    private func requestAddPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus == .authorized || newStatus == .limited {
                return
            }
            throw PhotoLibrarySaveError.permissionDenied
        default:
            throw PhotoLibrarySaveError.permissionDenied
        }
    }
}
