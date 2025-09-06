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
    func startESLoggerStreaming(withReply reply: @escaping (Bool, String?) -> Void)
    func stopESLoggerStreaming(withReply reply: @escaping (Bool, String?) -> Void)
    func isESLoggerRunning(withReply reply: @escaping (Bool) -> Void)
}

// Protocol for streaming callbacks from helper to main app
@objc(ESLoggerStreamDelegate)
public protocol ESLoggerStreamDelegate {
    @MainActor func didReceiveJSONLine(_ jsonLine: String)
    @MainActor func didFinishStreaming()
    @MainActor func didErrorStreaming(_ error: String)
}

// XPC Communication setup
class HelperToolDelegate: NSObject, NSXPCListenerDelegate, HelperToolProtocol {
    
    // Streaming state
    private var streamingConnection: NSXPCConnection?
    private var isStreaming = false
    private var streamingProcess: Process?
    private var esloggerPID: Int32? = nil
    
    // Accept new XPC connections by setting up the exported interface and object.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate that the main app and helper app have the same code signing identity, otherwise return
        guard isValidClient(connection: newConnection) else {
            print("❌ Rejected connection from unauthorized client")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedObject = self
        
        // Set up remote interface for streaming callbacks
        newConnection.remoteObjectInterface = NSXPCInterface(with: ESLoggerStreamDelegate.self)
        
        // Store connection for streaming
        streamingConnection = newConnection
        
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
    

    
    func startESLoggerStreaming(withReply reply: @escaping (Bool, String?) -> Void) {
        fputs("📡 HELPER XPC: startESLoggerStreaming called at \(Date())\n", stderr)
        fflush(stderr)
        
        guard !isStreaming else {
            reply(false, "Already streaming")
            return
        }
        
        guard let streamingConnection = streamingConnection else {
            reply(false, "No streaming connection available")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/eslogger")
        process.arguments = ["create", "rename", "--select", "/Applications/", "--select", "/Users/"]
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            self.streamingProcess = process
            self.isStreaming = true
            self.esloggerPID = process.processIdentifier
            
            // Monitor process termination
            process.terminationHandler = { [weak self] terminatedProcess in
                fputs("🔄 HELPER: eslogger process terminated with status \(terminatedProcess.terminationStatus)\n", stderr)
                fflush(stderr)
                
                // Clear PID regardless of how process ended
                self?.esloggerPID = nil
                self?.isStreaming = false
                self?.streamingProcess = nil
            }
            
            // Get the delegate for callbacks
            let delegate = streamingConnection.remoteObjectProxyWithErrorHandler { error in
                fputs("❌ HELPER STREAM: XPC Error: \(error)\n", stderr)
            } as? ESLoggerStreamDelegate
            
            // Start streaming thread
            DispatchQueue.global().async { [weak self] in
                self?.streamJSONLines(from: stdoutPipe, to: delegate)
            }
            
            reply(true, nil)
            
        } catch {
            reply(false, "Failed to start eslogger: \(error.localizedDescription)")
        }
    }
    
    func stopESLoggerStreaming(withReply reply: @escaping (Bool, String?) -> Void) {
        fputs("🛑 HELPER XPC: stopESLoggerStreaming called at \(Date())\n", stderr)
        fflush(stderr)
        
        guard isStreaming else {
            reply(false, "Not currently streaming")
            return
        }
        
        // Terminate the process
        streamingProcess?.terminate()
        streamingProcess = nil
        isStreaming = false
        esloggerPID = nil
        
        // Notify completion
        if let connection = streamingConnection {
            let delegate = connection.remoteObjectProxyWithErrorHandler { error in
                fputs("❌ HELPER STREAM: XPC Error on finish: \(error)\n", stderr)
            } as? ESLoggerStreamDelegate
            
            Task { @MainActor in
                delegate?.didFinishStreaming()
            }
        }
        
        reply(true, nil)
    }
    
    func isESLoggerRunning(withReply reply: @escaping (Bool) -> Void) {
        // Verify the PID is still valid by checking if the process exists
        if let pid = esloggerPID {
            let processExists = kill(pid, 0) == 0
            if !processExists {
                // Process no longer exists, clear our state
                fputs("⚠️ HELPER: eslogger PID \(pid) no longer exists, clearing state\n", stderr)
                fflush(stderr)
                esloggerPID = nil
                isStreaming = false
                streamingProcess = nil
            }
        }
        
        let isRunning = esloggerPID != nil
        fputs("📊 HELPER XPC: isESLoggerRunning called - Running: \(isRunning) (PID: \(esloggerPID?.description ?? "nil"))\n", stderr)
        fflush(stderr)
        reply(isRunning)
    }
    
    private func streamJSONLines(from pipe: Pipe, to delegate: ESLoggerStreamDelegate?) {
        let handle = pipe.fileHandleForReading
        fputs("🔄 HELPER STREAM: Starting to stream JSON lines\n", stderr)
        fflush(stderr)
        
        var buffer = Data()
        
        while isStreaming {
            let chunk = handle.availableData
            if chunk.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            
            buffer.append(chunk)
            
            // Process complete lines
            while let newlineRange = buffer.range(of: Data([0x0A])) { // Find newline
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                
                if let jsonLine = String(data: lineData, encoding: .utf8) {
                    let trimmed = jsonLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed.first == "{" && trimmed.last == "}" && trimmed.count > 10 {
                        Task { @MainActor in
                            delegate?.didReceiveJSONLine(trimmed)
                        }
                    }
                }
            }
        }
        
        // Clear PID when streaming ends
        esloggerPID = nil
        isStreaming = false
        
        fputs("🏁 HELPER STREAM: Finished streaming JSON lines\n", stderr)
        fflush(stderr)
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
