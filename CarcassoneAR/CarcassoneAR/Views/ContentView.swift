//
//  ContentView.swift
//  CarcassoneAR
//
//  Created by Piotr Zieliński on 14/10/2025.
//

import SwiftUI

enum ViewMode {
    case ar
    case view2D
}

struct ContentView: View {
    @State private var viewMode: ViewMode = .ar
    @State private var resetTrigger: Bool = false
    @State private var planeData: PlaneData?
    @State private var capturedFrame: CapturedFrame?
    @State private var captureNow: Bool = false
    @State private var projectedCorners: [CGPoint]?
    @State private var cameraImageSize: CGSize = .zero
    @State private var pendingViewSwitch: Bool = false

    var body: some View {
        ZStack {
            // AR Camera View - Only render when in AR mode
            if viewMode == .ar {
                ARViewContainer(
                    planeData: $planeData,
                    capturedFrame: $capturedFrame,
                    resetTrigger: $resetTrigger,
                    captureNow: $captureNow,
                    projectedCorners: $projectedCorners,
                    cameraImageSize: $cameraImageSize
                )
                .edgesIgnoringSafeArea(.all)

                // Corner markers overlay - must also ignore safe area to match ARView coordinate system
                if let corners = projectedCorners, cameraImageSize != .zero {
                    CornerMarkersOverlay(corners: corners, imageSize: cameraImageSize)
                        .edgesIgnoringSafeArea(.all)
                }

                // UI Overlay for AR View
                VStack {
                    // Status indicator at top
                    HStack {
                        Spacer()

                        if planeData != nil {
                            // Plane detected
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Surface Detected")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                        } else {
                            // Scanning
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                                Text("Scanning...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                        }

                        Spacer()
                    }
                    .padding(.top, 50)

                    Spacer()

                    HStack {
                        // Reset Button
                        Button(action: {
                            print("Reset button tapped")
                            resetTrigger = true
                        }) {
                            Text("Reset")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }

                        Spacer()

                        // 2D Button - disabled until plane detected
                        Button(action: {
                            // Trigger camera frame capture and mark that we want to switch views
                            captureNow = true
                            pendingViewSwitch = true
                        }) {
                            Text("2D")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(planeData != nil ? .white : .gray)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(planeData != nil ? Color.black.opacity(0.7) : Color.black.opacity(0.3))
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .disabled(planeData == nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
                }
            } else {
                // 2D View
                View2D(viewMode: $viewMode, capturedFrame: capturedFrame)
            }
        }
        .onChange(of: capturedFrame) { oldValue, newValue in
            // When a new frame is captured and we're waiting to switch views, do it now
            if pendingViewSwitch && newValue != nil {
                viewMode = .view2D
                pendingViewSwitch = false
            }
        }
    }
}

#Preview {
    ContentView()
}
