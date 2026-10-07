import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "shared_flutter_engine")
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private let refreshTaskIdentifier = "com.samtigis.client.refresh"

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

    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { [weak self] task in
        if let refreshTask = task as? BGAppRefreshTask {
          self?.handleAppRefresh(task: refreshTask)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @available(iOS 13.0, *)
  func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("[BGTask] Error scheduling BGAppRefresh: \(error)")
    }
  }

  @available(iOS 13.0, *)
  private func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleAppRefresh()

    let channel = FlutterMethodChannel(
      name: "com.samtigis.client/background_task",
      binaryMessenger: flutterEngine.binaryMessenger
    )

    task.expirationHandler = {
      // Clean up if task expires
    }

    channel.invokeMethod("onBackgroundRefresh", arguments: nil) { _ in
      task.setTaskCompleted(success: true)
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    if #available(iOS 13.0, *) {
      scheduleAppRefresh()
    }
  }

  // MARK: - UISceneSession Lifecycle
  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }

  override func application(
    _ application: UIApplication,
    didDiscardSceneSessions sceneSessions: Set<UISceneSession>
  ) {}
}
