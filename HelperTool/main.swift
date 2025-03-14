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
}

// XPC Communication setup
class HelperToolDelegate: NSObject, NSXPCListenerDelegate, HelperToolProtocol {
    // Accept new XPC connections by setting up the exported interface and object.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
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
