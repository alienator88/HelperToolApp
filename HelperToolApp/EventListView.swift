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
                // Start/Stop button for streaming mode
                Button(esloggerManager.isRunning ? "Stop Monitoring" : "Start Monitoring") {
                    if esloggerManager.isRunning {
                        esloggerManager.stopESLogger()
                    } else {
                        esloggerManager.startESLogger()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(esloggerManager.isRunning ? .red : .green)
                .disabled(esloggerManager.isRunning) // Disable the new button when streaming
                
                // New simplified session button
                Button("Run 5s Session") {
                    esloggerManager.runESLoggerSession()
                }
                .buttonStyle(.bordered)
                .disabled(esloggerManager.isRunning) // Disable when running streaming mode
                
                Spacer()
                
                // Status and count
                VStack(alignment: .trailing, spacing: 2) {
                    Text(esloggerManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(esloggerManager.isRunning ? .green : .secondary)
                    Text("Total Events: \(esloggerManager.totalEventCount)")
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
                .frame(width: 150)
            }
            
            // Event list
            if filteredEvents.isEmpty {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(esloggerManager.isRunning ? "Waiting for file creation events...\n(Test file will be created in Downloads after 2 seconds)" : "Start monitoring to see file creation events")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEvents, id: \.id) { event in
                    EventRowView(event: event)
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var filteredEvents: [FileCreationEvent] {
        var events = Array(dataStore.allEvents.reversed()) // Convert to Array first
        
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
        
        return Array(filteredForTempFiles.prefix(50)) // Limit display for performance
    }
    
    private var uniqueAppNames: [String] {
        return dataStore.uniqueAppNames
    }
}

struct EventRowView: View {
    let event: FileCreationEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // App name
                Text(event.appBundle?.displayName ?? "Unknown App")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Timestamp
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Event description
            HStack {
                Image(systemName: event.eventType == "rename" ? "arrow.right" : "doc")
                    .foregroundStyle(event.eventType == "rename" ? .orange : .blue)
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