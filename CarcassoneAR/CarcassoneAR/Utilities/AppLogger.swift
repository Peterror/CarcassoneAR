//
//  AppLogger.swift
//  CarcassoneAR
//
//  Centralized logging configuration using Apple's Unified Logging system (os.Logger).
//  Provides category-specific loggers for structured, filterable logging.
//

import OSLog

/// Centralized logging utility for the CarcassoneAR application.
///
/// Provides pre-configured Logger instances for each major component of the app.
/// All loggers share the same subsystem (bundle identifier) but use different
/// categories to allow filtering by class or module.
///
/// Usage:
/// ```swift
/// AppLogger.arCoordinator.info("Plane detected")
/// AppLogger.transformCalculator.debug("Corner: \(corner)")
/// AppLogger.imageProcessor.error("Failed to create CGImage")
/// ```
///
/// Filtering in Console.app:
/// - By subsystem: `subsystem:Peterror.CarcassoneAR`
/// - By category: `category:ARViewContainer.Coordinator`
/// - By level: `level:error`
/// - Combined: `subsystem:Peterror.CarcassoneAR category:PerspectiveTransformCalculator level:debug`
struct AppLogger {
    /// The subsystem identifier for all loggers (matches bundle identifier)
    private static let subsystem = "Peterror.CarcassoneAR"

    // MARK: - ARKit Component Loggers

    /// Logger for ARViewContainer.Coordinator class
    /// Handles AR session coordination, frame capture, and visualization updates
    static let arCoordinator = Logger(subsystem: subsystem, category: "ARViewContainer.Coordinator")

    /// Logger for ARViewContainer.PlaneDetectionDelegate class
    /// Handles plane detection events from ARSession
    static let planeDetection = Logger(subsystem: subsystem, category: "ARViewContainer.PlaneDetectionDelegate")

    // MARK: - Perspective Transform Loggers

    /// Logger for PerspectiveTransformCalculator class
    /// Handles geometric calculations, 3D→2D projections, and quality validation
    static let transformCalculator = Logger(subsystem: subsystem, category: "PerspectiveTransformCalculator")

    /// Logger for ImageTransformProcessor class
    /// Handles Core Image perspective correction and image transformations
    static let imageProcessor = Logger(subsystem: subsystem, category: "ImageTransformProcessor")

    // MARK: - View Loggers

    /// Logger for ContentView
    /// Handles main view user interactions and state management
    static let contentView = Logger(subsystem: subsystem, category: "ContentView")

    /// Logger for View2D
    /// Handles 2D view user interactions and display
    static let view2D = Logger(subsystem: subsystem, category: "View2D")

    // MARK: - Export Loggers

    /// Logger for ImageExporter class
    /// Handles image export operations to Photos Library
    static let imageExporter = Logger(subsystem: subsystem, category: "ImageExporter")
}
