//
//  FileCreationEvent.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2025-09-05.
//

import Foundation

// Basic data models for compatibility with older macOS versions
class AppBundle: ObservableObject, Identifiable {
    let id = UUID()
    var bundlePath: String
    var appName: String
    var firstSeen: Date
    var lastSeen: Date
    var events: [FileCreationEvent] = []
    
    init(bundlePath: String, appName: String) {
        self.bundlePath = bundlePath
        self.appName = appName
        self.firstSeen = Date()
        self.lastSeen = Date()
    }
    
    var displayName: String {
        if appName.hasSuffix(".app") {
            return String(appName.dropLast(4))
        }
        return appName
    }
}

class FileCreationEvent: ObservableObject, Identifiable {
    let id = UUID()
    var timeISO8601: String
    var pid: Int
    var execPath: String
    var createdPath: String
    var timestamp: Date
    var eventType: String
    var sourcePath: String?
    weak var appBundle: AppBundle?
    
    init(timeISO8601: String, pid: Int, execPath: String, createdPath: String, eventType: String, sourcePath: String?, appBundle: AppBundle?) {
        self.timeISO8601 = timeISO8601
        self.pid = pid
        self.execPath = execPath
        self.createdPath = createdPath
        self.eventType = eventType
        self.sourcePath = sourcePath
        // Parse the actual ESLogger timestamp from ISO8601 string
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.date(from: timeISO8601) ?? Date()
        self.appBundle = appBundle
    }
    
    var fileName: String {
        return URL(fileURLWithPath: createdPath).lastPathComponent
    }
    
    var displayDescription: String {
        return "Created \(fileName)"
    }
}

// Simple data store for managing events and app bundles
class FileCreationDataStore: ObservableObject {
    @Published var appBundles: [AppBundle] = []
    @Published var allEvents: [FileCreationEvent] = []
    
    
    func findOrCreateAppBundle(bundlePath: String) -> AppBundle {
        if let existingBundle = appBundles.first(where: { $0.bundlePath == bundlePath }) {
            return existingBundle
        }
        
        let appName = URL(fileURLWithPath: bundlePath).lastPathComponent
        let newBundle = AppBundle(bundlePath: bundlePath, appName: appName)
        appBundles.append(newBundle)
        return newBundle
    }
    
    func addEvent(_ event: FileCreationEvent) {
        allEvents.append(event)
        event.appBundle?.events.append(event)
        event.appBundle?.lastSeen = Date()
        
        // Keep only recent events for performance
        if allEvents.count > 10000 {
            let eventsToRemove = Array(allEvents.prefix(allEvents.count - 5000))
            allEvents.removeFirst(allEvents.count - 5000)
            
            // Clean up app bundle references
            for event in eventsToRemove {
                if let bundle = event.appBundle {
                    bundle.events.removeAll { $0.id == event.id }
                }
            }
            
        }
    }
    
    var uniqueAppNames: [String] {
        return Array(Set(allEvents.compactMap { $0.appBundle?.displayName })).sorted()
    }
}
