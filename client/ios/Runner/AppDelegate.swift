import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private let refreshTaskIdentifier = "com.samtigis.client.refresh"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
      setupChannels(messenger: messenger)
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

  private func setupChannels(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.samtigis.client/background_task",
      binaryMessenger: messenger
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
  }

  @available(iOS 13.0, *)
  func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("[BGTask] Error: \(error)")
    }
  }

  @available(iOS 13.0, *)
  private func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleAppRefresh()

    guard let controller = window?.rootViewController as? FlutterViewController else {
      task.setTaskCompleted(success: false)
      return
    }

    let channel = FlutterMethodChannel(
      name: "com.samtigis.client/background_task",
      binaryMessenger: controller.binaryMessenger
    )

    task.expirationHandler = {}

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
}
