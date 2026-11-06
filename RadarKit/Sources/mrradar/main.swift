import Foundation
import RadarKit

// `mrradar-hub hub [--attached] [--demo]`: runs the engine and the local API without the app.
// Remote Code starts it with `--attached`, so it ends with Remote Code.
let arguments = Array(CommandLine.arguments.dropFirst())
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

guard arguments.first == "hub" else {
    print("usage: mrradar-hub hub [--attached] [--demo]")
    exit(arguments.isEmpty ? 0 : 64)
}

if let control = Hub.liveControl() {
    print("A hub is already running on port \(control.port).")
    exit(0)
}

let demo = arguments.contains("--demo")
let parent = getppid()
let engine = Engine(source: demo ? DemoSource() : RevenueCatCLI(), spacing: demo ? .milliseconds(1) : .seconds(3), persists: !demo)
let hub = Hub(engine: engine, demo: demo, version: version) { exit(0) }

try hub.start()
// Before setup is done there is nothing to read; the hub only reports that.
if demo || RadarPreferences.load().setupFinished {
    Task { await engine.start() }
}

if arguments.contains("--attached") {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 5, repeating: 5)
    timer.setEventHandler { if getppid() != parent { exit(0) } }
    timer.resume()
    withExtendedLifetime(timer) { dispatchMain() }
}
dispatchMain()
