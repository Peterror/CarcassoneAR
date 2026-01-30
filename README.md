# CarcassoneAR

An iOS augmented reality app that enhances the Carcassonne board game experience. Point your camera at the game board and get intelligent assistance.

## Features

**Implemented:**
- AR plane detection and board capture
- Perspective transformation to top-down view
- Image export for ML training data collection

**Planned:**
- Tile detection (YOLO)
- Tile classification (MobileNetV2)
- Remaining tiles tracking
- Valid placement suggestions
- Probability calculations

## Requirements

- iOS 26.0+
- Physical device with ARKit support (iPhone/iPad)

## Tech Stack

- ARKit & RealityKit
- Core Image
- CoreML
- SwiftUI

## Project Structure

```
CarcassoneAR/
├── Models/          # Data models
├── Utilities/       # Image processing, logging
└── Views/           # SwiftUI views and AR components
```

## Documentation

See [Technical Design](TECHNICAL_DESIGN.md) for architecture and implementation details.

## License

[MIT](LICENSE)
