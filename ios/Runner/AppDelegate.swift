import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The panchang needs to know where the phone is. Its timezone says so —
    // no location permission, no API, nothing to refuse. The same channel
    // answers the notification question on Android; here there is nothing to
    // ask for, because iOS grants the media controls with the audio session.
    if let messenger = engineBridge.applicationRegistry as? FlutterBinaryMessenger {
      let channel = FlutterMethodChannel(
        name: "com.batiyao.veda/notifications",
        binaryMessenger: messenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "timezone": result(TimeZone.current.identifier)
        case "request": result(true)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
