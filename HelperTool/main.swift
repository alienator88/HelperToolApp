//
//  main.swift
//  HelperTool
//
//  Created by Alin Lupascu on 2/25/25.
//

import Foundation

@objc(HelperToolProtocol)
public protocol HelperToolProtocol {
    func runCommand(command: String, withReply reply: @escaping (String) -> Void)
    func startESLogger(withReply reply: @escaping (Bool, String?) -> Void)
    func stopESLogger(withReply reply: @escaping (Bool, String?) -> Void)
    func getESLoggerEvents(withReply reply: @escaping ([String]) -> Void)
    func runESLoggerForDuration(duration: Double, withReply reply: @escaping (String?, String?) -> Void)
}

// XPC Communication setup
class HelperToolDelegate: NSObject, NSXPCListenerDelegate, HelperToolProtocol {
    private let esloggerService = ESLoggerService()
    private var eventBuffer: [CreateEvent] = []
    private let eventBufferLock = NSLock()
    
    // Debug logging
    private var debugLogs: [String] = []
    private let debugLogLock = NSLock()
    
    private func addDebugLog(_ message: String) {
        debugLogLock.lock()
        defer { debugLogLock.unlock() }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        debugLogs.append("[\(timestamp)] \(message)")
        
        // Keep only last 100 debug messages
        if debugLogs.count > 100 {
            debugLogs.removeFirst(debugLogs.count - 100)
        }
        
        // Also print to stderr for daemon logs
        fputs("HELPER DEBUG: \(message)\n", stderr)
        fflush(stderr)
    }
    // Accept new XPC connections by setting up the exported interface and object.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate that the main app and helper app have the same code signing identity, otherwise return
        guard isValidClient(connection: newConnection) else {
            print("❌ Rejected connection from unauthorized client")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // Execute the shell command and reply with output.
    func runCommand(command: String, withReply reply: @escaping (String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply("Failed to run command: \(error.localizedDescription)")
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        reply(output.isEmpty ? "No output" : output)
    }

    // ESLogger management functions
    func startESLogger(withReply reply: @escaping (Bool, String?) -> Void) {
        // Direct stderr logging that should appear in Console.app
        fputs("🚀 HELPER XPC: startESLogger called at \(Date())\n", stderr)
        fflush(stderr)
        
        // Create simple file log to verify this function is called - use /tmp for root access
        let logMessage = "🚀 MAIN HELPER: startESLogger called at \(Date())\n"
        let logURL = URL(fileURLWithPath: "/tmp/helper_main_debug.log")
        
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
        
        addDebugLog("Helper tool startESLogger called")
        
        // Set up debug logging callback
        esloggerService.onDebugLog = { [weak self] message in
            self?.addDebugLog("ESLoggerService: \(message)")
        }
        
        let success = esloggerService.startESLogger()
        
        // Log the result
        let resultMessage = "📝 MAIN HELPER: ESLoggerService.startESLogger() returned: \(success)\n"
        if let data = resultMessage.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        }
        
        if success {
            addDebugLog("ESLogger service started successfully, setting up event callback")
            esloggerService.onNewEvent = { [weak self] event in
                self?.addDebugLog("Received event callback in helper tool")
                self?.bufferEvent(event)
            }
            reply(true, nil)
        } else {
            addDebugLog("Failed to start ESLogger service")
            reply(false, "Failed to start eslogger")
        }
    }
    
    func stopESLogger(withReply reply: @escaping (Bool, String?) -> Void) {
        esloggerService.stopESLogger()
        reply(true, nil)
    }
    
    func getESLoggerEvents(withReply reply: @escaping ([String]) -> Void) {
        // Direct stderr logging that should appear in Console.app
        fputs("📞 HELPER XPC: getESLoggerEvents called at \(Date())\n", stderr)
        fflush(stderr)
        
        // Log to file to verify this XPC function is being called
        let logMessage = "📞 MAIN HELPER: getESLoggerEvents called at \(Date())\n"
        let logURL = URL(fileURLWithPath: "/tmp/helper_get_events_debug.log")
        
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
        
        eventBufferLock.lock()
        defer { eventBufferLock.unlock() }
        
        let eventStrings = eventBuffer.map { event in
            "\(event.timeISO8601)|\(event.pid)|\(event.bundlePath ?? "Unknown")|\(event.createdPath)|\(event.eventType)|\(event.sourcePath ?? "")"
        }
        
        // Log the results
        let resultMessage = "📊 MAIN HELPER: Returning \(eventStrings.count) events: \(eventStrings.joined(separator: " | "))\n"
        if let data = resultMessage.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        }
        
        addDebugLog("Returning \(eventStrings.count) events to main app")
        eventBuffer.removeAll()
        reply(eventStrings)
    }
    
