//
//  HelperToolAppApp.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2/25/25.
//

import SwiftUI

@main
struct HelperToolAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .windowResizability(.contentMinSize)
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
