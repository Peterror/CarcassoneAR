//
//  ImageExporter.swift
//  CarcassoneAR
//
//  Exports captured and transformed images to Photos Library for ML training data collection.
//

import UIKit
import Photos
import OSLog

/// Result type for image export operations
enum ExportResult {
    case success(assetIdentifier: String)
    case failure(error: Error)

    var localizedMessage: String {
        switch self {
        case .success:
            return "Image saved to Photos"
        case .failure(let error):
            return "Export failed: \(error.localizedDescription)"
        }
    }
}

/// Error types specific to image export operations
enum ExportError: LocalizedError {
    case photoLibraryAccessDenied
    case photoLibraryAccessRestricted
    case imageConversionFailed
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photos access denied. Enable in Settings > CarcassoneAR > Photos."
        case .photoLibraryAccessRestricted:
            return "Photos access restricted by device policy."
        case .imageConversionFailed:
            return "Failed to convert image to PNG format."
        case .saveFailed(let error):
            return "Failed to save image: \(error.localizedDescription)"
        }
    }
}

/// Utility class for exporting captured AR images to Photos Library
@MainActor
class ImageExporter {

    // MARK: - Public Interface

    /// Exports a captured frame to Photos Library with metadata
    /// - Parameters:
    ///   - capturedFrame: The frame containing image and transformation data
    ///   - completion: Callback with export result
    func exportToPhotos(
        capturedFrame: CapturedFrame,
        completion: @escaping (ExportResult) -> Void
    ) {
        AppLogger.imageExporter.info("Starting export to Photos Library")

        Task {
            do {
                // Request authorization
                let status = await requestPhotoLibraryAuthorization()
                guard status == .authorized else {
                    throw authorizationError(for: status)
                }

                // Convert UIImage to PNG data
                guard let pngData = capturedFrame.image.pngData() else {
                    AppLogger.imageExporter.error("Failed to convert UIImage to PNG data")
                    throw ExportError.imageConversionFailed
                }

                // Generate filename with quality metrics
                let filename = generateFilename(from: capturedFrame)

                // Save to Photos Library
                let assetIdentifier = try await saveImageToPhotos(
                    imageData: pngData,
                    filename: filename
                )

                AppLogger.imageExporter.notice("✅ Successfully exported image: \(filename)")
                completion(.success(assetIdentifier: assetIdentifier))

            } catch {
                AppLogger.imageExporter.error("❌ Export failed: \(error.localizedDescription)")
                completion(.failure(error: error))
            }
        }
    }

    // MARK: - Private Helpers

    /// Requests Photos Library authorization using modern async API
    private func requestPhotoLibraryAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .notDetermined:
            AppLogger.imageExporter.debug("Requesting Photos Library authorization")
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        case .authorized, .limited:
            return status
        case .denied, .restricted:
            AppLogger.imageExporter.warning("Photos access not granted: \(String(describing: status))")
            return status
        @unknown default:
            AppLogger.imageExporter.warning("Unknown authorization status: \(String(describing: status))")
            return status
        }
    }

    /// Converts PHAuthorizationStatus to appropriate error
    private func authorizationError(for status: PHAuthorizationStatus) -> ExportError {
        switch status {
        case .denied:
            return .photoLibraryAccessDenied
        case .restricted:
            return .photoLibraryAccessRestricted
        default:
            return .photoLibraryAccessDenied
        }
    }

    /// Generates filename with timestamp and quality metrics
    /// Format: carcassonne_YYYYMMDD_HHmmss_ppmQQQQ.png
    /// Where QQQQ = pixels per meter (e.g., 847 ppm → "ppm0847")
    private func generateFilename(from frame: CapturedFrame) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date(timeIntervalSince1970: frame.transform.timestamp))

        let qualityScore = Int(frame.transform.quality.estimatedPixelsPerMeter)
        let qualityString = String(format: "%04d", min(9999, max(0, qualityScore)))

        return "carcassonne_\(timestamp)_ppm\(qualityString).png"
    }

    /// Saves image data to Photos Library with embedded filename
    private func saveImageToPhotos(
        imageData: Data,
        filename: String
    ) async throws -> String {

        var assetIdentifier: String?

        try await PHPhotoLibrary.shared().performChanges {
            // Create image creation request
            let creationRequest = PHAssetCreationRequest.forAsset()

            // Add image data with filename as resource options
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            creationRequest.addResource(with: .photo, data: imageData, options: options)

            // Store placeholder identifier
            assetIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
        }

        guard let identifier = assetIdentifier else {
            throw ExportError.saveFailed(underlying: NSError(
                domain: "ImageExporter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get asset identifier"]
            ))
        }

        AppLogger.imageExporter.info("Image saved to Photos Library: \(filename)")
        return identifier
    }
}
