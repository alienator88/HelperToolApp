//
//  ESLoggerManager.swift
//  HelperToolApp
//
//  Created by Claude on 2025-09-05.
//

import Foundation

@MainActor
class ESLoggerManager: ObservableObject {
    let helperToolManager: HelperToolManager // Made public for debug access
    private let dataStore: FileCreationDataStore
    
    @Published var isRunning = false
    @Published var recentEvents: [FileCreationEvent] = []
    @Published var totalEventCount = 0
    @Published var statusMessage = "ESLogger stopped"
    
    private var eventPollingTimer: Timer?
    
    // Temporary storage for create events that might be temp files
    private var pendingCreateEvents: [String: FileCreationEvent] = [:]
    private let correlationTimeout: TimeInterval = 2.0 // 2 seconds to wait for rename
    
    private func addDebugLog(_ message: String) {
        // Remove console logging to clean up output
    }
    
    init(helperToolManager: HelperToolManager, dataStore: FileCreationDataStore) {
        self.helperToolManager = helperToolManager
        self.dataStore = dataStore
    }
    
    func startESLogger() {
        Task {
            await helperToolManager.startESLogger { [weak self] success, error in
                guard let self = self else { return }
                
                if success {
                    self.isRunning = true
                    self.statusMessage = "ESLogger running - monitoring file creation..."
                    self.startPollingForEvents()
                    self.scheduleTestFileCreation()
                } else {
                    self.statusMessage = "Failed to start ESLogger: \(error ?? "Unknown error")"
                }
            }
        }
    }
    
    func stopESLogger() {
        Task {
            await helperToolManager.stopESLogger { [weak self] success, error in
                guard let self = self else { return }
                
                self.isRunning = false
                self.statusMessage = success ? "ESLogger stopped" : "Error stopping ESLogger: \(error ?? "Unknown")"
                self.stopPollingForEvents()
            }
        }
    }
    
    // New simplified approach: run eslogger for a short duration and get raw JSON
    func runESLoggerSession(duration: Double = 5.0) {
        guard !isRunning else {
            statusMessage = "Already running a session"
            return
        }
        
        isRunning = true
        statusMessage = "Running ESLogger session for \(duration) seconds..."
        
        Task {
            await helperToolManager.runESLoggerForDuration(duration: duration) { [weak self] jsonOutput, error in
                guard let self = self else { return }
                
                self.isRunning = false
                
                if let error = error {
                    self.statusMessage = "ESLogger session failed: \(error)"
                    return
                }
                
                guard let jsonOutput = jsonOutput, !jsonOutput.isEmpty else {
                    self.statusMessage = "ESLogger session completed - no events captured"
                    return
                }
                
                // Process the raw JSON
                let eventCount = self.processRawJSON(jsonOutput)
                self.statusMessage = "ESLogger session completed - processed \(eventCount) events"
            }
        }
    }
    
    private func processRawJSON(_ jsonString: String) -> Int {
        let lines = jsonString.components(separatedBy: .newlines)
        var processedCount = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty && 
                  trimmedLine.first == "{" && 
                  trimmedLine.last == "}" && 
                  trimmedLine.count > 10 else { // Basic JSON validation
                continue
            }
            
            if let event = parseJSONLine(trimmedLine) {
                processEvent(event)
                processedCount += 1
            }
        }
        
