//
//  EventListView.swift
//  HelperToolApp
//
//  Created by Claude on 2025-09-05.
//

import SwiftUI

struct EventListView: View {
    @ObservedObject var esloggerManager: ESLoggerManager
    @ObservedObject var dataStore: FileCreationDataStore
    @State private var selectedAppBundle: String = "All Apps"
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with controls
            HStack {
                // Real-time streaming button
                Button(esloggerManager.isRunning ? "Stop Stream" : "Start Stream") {
                    if esloggerManager.isRunning {
                        esloggerManager.stopESLoggerStreaming()
                    } else {
                        esloggerManager.startESLoggerStreaming()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(esloggerManager.isRunning ? .red : .blue)
                
                // Create test files button
                Button("Create Test Files") {
                    createTestFiles()
                }
                .buttonStyle(.bordered)
                .tint(.green)
                
                
                
                Spacer()
                
                // Status and count
                VStack(alignment: .trailing, spacing: 2) {
                    Text(esloggerManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(esloggerManager.isRunning ? .green : .secondary)
                    Text("\(selectedAppBundle == "All Apps" ? "Total" : selectedAppBundle) Events: \(filteredEvents.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Filter controls
            HStack {
                TextField("Search created files...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                Picker("App Bundle", selection: $selectedAppBundle) {
                    Text("All Apps").tag("All Apps")
                    ForEach(uniqueAppNames, id: \.self) { appName in
                        Text(appName).tag(appName)
                    }
                }
                .frame(width: 200)
            }
            
            // Event list
            if filteredEvents.isEmpty {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(esloggerManager.isRunning ? "Waiting for file creation events.." : "Start monitoring to see file creation events")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                                EventRowView(event: event)
                                    .id(event.id)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                
                                // Add divider between events (except for the last one)
                                if index < filteredEvents.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .onChange(of: filteredEvents.count) { _ in
                        // Auto-scroll to the most recent event for the selected app
                        if let mostRecentEvent = filteredEvents.first {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(mostRecentEvent.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var filteredEvents: [FileCreationEvent] {
        var events = Array(dataStore.allEvents) // Don't reverse - keep chronological order
        
        // Filter by app bundle
        if selectedAppBundle != "All Apps" {
            events = events.filter { event in
                event.appBundle?.displayName == selectedAppBundle
            }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            events = events.filter { event in
                event.createdPath.localizedCaseInsensitiveContains(searchText) ||
                event.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // For better UX, prefer showing rename events over create events for temp files
        var filteredForTempFiles: [FileCreationEvent] = []
        var tempFilePaths: Set<String> = []
        
        // First pass: collect all temp file paths that have corresponding rename events
        for event in events {
            if event.eventType == "rename", let sourcePath = event.sourcePath {
                if sourcePath.contains(".dat.nosync") || sourcePath.hasPrefix(".tmp") {
                    tempFilePaths.insert(sourcePath)
                }
            }
        }
        
        // Second pass: filter out create events for temp files that have rename events
        for event in events {
            if event.eventType == "create" && tempFilePaths.contains(event.createdPath) {
                // Skip this create event because we have a rename event that shows the final name
                continue
            }
            filteredForTempFiles.append(event)
        }
        
        // Sort by app name, then by timestamp (newest first within each app)
        let sortedEvents = filteredForTempFiles.sorted { event1, event2 in
            let app1 = event1.appBundle?.displayName ?? "Unknown App"
            let app2 = event2.appBundle?.displayName ?? "Unknown App"
            
            if app1 != app2 {
                return app1 < app2 // Sort by app name alphabetically
            } else {
                // Same app - sort by timestamp, newest first
                return event1.timestamp > event2.timestamp
            }
        }
        
        return sortedEvents // Show all events with LazyVStack
    }
    
    private var uniqueAppNames: [String] {
        return dataStore.uniqueAppNames
    }
    
    // Create test files to verify streaming is working
    private func createTestFiles() {
        Task {
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            guard let downloadsPath = downloadsURL?.path else {
                print("Could not find Downloads directory")
                return
            }
            
            // Create eslogger directory if it doesn't exist
            let esloggerDir = "\(downloadsPath)/eslogger"
            try? FileManager.default.createDirectory(atPath: esloggerDir, withIntermediateDirectories: true, attributes: nil)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
            let timestamp = dateFormatter.string(from: Date())
            
            // Create different types of test files to verify streaming
            let testFiles = [
                ("Direct_\(timestamp).txt", "Direct file creation test at \(Date())"),
                ("Atomic_\(timestamp).txt", "Atomic file creation test at \(Date())"),
                ("JSON_\(timestamp).json", #"{"test": "data", "timestamp": "\#(timestamp)", "type": "streaming_test"}"#)
            ]
            
            for (index, (fileName, content)) in testFiles.enumerated() {
                let filePath = "\(esloggerDir)/\(fileName)"
                
                // Add small delay between files
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                }
                
                // Test different file creation methods with longer delays
                if fileName.contains("Direct") {
                    // Direct file creation (non-atomic)
                    FileManager.default.createFile(atPath: filePath, contents: content.data(using: .utf8), attributes: nil)
                } else if fileName.contains("Atomic") {
                    // Atomic file creation (should show temp file then rename)
                    try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
                } else {
                    // Data write
                    try? content.data(using: .utf8)?.write(to: URL(fileURLWithPath: filePath))
                }
                
                // Add longer delay to ensure eslogger captures events
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
            }
            
        }
    }
}

struct EventRowView: View {
    let event: FileCreationEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // App name and bundle path
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.appBundle?.displayName ?? "Unknown App")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(event.appBundle?.bundlePath ?? "Unknown Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                // Full date and timestamp
                VStack(alignment: .trailing, spacing: 1) {
                    Text(event.timestamp, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Event description
            HStack {
                Image(systemName: "doc")
                    .foregroundStyle(.blue)
                    .font(.caption)
                
                Text(event.displayDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            
            // Full path
            Text(event.createdPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
