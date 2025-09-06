//
//  ESLoggerManager.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2025-09-05.
//

import Foundation

@MainActor
class ESLoggerManager: ObservableObject, ESLoggerStreamDelegate {
    let helperToolManager: HelperToolManager // Made public for debug access
    private let dataStore: FileCreationDataStore
    
    @Published var isRunning = false
    @Published var totalEventCount = 0
    @Published var statusMessage = "ESLogger stopped"
    
    private var isStreamingMode = false
    
    // Temporary storage for create events that might be temp files (only for true rename correlation)
    private var pendingCreateEvents: [String: FileCreationEvent] = [:]
    
    
    init(helperToolManager: HelperToolManager, dataStore: FileCreationDataStore) {
        self.helperToolManager = helperToolManager
        self.dataStore = dataStore
        
        // Set up streaming delegate
        helperToolManager.streamDelegate = self
    }
    
    
    
    // New streaming methods
    func startESLoggerStreaming() {
        guard !isRunning else {
            statusMessage = "Already running"
            return
        }
        
        isRunning = true
        isStreamingMode = true
        statusMessage = "Starting real-time monitoring..."
        
        Task {
            await helperToolManager.startESLoggerStreaming { [weak self] success, error in
                guard let self = self else { return }
                
                if success {
                    self.statusMessage = "Real-time monitoring active"
                } else {
                    self.isRunning = false
                    self.isStreamingMode = false
                    self.statusMessage = "Failed to start streaming: \(error ?? "Unknown error")"
                }
            }
        }
    }
    
    func stopESLoggerStreaming() {
        guard isRunning && isStreamingMode else { return }
        
        Task {
            await helperToolManager.stopESLoggerStreaming { [weak self] success, error in
                guard let self = self else { return }
                
                self.isRunning = false
                self.isStreamingMode = false
                self.statusMessage = success ? "Streaming stopped" : "Error stopping streaming: \(error ?? "Unknown")"
            }
        }
    }
    
    // ESLoggerStreamDelegate implementation
    func didReceiveJSONLine(_ jsonLine: String) {
        // Process the JSON line immediately
        if let event = parseJSONLine(jsonLine) {
            processEvent(event)
        }
    }
    
    func didFinishStreaming() {
        isRunning = false
        isStreamingMode = false
        statusMessage = "Streaming finished"
    }
    
    func didErrorStreaming(_ error: String) {
        isRunning = false
        isStreamingMode = false
        statusMessage = "Streaming error: \(error)"
    }
    
    
    private func parseJSONLine(_ line: String) -> FileCreationEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        
        do {
            let msg = try JSONDecoder().decode(ESMessage.self, from: data)
            
            // Extract path information based on event type
            guard let pathInfo = extractPathInfo(from: msg) else { return nil }
            
            let exec = msg.process.executable.path
            let bundlePath = extractBundlePath(from: exec) ?? exec
            let appBundle = dataStore.findOrCreateAppBundle(bundlePath: bundlePath)
            
            return FileCreationEvent(
                timeISO8601: msg.time,
                pid: msg.process.audit_token.pid,
                execPath: exec,
                createdPath: pathInfo.path,
                eventType: pathInfo.eventType,
                sourcePath: pathInfo.sourcePath,
                appBundle: appBundle
            )
            
        } catch {
            // Silently skip malformed JSON lines (common when eslogger is terminated)
            return nil
        }
    }
    
    private func extractPathInfo(from msg: ESMessage) -> (path: String, eventType: String, sourcePath: String?)? {
        switch msg.event_type {
        case 13: // ES_EVENT_TYPE_NOTIFY_CREATE
            if case .create(let createEvent) = msg.event {
                return (
                    path: createEvent.destination.existing_file.path,
                    eventType: "create",
                    sourcePath: nil
                )
            }
        case 25: // ES_EVENT_TYPE_NOTIFY_RENAME
            if case .rename(let renameEvent) = msg.event {
                return (
                    path: renameEvent.destination.finalPath,
                    eventType: "rename",
                    sourcePath: renameEvent.source.path
                )
            }
        default:
            return nil
        }
        return nil
    }
    
    private func extractBundlePath(from execPath: String) -> String? {
        let components = execPath.components(separatedBy: "/")
        
        // Look for .app bundle pattern
        if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let bundleComponents = Array(components[0...appIndex])
            return bundleComponents.joined(separator: "/")
        }
        
        return nil
    }
    
    private func processEvent(_ event: FileCreationEvent) {
        if event.eventType == "create" {
            handleCreateEventFromJSON(event)
        } else if event.eventType == "rename" {
            handleRenameEventFromJSON(event)
        } else {
            // For unlink or other events, just add directly
            addEventToStore(event)
        }
    }
    
    private func handleCreateEventFromJSON(_ event: FileCreationEvent) {
        let fileName = URL(fileURLWithPath: event.createdPath).lastPathComponent
        let isTempFile = fileName.contains(".tmp") || 
                        fileName.contains(".nosync") || 
                        fileName.hasPrefix(".dat") ||
                        fileName.contains("Temp") ||
                        fileName.contains("temp") ||
                        (fileName.hasPrefix(".") && fileName.count > 20 && fileName != ".DS_Store") ||
                        (fileName.contains(".") && fileName.components(separatedBy: ".").count > 3)
        
        if isTempFile {
            // Store temp file creates, wait for rename events to provide final names
            pendingCreateEvents[event.createdPath] = event
        } else {
            // Non-temp file, add immediately
            addEventToStore(event)
        }
    }
    
    private func handleRenameEventFromJSON(_ event: FileCreationEvent) {
        guard let sourcePath = event.sourcePath else {
            addEventToStore(event)
            return
        }
        
        // Check if we have a pending create event for the source path
        if let pendingCreate = pendingCreateEvents.removeValue(forKey: sourcePath) {
            // Update the pending create event to show as a rename with final name
            let correlatedEvent = FileCreationEvent(
                timeISO8601: pendingCreate.timeISO8601, // Use original create time
                pid: pendingCreate.pid,
                execPath: pendingCreate.execPath,
                createdPath: event.createdPath, // Final name
                eventType: "rename",
                sourcePath: sourcePath, // Original temp name
                appBundle: pendingCreate.appBundle
            )
            
            addEventToStore(correlatedEvent)
        } else {
            // No pending create, treat as regular rename
            addEventToStore(event)
        }
    }
    
    
    
    private func addEventToStore(_ event: FileCreationEvent) {
        dataStore.addEvent(event)
        totalEventCount += 1
    }
    
    
}
