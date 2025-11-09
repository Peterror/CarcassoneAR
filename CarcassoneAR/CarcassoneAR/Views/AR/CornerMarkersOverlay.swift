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
                // Overlay disabled - no visual markers shown
                // TODO: Enable this overlay for debugging
            }
        }
        .allowsHitTesting(false) // Don't intercept touches
    }
}
