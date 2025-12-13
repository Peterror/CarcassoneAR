//
//  View2D.swift
//  CarcassoneAR
//
//  2D view showing captured camera image with corner markers
//

import SwiftUI
import OSLog

struct View2D: View {
    @Binding var viewMode: ViewMode
    var capturedFrame: CapturedFrame?

    @State private var transformedImage: UIImage?
    @State private var isProcessing: Bool = false
    @State private var showTransformed: Bool = true  // Default to transformed view
    @State private var isExporting: Bool = false
    @State private var showExportAlert: Bool = false
    @State private var exportAlertMessage: String = ""

    private let imageExporter = ImageExporter()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Placeholder background
                Color.gray.opacity(0.2)
                    .edgesIgnoringSafeArea(.all)

                if let frame = capturedFrame {
                    let plane = frame.planeData

                    VStack(spacing: 20) {
                        Spacer()

                        // Title and quality indicator
                        VStack(spacing: 8) {
                            Text("Captured View")
                                .font(.title2)
                                .foregroundColor(.black)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(frame.transform.quality.isGoodQuality ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(frame.transform.quality.qualityDescription)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }

                        // Show image based on toggle state
                        ZStack {
                            if showTransformed, let transformed = transformedImage {
                                // Show transformed (top-down) view
                                Image(uiImage: transformed)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width - 40)
                                    .cornerRadius(8)
                            } else if isProcessing {
                                // Show processing indicator
                                VStack {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                    Text("Applying transformation...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.top, 8)
                                }
                                .frame(maxWidth: geometry.size.width - 40, minHeight: 300)
                            } else {
                                // Show original camera image
                                Image(uiImage: frame.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width - 40)
                                    .cornerRadius(8)
                            }

                            // Overlay corner markers ONLY on original view
                            if !showTransformed || transformedImage == nil {
                                GeometryReader { imageGeometry in
                                Canvas { context, size in
                                    let corners = frame.transform.portraitCorners

                                    // Get actual image dimensions
                                    let imageWidth = frame.image.size.width
                                    let imageHeight = frame.image.size.height

                                    // Scale to displayed size
                                    let displayWidth = imageGeometry.size.width
                                    let displayHeight = imageGeometry.size.height

                                    let scaleX = displayWidth / imageWidth
                                    let scaleY = displayHeight / imageHeight

                                    // Convert corners to display coordinates
                                    let displayCorners = corners.map { corner -> CGPoint in
                                        CGPoint(
                                            x: corner.x * scaleX,
                                            y: corner.y * scaleY
                                        )
                                    }

                                    // Draw quadrilateral
                                    var path = Path()
                                    path.move(to: displayCorners[0])
                                    path.addLine(to: displayCorners[1])
                                    path.addLine(to: displayCorners[2])
                                    path.addLine(to: displayCorners[3])
                                    path.closeSubpath()

                                    context.stroke(path, with: .color(.yellow), lineWidth: 2)

                                    // Draw corner circles
                                    let labels = ["TL", "TR", "BR", "BL"]
                                    for (index, corner) in displayCorners.enumerated() {
                                        let circle = Path(ellipseIn: CGRect(
                                            x: corner.x - 8,
                                            y: corner.y - 8,
                                            width: 16,
                                            height: 16
                                        ))
                                        context.fill(circle, with: .color(.red))

                                        let text = Text(labels[index])
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                        context.draw(text, at: CGPoint(x: corner.x, y: corner.y - 18))
                                    }
                                }
                            }
                            .frame(maxWidth: geometry.size.width - 40)
                            .aspectRatio(frame.image.size.width / frame.image.size.height, contentMode: .fit)
                            }  // End of if !showTransformed
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )

                        // Dimensions and camera angle
                        VStack(spacing: 4) {
                            Text(String(format: "%.2fm × %.2fm", plane.width, plane.height))
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(String(format: "Camera angle: %.1f°", frame.transform.quality.cameraAngleDegrees))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Spacer()
                    }
                } else {
                    // No captured frame available
                    VStack {
                        Text("No capture available")
                            .font(.title2)
                            .foregroundColor(.black)

                        Text("Return to AR view to scan and capture a surface")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                }

                // Bottom button bar with Toggle, Export, and 3D buttons
                VStack {
                    Spacer()

                    HStack {
                        // Toggle button (only shown when frame is captured)
                        if capturedFrame != nil {
                            Button(action: {
                                AppLogger.view2D.notice("Toggle view button tapped - switching to \(showTransformed ? "original" : "transformed")")
                                showTransformed.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: showTransformed ? "photo" : "grid")
                                    Text(showTransformed ? "Original" : "Top-Down")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.7))
                                .cornerRadius(10)
                            }
                            .disabled(isProcessing)
                        }

                        Spacer()

                        // Export button (only shown when transformed image is available)
                        if capturedFrame != nil, let transformed = transformedImage {
                            Button(action: {
                                exportImage(transformed)
                            }) {
                                HStack(spacing: 6) {
                                    if isExporting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                    Text("Export")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.7))
                                .cornerRadius(10)
                            }
                            .disabled(isExporting || isProcessing)
                        }

                        Spacer()

                        Button(action: {
                            AppLogger.view2D.notice("3D button tapped")
                            viewMode = .ar
                        }) {
                            Text("3D")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
                }
            }
        }
        .alert("Export Result", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportAlertMessage)
        }
        .task(id: capturedFrame?.transform.timestamp) {
            // Apply perspective transformation when a new frame is captured
            guard let frame = capturedFrame else {
                transformedImage = nil
                return
            }

            // Reset state for new frame
            transformedImage = nil
            isProcessing = true

            AppLogger.view2D.info("Starting perspective transformation...")

            // Perform transformation (runs on main actor)
            let result = ImageTransformProcessor.applyPerspectiveCorrection(
                image: frame.image,
                perspectiveTransform: frame.transform
            )

            // Update state
            self.transformedImage = result
            self.isProcessing = false

            if result != nil {
                AppLogger.view2D.info("Perspective transformation completed successfully")
            } else {
                AppLogger.view2D.error("Perspective transformation failed")
            }
        }
    }

    // MARK: - Export Function

    private func exportImage(_ transformedImage: UIImage) {
        guard let frame = capturedFrame else {
            AppLogger.view2D.error("Cannot export: no captured frame available")
            return
        }

        AppLogger.view2D.notice("Export button tapped")
        isExporting = true

        // Create a new CapturedFrame with the transformed image for export
        let exportFrame = CapturedFrame(
            image: transformedImage,
            transform: frame.transform,
            planeData: frame.planeData,
            cameraTransform: frame.cameraTransform
        )

        imageExporter.exportToPhotos(capturedFrame: exportFrame) { result in
            isExporting = false

            switch result {
            case .success:
                exportAlertMessage = "Image successfully saved to Photos Library!\n\nYou can find it in the Recents album."
                AppLogger.view2D.notice("Export successful")
            case .failure(let error):
                exportAlertMessage = error.localizedDescription
                AppLogger.view2D.error("Export failed: \(error.localizedDescription)")
            }

            showExportAlert = true
        }
    }
}
