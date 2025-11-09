//
//  CornerMarkersOverlay.swift
//  CarcassoneAR
//
//  Overlay to show projected corner markers on AR camera view
//

import SwiftUI

struct CornerMarkersOverlay: View {
    let corners: [CGPoint]

    var body: some View {
        GeometryReader { geometry in
            // Get the screen dimensions
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // ARKit camera image is 1920x1440 in landscape
            // But displayed on screen in portrait, so we need to rotate coordinates
            let imageWidth: CGFloat = 1920.0
            let imageHeight: CGFloat = 1440.0

            Canvas { context, size in
                // Convert image coordinates to screen coordinates
                // Camera image is 1920x1440 in landscape, displayed in portrait
                // So we need to rotate: screen_x = imageHeight - image_y, screen_y = image_x

                let scaledCorners = corners.map { imagePoint -> CGPoint in
                    // Rotate from landscape to portrait
                    let portraitX = imageHeight - imagePoint.y
                    let portraitY = imagePoint.x

                    // Scale from image coordinates to screen coordinates
                    let screenX = (portraitX / imageHeight) * screenWidth
                    let screenY = (portraitY / imageWidth) * screenHeight

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
