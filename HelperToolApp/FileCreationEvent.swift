//
//  FileCreationEvent.swift
//  HelperToolApp
//
//  Created by Claude on 2025-09-05.
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
        self.timestamp = Date()
        self.appBundle = appBundle
    }
    
    var fileName: String {
        return URL(fileURLWithPath: createdPath).lastPathComponent
    }
    
    var displayDescription: String {
        if eventType == "rename", let source = sourcePath {
            let sourceName = URL(fileURLWithPath: source).lastPathComponent
            return "Renamed \(sourceName) → \(fileName)"
        } else {
            return "Created \(fileName)"
        }
    }
}

// Simple data store for managing events and app bundles
class FileCreationDataStore: ObservableObject {
    @Published var appBundles: [AppBundle] = []
    @Published var allEvents: [FileCreationEvent] = []
    
    // Track temporary file to final name correlations
    private var tempFileCorrelations: [String: String] = [:]
    
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
        // Handle rename events - correlate temp files with final names
        if event.eventType == "rename", let sourcePath = event.sourcePath {
            // If this is a rename from a temp file to a real name, record the correlation
            if sourcePath.contains(".dat.nosync") || sourcePath.hasPrefix(".tmp") {
                tempFileCorrelations[sourcePath] = event.createdPath
                
                // Try to update any existing create event for this temp file
                if let tempEvent = allEvents.first(where: { $0.createdPath == sourcePath && $0.eventType == "create" }) {
                    tempEvent.createdPath = event.createdPath
                    print("✅ Updated temp file correlation: \(sourcePath) → \(event.createdPath)")
                }
            }
        }
        
        // Handle create events - check if we already know the final name for this temp file
        if event.eventType == "create" {
            if let finalName = tempFileCorrelations[event.createdPath] {
                event.createdPath = finalName
                print("✅ Applied known correlation for create event: \(event.createdPath)")
            }
        }
        
        allEvents.append(event)
        event.appBundle?.events.append(event)
        event.appBundle?.lastSeen = Date()
        
        // Keep only recent events for performance
        if allEvents.count > 10000 {
            let eventsToRemove = Array(allEvents.prefix(allEvents.count - 5000))
            allEvents.removeFirst(allEvents.count - 5000)
            
            // Clean up app bundle references and correlations
            for event in eventsToRemove {
                if let bundle = event.appBundle {
                    bundle.events.removeAll { $0.id == event.id }
                }
            }
            
            // Clean up old correlations
            if tempFileCorrelations.count > 100 {
                tempFileCorrelations.removeAll()
            }
        }
    }
    
    var uniqueAppNames: [String] {
        return Array(Set(allEvents.compactMap { $0.appBundle?.displayName })).sorted()
    }
}