import Cocoa
import FlutterMacOS

/// The probe app's window, plus the one thing a scripted run needs from the
/// platform: the ability to resize itself the way a person does.
///
/// A window resize is the only way anyone has reproduced the text artifacts
/// this app exists to photograph, and `flutter drive` cannot do it — it pumps
/// frames on the test's clock rather than the display's, so every asynchronous
/// arrival the defect lives in has already landed by the next pump. So the
/// resize has to happen in a real window, on a real run, and Dart has no way
/// to ask for one. This channel is that way.
///
/// See `lib/self_drive.dart`, and *Driving the real window* in
/// `examples/render_probe/README.md`.
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "render_probe/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let window = self else {
        result(FlutterError(code: "no_window", message: "The window is gone.",
                            details: nil))
        return
      }
      switch call.method {
      case "zoom":
        // `animate: true` on purpose: the point is to put the window through
        // the same frames a person's drag does, not to teleport it.
        if let screen = window.screen ?? NSScreen.main {
          window.setFrame(screen.visibleFrame, display: true, animate: true)
        }
        result(nil)
      case "restore":
        let size = call.arguments as? [String: Any]
        let width = (size?["width"] as? NSNumber)?.doubleValue ?? 800
        let height = (size?["height"] as? NSNumber)?.doubleValue ?? 628
        var frame = window.frame
        frame.size = NSSize(width: width, height: height)
        window.setFrame(frame, display: true, animate: true)
        result(nil)
      case "frame":
        let frame = window.frame
        result(["width": frame.size.width, "height": frame.size.height])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
