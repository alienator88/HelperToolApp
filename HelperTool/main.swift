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
class HelperToolService: NSObject, HelperToolProtocol {

    // Execute privileged commands
    func runCommand(command: String, withReply reply: @escaping (String) -> Void) {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                reply(output)
            } else {
                reply("No output")
            }
        } catch {
            reply("Error: \(error.localizedDescription)")
        }
    }
}

// Set up the XPC listener
let listener = NSXPCListener(machServiceName: "com.alienator88.HelperApp.HelperTool")
let delegate = HelperToolDelegate()
listener.delegate = delegate
listener.resume()

// Run the main loop
RunLoop.current.run()

// Helper Tool Delegate class for XPC
class HelperToolDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
//        print("New connection received")
        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedObject = HelperToolService()
        newConnection.resume()
        return true
    }
}
