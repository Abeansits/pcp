import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

    // `make install` stops a running copy with SIGTERM. Quit the normal way,
    // so the history is saved, instead of dying before the debounced write.
    signal(SIGTERM, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler {
        MainActor.assumeIsolated { NSApp.terminate(nil) }
    }
    termination.resume()

    withExtendedLifetime((delegate, termination)) {
        app.run()
    }
}
