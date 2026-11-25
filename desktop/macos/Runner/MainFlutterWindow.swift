import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // "wtv/window": the app asks for full screen through it (lib/window.dart).
    let channel = FlutterMethodChannel(name: "wtv/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "toggleFullScreen" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.toggleFullScreen(nil)
      result(nil)
    }

    super.awakeFromNib()
  }
}
