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
            // Get the screen dimensions
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // Get actual camera image dimensions
            let imageWidth = imageSize.width
            let imageHeight = imageSize.height

            Canvas { context, size in
                // Convert image coordinates to screen coordinates
                // Camera image (landscape) needs to be rotated to portrait for display
                // Then scaled to fill screen (aspect fill), which may crop edges

                let scaledCorners = corners.map { imagePoint -> CGPoint in
                    // Step 1: Rotate from landscape to portrait orientation
                    // Landscape (W×H) → Portrait: x' = H - y, y' = x
                    let portraitX = imageHeight - imagePoint.y
                    let portraitY = imagePoint.x

                    // Step 2: Calculate how the portrait image is scaled to fill the screen
                    // ARView uses aspect fill, so it scales to cover the entire screen
                    let imageAspect = imageHeight / imageWidth  // Portrait image aspect ratio
                    let screenAspect = screenHeight / screenWidth

                    // Determine scale factor and visible region
                    let scale: CGFloat
                    let offsetX: CGFloat
                    let offsetY: CGFloat

                    if imageAspect > screenAspect {
                        // Image is taller relative to screen - width fills, height is cropped
                        scale = screenWidth / imageHeight
                        offsetX = 0
                        offsetY = (screenHeight - imageWidth * scale) / 2
                    } else {
                        // Image is wider relative to screen - height fills, width is cropped
                        scale = screenHeight / imageWidth
                        offsetX = (screenWidth - imageHeight * scale) / 2
                        offsetY = 0
                    }

                    // Step 3: Apply scale and offset to get final screen coordinates
                    let screenX = portraitX * scale + offsetX
                    let screenY = portraitY * scale + offsetY

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
