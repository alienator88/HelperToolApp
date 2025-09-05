//
//  ESLoggerModels.swift
//  HelperTool
//
//  Created by Claude on 2025-09-05.
//

import Foundation

// JSON models (only fields we need from eslogger)
struct ESMessage: Decodable {
    let time: String
    let process: ProcessInfo
    let event: Event
    
    struct ProcessInfo: Decodable {
        let audit_token: Audit
        let executable: Executable
        
        struct Audit: Decodable { 
            let pid: Int 
        }
        
        struct Executable: Decodable { 
            let path: String 
        }
    }
    
    struct Event: Decodable {
        let create: Create?
        let rename: Rename?
        let unlink: Unlink?
        
        struct Create: Decodable {
            let destination: Destination
            
            struct Destination: Decodable {
                // eslogger emits either new_path or existing_file; keep both, use first non-nil
                let new_path: PathObj?
                let existing_file: PathObj?
                
                struct PathObj: Decodable { 
                    let path: String 
                }
            }
        }
        
        struct Rename: Decodable {
            let source: PathObj
            let destination: PathObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
        }
        
        struct Unlink: Decodable {
            let target: PathObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
        }
    }
}

// Our distilled event for storage/UI
struct CreateEvent {
    let timeISO8601: String
    let pid: Int
    let execPath: String
    let createdPath: String
    let bundlePath: String? // derived from execPath (…/App.app)
    let eventType: String // "create" or "rename"
    let sourcePath: String? // for rename events
}

// Pending file creation tracking for atomic operations
struct PendingFileCreation {
    let pid: Int
    let execPath: String
    let tempPath: String
    let timeISO8601: String
    let bundlePath: String?
    let createdAt: Date
}

// Helpers
func bundlePath(from execPath: String) -> String? {
    // execPath usually …/Foo.app/Contents/MacOS/Foo → return …/Foo.app
    guard let range = execPath.range(of: ".app/Contents/MacOS/") else { return nil }
    let prefix = execPath[..<range.lowerBound]
    return prefix.appending(".app")
}

func createdPath(from msg: ESMessage) -> (path: String, eventType: String, sourcePath: String?)? {
    if let create = msg.event.create {
        let path = create.destination.new_path?.path ?? create.destination.existing_file?.path
        return path.map { (path: $0, eventType: "create", sourcePath: nil) }
    } else if let rename = msg.event.rename {
        return (path: rename.destination.path, eventType: "rename", sourcePath: rename.source.path)
    } else if let unlink = msg.event.unlink {
        return (path: unlink.target.path, eventType: "unlink", sourcePath: nil)
    }
    return nil
}

// Small utility to read a line from Pipe without Foundation's FileHandle.readToEnd (streaming)
extension FileHandle {
    func readLineUTF8() -> String? {
        var data = Data()
        while true {
            let chunk = try? self.read(upToCount: 1) // 1 byte at a time keeps it simple
            guard let c = chunk, !c.isEmpty else { 
                return data.isEmpty ? nil : String(data: data, encoding: .utf8) 
            }
            if c[0] == 0x0A { break } // newline
            data.append(c)
        }
        return String(data: data, encoding: .utf8)
    }
}