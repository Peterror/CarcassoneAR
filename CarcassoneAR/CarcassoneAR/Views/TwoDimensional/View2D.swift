//
//  View2D.swift
//  CarcassoneAR
//
//  2D view showing captured camera image with corner markers
//

import SwiftUI

struct View2D: View {
    @Binding var viewMode: ViewMode
    var capturedFrame: CapturedFrame?

    @State private var transformedImage: UIImage?
    @State private var isProcessing: Bool = false

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

                        // Show untransformed camera image with corner overlay
                        ZStack {
                            Image(uiImage: frame.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width - 40)
                                .cornerRadius(8)

                            // Overlay corner markers on the image
                            GeometryReader { imageGeometry in
                                Canvas { context, size in
                                    let corners = frame.transform.sourceCorners

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

                // 3D Button positioned at bottom right
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        Button(action: {
                            print("3D button tapped")
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
    }
}
