//
//  CornerMarkersOverlay.swift
//  CarcassoneAR
//
//  Overlay to show projected corner markers on AR camera view
//

import SwiftUI

struct CornerMarkersOverlay: View {
    let corners: [CGPoint]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            // Determine orientation from geometry
            let isLandscape = geometry.size.width > geometry.size.height

            // Get the screen dimensions
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // Get actual camera image dimensions
            let imageWidth = imageSize.width
            let imageHeight = imageSize.height

            Canvas { context, size in
                // Convert image coordinates to screen coordinates
                // Camera image buffer is always landscape (W×H)
                // Display can be portrait or landscape right
                let scaledCorners = corners.map { imagePoint -> CGPoint in
                    // Step 1: Rotate based on device orientation
                    // Camera buffer is always landscape (W×H)
                    // Corners are projected to camera buffer coordinates (landscape)
                    let rotatedPoint: CGPoint

                    if isLandscape {
                        // Landscape Right: NO rotation needed!
                        // Camera buffer is landscape, screen is landscape - coordinates match
                        rotatedPoint = imagePoint
                    } else {
                        // Portrait: Rotate 90° clockwise
                        // Landscape buffer (W×H) → Portrait display: x' = H - y, y' = x
                        rotatedPoint = CGPoint(
                            x: imageHeight - imagePoint.y,
                            y: imagePoint.x
                        )
                    }

                    // Step 2: Calculate how the rotated image is scaled to fill the screen
                    // ARView uses aspect fill, so it scales to cover the entire screen
                    let displayWidth: CGFloat
                    let displayHeight: CGFloat

                    if isLandscape {
                        // Landscape: image dimensions match display orientation
                        displayWidth = imageWidth
                        displayHeight = imageHeight
                    } else {
                        // Portrait: image dimensions are rotated
                        displayWidth = imageHeight
                        displayHeight = imageWidth
                    }

                    let imageAspect = displayHeight / displayWidth
                    let screenAspect = screenHeight / screenWidth

                    // Determine scale factor and visible region
                    let scale: CGFloat
                    let offsetX: CGFloat
                    let offsetY: CGFloat

                    if imageAspect > screenAspect {
                        // Image is taller relative to screen - width fills, height is cropped
                        scale = screenWidth / displayWidth
                        offsetX = 0
                        offsetY = (screenHeight - displayHeight * scale) / 2
                    } else {
                        // Image is wider relative to screen - height fills, width is cropped
                        scale = screenHeight / displayHeight
                        offsetX = (screenWidth - displayWidth * scale) / 2
                        offsetY = 0
                    }

                    // Step 3: Apply scale and offset to get final screen coordinates
                    let screenX = rotatedPoint.x * scale + offsetX
                    let screenY = rotatedPoint.y * scale + offsetY

                    return CGPoint(x: screenX, y: screenY)
                }

                // Corner labels: TL, TR, BR, BL
                let labels = ["TL", "TR", "BR", "BL"]

                // Draw corner markers
                for (index, corner) in scaledCorners.enumerated() {
                    // Draw outer circle (white with transparency)
                    let outerCircle = Circle()
                        .path(in: CGRect(x: corner.x - 15, y: corner.y - 15, width: 30, height: 30))
                    context.stroke(outerCircle, with: .color(.white.opacity(0.8)), lineWidth: 1)

                    // Draw inner circle (cyan solid)
                    let innerCircle = Circle()
                        .path(in: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10))
                    context.fill(innerCircle, with: .color(.cyan))

                    // Draw label
                    if index < labels.count {
                        let label = labels[index]
                        let textPosition = CGPoint(x: corner.x + 20, y: corner.y - 10)
                        context.draw(
                            Text(label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white),
                            at: textPosition
                        )
                    }
                }

                // Draw lines connecting corners to show capture region boundary
                if scaledCorners.count == 4 {
                    var path = Path()
                    path.move(to: scaledCorners[0])
                    path.addLine(to: scaledCorners[1])
                    path.addLine(to: scaledCorners[2])
                    path.addLine(to: scaledCorners[3])
                    path.closeSubpath()

                    context.stroke(path, with: .color(.green.opacity(0.6)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false) // Don't intercept touches
    }
}
