import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "shared_flutter_engine")
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let channel = FlutterMethodChannel(
      name: "com.samtigis.client/background_task",
      binaryMessenger: flutterEngine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(false)
        return
      }

      switch call.method {
      case "beginBackgroundTask":
        if self.backgroundTaskId != .invalid {
          UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
          self.backgroundTaskId = .invalid
        }
        self.backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "SamConnectedSync") {
          if self.backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
            self.backgroundTaskId = .invalid
          }
        }
        result(self.backgroundTaskId != .invalid)

      case "endBackgroundTask":
        if self.backgroundTaskId != .invalid {
          UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
          self.backgroundTaskId = .invalid
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - UISceneSession Lifecycle
  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    return UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
  }

  override func application(
    _ application: UIApplication,
    didDiscardSceneSessions sceneSessions: Set<UISceneSession>
  ) {}
}