    func runESLoggerForDuration(duration: Double, withReply reply: @escaping (String?, String?) -> Void) {
        // Log the XPC call
        fputs("🎬 HELPER XPC: runESLoggerForDuration called for \(duration) seconds at \(Date())\n", stderr)
        fflush(stderr)
        
        let logMessage = "🎬 MAIN HELPER: runESLoggerForDuration called for \(duration) seconds at \(Date())\n"
        let logURL = URL(fileURLWithPath: "/tmp/helper_eslogger_run_debug.log")
        
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
        
        // Run eslogger for the specified duration and collect all JSON output
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/eslogger")
        process.arguments = ["create", "rename", "unlink"]
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            
            // Start a timer to terminate the process after the duration
            DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
                process.terminate()
            }
            
            // Wait for the process to finish
            process.waitUntilExit()
            
            // Collect all stdout data (JSON)
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let jsonOutput = String(data: stdoutData, encoding: .utf8) ?? ""
            
            // Collect any stderr data (errors)
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: stderrData, encoding: .utf8)
            
            // Log results
            let resultMessage = "📊 MAIN HELPER: Collected \(stdoutData.count) bytes of JSON, \(stderrData.count) bytes stderr\n"
            if let data = resultMessage.data(using: .utf8) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            }
            
            if jsonOutput.isEmpty {
                reply(nil, errorOutput?.isEmpty == false ? errorOutput : "No JSON data collected")
            } else {
                reply(jsonOutput, errorOutput?.isEmpty == false ? errorOutput : nil)
            }
            
        } catch {
            let errorMsg = "Failed to run eslogger: \(error.localizedDescription)"
            
            // Log error
            let errorMessage = "❌ MAIN HELPER: \(errorMsg)\n"
            if let data = errorMessage.data(using: .utf8) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            }
            
            reply(nil, errorMsg)
        }
    }
    
    
    
    private func bufferEvent(_ event: CreateEvent) {
        eventBufferLock.lock()
        defer { eventBufferLock.unlock() }
        
        addDebugLog("Buffering event - File: \(event.createdPath), Process: \(event.execPath)")
        eventBuffer.append(event)
        
        // Keep buffer size manageable
        if eventBuffer.count > 1000 {
            eventBuffer.removeFirst(eventBuffer.count - 1000)
        }
        
        addDebugLog("Event buffer now contains \(eventBuffer.count) events")
    }
    
    // Check that the codesigning matches between the main app and the helper app
    private func isValidClient(connection: NSXPCConnection) -> Bool {
        do {
            return try CodesignCheck.codeSigningMatches(pid: connection.processIdentifier)
        } catch {
            print("Helper code signing check failed with error: \(error)")
            return false
        }
    }
}

// Set up and start the XPC listener.
let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "com.alienator88.HelperApp.HelperTool")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()










//class HelperToolService: NSObject, HelperToolProtocol {
//
//    // Execute privileged commands
//    func runCommand(command: String, withReply reply: @escaping (String) -> Void) {
//        let task = Process()
//        let pipe = Pipe()
//        task.standardOutput = pipe
//        task.standardError = pipe
//        task.arguments = ["-c", command]
//        task.executableURL = URL(fileURLWithPath: "/bin/bash")
//
//        do {
//            try task.run()
//            task.waitUntilExit()
//
//            let data = pipe.fileHandleForReading.readDataToEndOfFile()
//            if let output = String(data: data, encoding: .utf8) {
//                reply(output)
//            } else {
//                reply("No output")
//            }
//        } catch {
//            reply("Error: \(error.localizedDescription)")
//        }
//    }
//}
//
//// Set up the XPC listener
//let listener = NSXPCListener(machServiceName: "com.alienator88.HelperApp.HelperTool")
//let delegate = HelperToolDelegate()
//listener.delegate = delegate
//listener.resume()
//
//// Run the main loop
//RunLoop.current.run()
//
//// Helper Tool Delegate class for XPC
//class HelperToolDelegate: NSObject, NSXPCListenerDelegate {
//    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
////        print("New connection received")
//        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
//        newConnection.exportedObject = HelperToolService()
//        newConnection.resume()
//        return true
//    }
//}
