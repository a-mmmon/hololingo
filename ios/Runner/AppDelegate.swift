import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let visionChannelName = "hololingo/vision"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(
      with: engineBridge.pluginRegistry
    )

    let visionChannel = FlutterMethodChannel(
      name: visionChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    visionChannel.setMethodCallHandler { call, result in
      guard call.method == "removeBackground" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard #available(iOS 17.0, *) else {
        result(FlutterError(
          code: "UNSUPPORTED_IOS",
          message: "Foreground segmentation requires iOS 17 or later.",
          details: nil
        ))
        return
      }

      guard
        let args = call.arguments as? [String: Any],
        let imagePath = args["imagePath"] as? String,
        !imagePath.isEmpty
      else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Missing imagePath.",
          details: nil
        ))
        return
      }

      let centerX = args["centerX"] as? Double
      let centerY = args["centerY"] as? Double

      guard FileManager.default.fileExists(atPath: imagePath) else {
        result(FlutterError(
          code: "IMAGE_NOT_FOUND",
          message: "The captured image could not be found.",
          details: imagePath
        ))
        return
      }

      Task {
        do {
          let outputPath = try await ForegroundSegmentation.removeBackground(
            from: imagePath,
            centerX: centerX,
            centerY: centerY
          )
          result(outputPath)
        } catch {
          result(FlutterError(
            code: "VISION_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }
}
