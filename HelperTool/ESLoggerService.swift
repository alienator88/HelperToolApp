//
//  ESLoggerService.swift
//  HelperTool
//
//  Created by Claude on 2025-09-05.
//

import Foundation

class ESLoggerService {
    private var esloggerProcess: Process?
    private var isRunning = false
    private let decoder = JSONDecoder()
    private var processingQueue = DispatchQueue(label: "com.alienator88.eslogger.processing", qos: .userInitiated)
    
    // JSON buffer to store all eslogger output
    private var jsonBuffer = Data()
    private let jsonBufferLock = NSLock()
    
    // Event streaming callback
    var onNewEvent: ((CreateEvent) -> Void)?
    var onDebugLog: ((String) -> Void)?
    
    // File logging for helper tool debugging
    private let logFileURL: URL? = {
        return URL(fileURLWithPath: "/tmp/helper_tool_debug.log")
    }()
    
    private func logToFile(_ message: String) {
        guard let logURL = logFileURL else { return }
        let timestamp = DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
    
    
    func startESLogger() -> Bool {
        logToFile("🚀 ESLogger startESLogger() called")
        
        guard !isRunning else { 
            onDebugLog?("ESLogger already running")
            logToFile("⚠️ ESLogger already running, returning true")
            return true 
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/eslogger")
        process.arguments = ["create", "rename", "unlink"] // Capture create, rename, and unlink events
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // First, test if eslogger binary exists and can be executed
        let fileManager = FileManager.default
        let esloggerExists = fileManager.fileExists(atPath: "/usr/bin/eslogger")
        let esloggerExecutable = fileManager.isExecutableFile(atPath: "/usr/bin/eslogger")
        
        logToFile("📁 ESLogger binary exists: \(esloggerExists), executable: \(esloggerExecutable)")
        logToFile("📂 Current working directory: \(FileManager.default.currentDirectoryPath)")
        logToFile("🔧 Starting eslogger with command: /usr/bin/eslogger create rename unlink")
        logToFile("🌍 Process environment: USER=\(ProcessInfo.processInfo.environment["USER"] ?? "nil"), UID=\(getuid()), EUID=\(geteuid())")
        logToFile("ℹ️ Process info: \(ProcessInfo.processInfo.processName), PID: \(ProcessInfo.processInfo.processIdentifier)")
        
        // Set environment to match terminal session more closely
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["SHELL"] = "/bin/zsh"
        process.environment = environment
        onDebugLog?("Set process environment variables: TERM=\(environment["TERM"] ?? "nil"), SHELL=\(environment["SHELL"] ?? "nil")")
        
        // Try a simple test command first
        let testProcess = Process()
        testProcess.executableURL = URL(fileURLWithPath: "/usr/bin/eslogger")
        testProcess.arguments = ["--help"]
        let testPipe = Pipe()
        testProcess.standardOutput = testPipe
        testProcess.standardError = testPipe
        
        do {
            try testProcess.run()
            testProcess.waitUntilExit()
            let testData = testPipe.fileHandleForReading.readDataToEndOfFile()
            let testOutput = String(data: testData, encoding: .utf8) ?? ""
            onDebugLog?("ESLogger help test (exit: \(testProcess.terminationStatus)): \(String(testOutput.prefix(100)))")
        } catch {
            onDebugLog?("ESLogger help test failed: \(error)")
        }
        
        do {
            logToFile("🚀 Attempting to start ESLogger process...")
            try process.run()
            self.esloggerProcess = process
            self.isRunning = true
            
            logToFile("✅ ESLogger process started successfully, PID: \(process.processIdentifier)")
            onDebugLog?("ESLogger process started successfully, PID: \(process.processIdentifier)")
            
            // Check process status without consuming stdout data
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if let process = self?.esloggerProcess {
                    let stillRunning = process.isRunning
                    let exitCode = stillRunning ? -1 : process.terminationStatus
                    self?.logToFile("🔍 ESLogger process status after 1s - running: \(stillRunning), exit code: \(exitCode)")
                    
                    // Don't consume stdout data here - let the collection thread handle it
                    self?.logToFile("📤 ESLogger stdout: Data left for collection thread")
                    
                    // Check for any stderr data
                    let stderrData = stderrPipe.fileHandleForReading.availableData
                    if !stderrData.isEmpty, let stderrString = String(data: stderrData, encoding: .utf8) {
                        self?.logToFile("📢 ESLogger initial stderr: \(stderrString)")
                    } else {
                        self?.logToFile("📢 ESLogger initial stderr: No data available")
                    }
                }
            }
            
            // Start processing stderr to capture any error messages
            processingQueue.async { [weak self] in
                self?.processESLoggerStderr(pipe: stderrPipe)
            }
            
            // Start collecting JSON data from stdout
            processingQueue.async { [weak self] in
                self?.onDebugLog?("Starting stdout collection thread")
                self?.collectESLoggerJSON(pipe: stdoutPipe)
            }
            
            return true
        } catch {
            onDebugLog?("Failed to start eslogger process: \(error)")
            
            // Try to read any immediate stderr output
            let stderrData = stderrPipe.fileHandleForReading.availableData
            if !stderrData.isEmpty, let stderrString = String(data: stderrData, encoding: .utf8) {
                onDebugLog?("ESLogger stderr: \(stderrString)")
            }
            
            return false
        }
    }
    
    func stopESLogger() {
        guard isRunning else { return }
        
        esloggerProcess?.terminate()
        esloggerProcess = nil
        isRunning = false
        
        // Process all collected JSON when stopping
        processCollectedJSON()
    }
    
    func isESLoggerRunning() -> Bool {
        return isRunning
    }
    
    private func collectESLoggerJSON(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        onDebugLog?("Starting to collect ESLogger JSON...")
        logToFile("🚀 HELPER ESLOGGER: Starting to collect JSON from eslogger process")
        
        var totalBytesCollected = 0
        var readAttempts = 0
        
        while isRunning {
            readAttempts += 1
            if readAttempts % 100 == 0 {
                logToFile("📊 HELPER ESLOGGER: Read attempts: \(readAttempts), still running: \(isRunning)")
            }
            
            // Use availableData with more robust approach
            let chunkData: Data
            do {
                // First check if there's data available
                let availableData = handle.availableData
                if !availableData.isEmpty {
                    chunkData = availableData
                    logToFile("📥 HELPER ESLOGGER: Got \(availableData.count) bytes via availableData")
                } else {
                    // Try reading with a small timeout approach
                    chunkData = try handle.read(upToCount: 8192) ?? Data()
                    if !chunkData.isEmpty {
                        logToFile("📥 HELPER ESLOGGER: Got \(chunkData.count) bytes via read(upToCount:)")
                    }
                }
            } catch {
                logToFile("❌ HELPER ESLOGGER: Error reading data: \(error)")
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            
            if chunkData.isEmpty {
                // No data available, sleep briefly and continue
                Thread.sleep(forTimeInterval: 0.05) // Shorter sleep
                continue
            }
            
            totalBytesCollected += chunkData.count
            logToFile("📥 HELPER ESLOGGER: Collected \(chunkData.count) bytes (total: \(totalBytesCollected))")
            
            // Log a sample of what we collected
            if let sampleString = String(data: chunkData.prefix(100), encoding: .utf8) {
                logToFile("📋 HELPER ESLOGGER: Sample data: \(sampleString.replacingOccurrences(of: "\n", with: "\\n"))")
            }
            
            // Add to buffer
            jsonBufferLock.lock()
            jsonBuffer.append(chunkData)
            jsonBufferLock.unlock()
        }
        
        // Try to get any remaining data after stopping
        let finalData = handle.availableData
        if !finalData.isEmpty {
            totalBytesCollected += finalData.count
            logToFile("📥 HELPER ESLOGGER: Final collected \(finalData.count) bytes (final total: \(totalBytesCollected))")
            jsonBufferLock.lock()
            jsonBuffer.append(finalData)
            jsonBufferLock.unlock()
        }
        
        logToFile("🏁 HELPER ESLOGGER: Finished collecting, total bytes: \(totalBytesCollected), read attempts: \(readAttempts)")
        onDebugLog?("Finished collecting ESLogger JSON")
    }
    
    private func processCollectedJSON() {
        jsonBufferLock.lock()
        let collectedData = jsonBuffer
        jsonBuffer = Data() // Clear buffer
        jsonBufferLock.unlock()
        
        guard !collectedData.isEmpty else {
            logToFile("📭 No JSON data collected to process")
            return
        }
        
        logToFile("🔍 Processing \(collectedData.count) bytes of collected JSON")
        
        // Convert to string and split by lines
        guard let jsonString = String(data: collectedData, encoding: .utf8) else {
            logToFile("❌ Failed to convert collected data to string")
            return
        }
        
        let lines = jsonString.components(separatedBy: .newlines)
        logToFile("📄 Split into \(lines.count) lines")
        
        var processedCount = 0
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.isEmpty {
                continue
            }
            
            if trimmedLine.first != "{" {
                logToFile("⚠️ Skipping non-JSON line \(index): \(String(trimmedLine.prefix(50)))")
                continue
            }
            
            if let event = parseJSONLine(trimmedLine) {
                logToFile("✅ Parsed event \(processedCount + 1): \(event.createdPath)")
                onNewEvent?(event)
                processedCount += 1
            } else {
                logToFile("❌ Failed to parse JSON line \(index): \(String(trimmedLine.prefix(100)))")
            }
        }
        
        logToFile("🎉 Successfully processed \(processedCount) events from collected JSON")
    }
    
    private func processESLoggerStderr(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        onDebugLog?("Starting to read ESLogger stderr...")
        
        while isRunning {
            guard let line = handle.readLineUTF8() else {
                onDebugLog?("End of stderr stream")
                break
            }
            
            if !line.isEmpty {
                onDebugLog?("ESLogger stderr: \(line)")
            }
        }
    }
    
    private func parseJSONLine(_ line: String) -> CreateEvent? {
        guard let data = line.data(using: .utf8) else {
            onDebugLog?("❌ Failed to convert line to data")
            return nil
        }
        
        // Always output raw JSON first, before parsing
        logToFile("🔍 RAW JSON: \(String(line.prefix(500)))")
        
        do {
            let msg = try decoder.decode(ESMessage.self, from: data)
            logToFile("✅ JSON parsing succeeded")
            
            // Process the parsed message...
            guard let pathInfo = createdPath(from: msg) else {
                onDebugLog?("No created path found in message")
                return nil
            }
            
            let exec = msg.process.executable.path
            let eventDesc = pathInfo.eventType == "rename" ? 
                "File renamed: \(pathInfo.sourcePath ?? "?") → \(pathInfo.path)" : 
                "File created: \(pathInfo.path)"
            onDebugLog?("\(eventDesc) by process: \(exec)")
            
            // DEBUG: Temporarily allow all events (removed .app filter)
            // Original filter: exec.contains(".app/Contents/MacOS/")
            let bpath = bundlePath(from: exec) ?? exec // Use exec path if no bundle found
            
            let event = CreateEvent(
                timeISO8601: msg.time,
                pid: msg.process.audit_token.pid,
                execPath: exec,
                createdPath: pathInfo.path,
                bundlePath: bpath,
                eventType: pathInfo.eventType,
                sourcePath: pathInfo.sourcePath
            )
            
            onDebugLog?("Created \(pathInfo.eventType) event for: \(pathInfo.path)")
            return event
            
        } catch {
            logToFile("❌ JSON parsing failed: \(error)")
            logToFile("❌ Failed JSON (first 200 chars): \(String(line.prefix(200)))")
            return nil
        }
    }
    
}