        return processedCount
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
                    path: renameEvent.destination.existing_file.path,
                    eventType: "rename",
                    sourcePath: renameEvent.source.path
                )
            }
        case 32: // ES_EVENT_TYPE_NOTIFY_UNLINK
            if case .unlink(let unlinkEvent) = msg.event {
                return (
                    path: unlinkEvent.target.path,
                    eventType: "unlink",
                    sourcePath: nil
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
            // Store temp file creates, don't add to UI yet
            pendingCreateEvents[event.createdPath] = event
            
            // Set a timer to add this event if no rename comes
            Task {
                try? await Task.sleep(for: .seconds(correlationTimeout))
                await handlePendingEventTimeout(createdPath: event.createdPath)
            }
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
    
    private func startPollingForEvents() {
        eventPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollForEvents()
            }
        }
    }
    
    private func stopPollingForEvents() {
        eventPollingTimer?.invalidate()
        eventPollingTimer = nil
    }
    
    private func pollForEvents() {
        Task {
            await helperToolManager.getESLoggerEvents { [weak self] eventStrings in
                guard let self = self else { return }
                
                if !eventStrings.isEmpty {
                    self.processNewEvents(eventStrings)
                }
            }
        }
    }
    
    private func processNewEvents(_ eventStrings: [String]) {
        addDebugLog("Processing \(eventStrings.count) new events")
        
        for eventString in eventStrings {
            if let parsedEvent = parseEventString(eventString) {
                addDebugLog("Parsed event: \(parsedEvent.eventType) - \(parsedEvent.createdPath)")
                
                if parsedEvent.eventType == "create" {
                    handleCreateEvent(parsedEvent: parsedEvent)
                } else if parsedEvent.eventType == "rename" {
                    handleRenameEvent(parsedEvent: parsedEvent)
                }
            } else {
                addDebugLog("Failed to parse event string: \(eventString)")
            }
        }
        
        // Clean up old pending events that never got renamed
        cleanupOldPendingEvents()
    }
    
    private func handleCreateEvent(parsedEvent: (timeISO8601: String, pid: Int, bundlePath: String?, createdPath: String, eventType: String, sourcePath: String?)) {
        // Check if this looks like a temporary file
        let fileName = URL(fileURLWithPath: parsedEvent.createdPath).lastPathComponent
        let isTempFile = fileName.contains(".tmp") || 
                        fileName.contains(".nosync") || 
                        fileName.hasPrefix(".dat") ||
                        fileName.contains("Temp") ||
                        fileName.contains("temp") ||
                        (fileName.hasPrefix(".") && fileName.count > 20 && fileName != ".DS_Store") || // Long hidden files are often temp
                        (fileName.contains(".") && fileName.components(separatedBy: ".").count > 3) // Files with multiple dots are often temp
        
        addDebugLog("Create event - File: \(fileName), IsTempFile: \(isTempFile)")
        
        let appBundle = dataStore.findOrCreateAppBundle(bundlePath: parsedEvent.bundlePath ?? "Unknown")
        let event = FileCreationEvent(
            timeISO8601: parsedEvent.timeISO8601,
            pid: parsedEvent.pid,
            execPath: "Unknown",
            createdPath: parsedEvent.createdPath,
            eventType: parsedEvent.eventType,
            sourcePath: parsedEvent.sourcePath,
            appBundle: appBundle
        )
        
        if isTempFile {
            // Store temp file creates, don't add to UI yet
            addDebugLog("Storing potential temp file create: \(parsedEvent.createdPath)")
            pendingCreateEvents[parsedEvent.createdPath] = event
            
            // Set a timer to add this event if no rename comes
            Task {
                try? await Task.sleep(for: .seconds(correlationTimeout))
                await handlePendingEventTimeout(createdPath: parsedEvent.createdPath)
            }
        } else {
            // Non-temp file, add immediately
            addDebugLog("Adding non-temp create event: \(parsedEvent.createdPath)")
            addEventToStore(event)
        }
    }
    
    private func handleRenameEvent(parsedEvent: (timeISO8601: String, pid: Int, bundlePath: String?, createdPath: String, eventType: String, sourcePath: String?)) {
        guard let sourcePath = parsedEvent.sourcePath else {
            addDebugLog("Rename event without source path, treating as regular event")
            let appBundle = dataStore.findOrCreateAppBundle(bundlePath: parsedEvent.bundlePath ?? "Unknown")
            let event = FileCreationEvent(
                timeISO8601: parsedEvent.timeISO8601,
                pid: parsedEvent.pid,
                execPath: "Unknown",
                createdPath: parsedEvent.createdPath,
                eventType: parsedEvent.eventType,
                sourcePath: parsedEvent.sourcePath,
                appBundle: appBundle
            )
            addEventToStore(event)
            return
        }
        
        // Check if we have a pending create event for the source path
        if let pendingCreate = pendingCreateEvents.removeValue(forKey: sourcePath) {
            addDebugLog("SUCCESS: Correlating rename \(sourcePath) -> \(parsedEvent.createdPath) with pending create")
            
            // Update the pending create event to show as a rename with final name
            let correlatedEvent = FileCreationEvent(
                timeISO8601: pendingCreate.timeISO8601, // Use original create time
                pid: pendingCreate.pid,
                execPath: pendingCreate.execPath,
                createdPath: parsedEvent.createdPath, // Final name
                eventType: "rename",
                sourcePath: sourcePath, // Original temp name
                appBundle: pendingCreate.appBundle
            )
            
            addEventToStore(correlatedEvent)
        } else {
            // No pending create, treat as regular rename
            addDebugLog("No pending create for rename \(sourcePath) -> \(parsedEvent.createdPath)")
            let appBundle = dataStore.findOrCreateAppBundle(bundlePath: parsedEvent.bundlePath ?? "Unknown")
            let event = FileCreationEvent(
                timeISO8601: parsedEvent.timeISO8601,
                pid: parsedEvent.pid,
                execPath: "Unknown",
                createdPath: parsedEvent.createdPath,
                eventType: parsedEvent.eventType,
                sourcePath: parsedEvent.sourcePath,
                appBundle: appBundle
            )
            addEventToStore(event)
        }
    }
    
    private func addEventToStore(_ event: FileCreationEvent) {
        addDebugLog("Adding event to UI: \(event.eventType) - \(event.fileName) (pending: \(pendingCreateEvents.count))")
        dataStore.addEvent(event)
        recentEvents.append(event)
        totalEventCount += 1
        
        // Keep recent events list manageable
        if recentEvents.count > 100 {
            recentEvents.removeFirst(recentEvents.count - 100)
        }
    }
    
    private func handlePendingEventTimeout(createdPath: String) async {
        // Check if the pending event is still there (wasn't correlated)
        if let pendingEvent = pendingCreateEvents.removeValue(forKey: createdPath) {
            addDebugLog("Timeout reached for pending create: \(createdPath), adding to UI")
            await MainActor.run {
                addEventToStore(pendingEvent)
            }
        }
    }
    
    private func cleanupOldPendingEvents() {
        // Remove any events older than correlation timeout
        let currentTime = Date()
        let dateFormatter = ISO8601DateFormatter()
        
        pendingCreateEvents = pendingCreateEvents.filter { (path, event) in
            if let eventDate = dateFormatter.date(from: event.timeISO8601) {
                return currentTime.timeIntervalSince(eventDate) < correlationTimeout * 2
            }
            return true // Keep if we can't parse date
        }
    }
    
    private func parseEventString(_ eventString: String) -> (timeISO8601: String, pid: Int, bundlePath: String?, createdPath: String, eventType: String, sourcePath: String?)? {
        let components = eventString.components(separatedBy: "|")
        guard components.count == 6 else { 
            // Handle old format for backwards compatibility
            if components.count == 4 {
                guard let pid = Int(components[1]) else { return nil }
                let bundlePath = components[2] == "Unknown" ? nil : components[2]
                return (
                    timeISO8601: components[0],
                    pid: pid,
                    bundlePath: bundlePath,
                    createdPath: components[3],
                    eventType: "create",
                    sourcePath: nil
                )
            }
            return nil
        }
        
        guard let pid = Int(components[1]) else { return nil }
        
        let bundlePath = components[2] == "Unknown" ? nil : components[2]
        let sourcePath = components[5].isEmpty ? nil : components[5]
        
        return (
            timeISO8601: components[0],
            pid: pid,
            bundlePath: bundlePath,
            createdPath: components[3],
            eventType: components[4],
            sourcePath: sourcePath
        )
    }
    
    // Test function to create a file after 2 seconds when monitoring starts
    private func scheduleTestFileCreation() {
        Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await createTestFile()
            
            // Test different file creation methods
            try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 more seconds
            
            await testDifferentFileCreationMethods()
        }
    }
    
    private func createTestFile() async {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloadsPath = downloadsURL?.path else {
            print("Could not find Downloads directory")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let testFileName = "ESLogger_Test_\(timestamp).txt"
        let testFilePath = "\(downloadsPath)/eslogger/\(testFileName)"

        let testContent = """
        ESLogger Test File
        Created: \(Date())
        Purpose: Testing file creation monitoring in HelperToolApp
        
        This file was created by the HelperToolApp to test the ESLogger integration.
        You should see this file creation event appear in the monitoring interface.
        """
        
        do {
            try testContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Test file created in Downloads - watch for event!"
            }
            
            // Update status back to normal after 3 seconds
            Task {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                DispatchQueue.main.async { [weak self] in
                    if self?.isRunning == true {
                        self?.statusMessage = "ESLogger running - monitoring file creation..."
                    }
                }
            }
            
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Failed to create test file: \(error.localizedDescription)"
            }
        }
    }
    
    private func testDifferentFileCreationMethods() async {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloadsPath = downloadsURL?.path else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Test 1: Non-atomic Swift write
        let nonAtomicFile = "\(downloadsPath)/eslogger/NonAtomic_Test_\(timestamp).txt"
        let testContent = "Non-atomic test file created at \(Date())"
        
        do {
            try testContent.write(toFile: nonAtomicFile, atomically: false, encoding: .utf8)
        } catch {
            // Ignore errors for test purposes
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Test 2: Using touch via helper tool
        let touchFile = "\(downloadsPath)/eslogger/Touch_Test_\(timestamp).txt"
        await helperToolManager.runCommand("touch '\(touchFile)'") { output in
            print("Touch command result: \(output.isEmpty ? "SUCCESS" : output)")
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Test 3: Using direct FileManager
        let fileManagerFile = "\(downloadsPath)/eslogger/FileManager_Test_\(timestamp).txt"
        do {
            print("Creating FileManager file: \(fileManagerFile)")
            FileManager.default.createFile(atPath: fileManagerFile, contents: testContent.data(using: .utf8), attributes: nil)
        } catch {
            print("Failed to create FileManager file: \(error)")
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Test 4: Manual file operations (open, write, close)
        let manualFile = "\(downloadsPath)/eslogger/Manual_Test_\(timestamp).txt"
        await helperToolManager.runCommand("echo 'Manual test content' > '\(manualFile)'") { output in
            print("Manual file creation result: \(output.isEmpty ? "SUCCESS" : output)")
        }
        
        print("Completed different file creation method tests")
    }
    
    
    deinit {
        Task { @MainActor in
            stopPollingForEvents()
        }
    }
}
