//
//  ESLoggerModels.swift
//  HelperToolApp
//
//  Created by Claude on 2025-09-05.
//

import Foundation

// JSON models (only fields we need from eslogger)
struct ESMessage: Decodable {
    let time: String
    let process: ProcessInfo
    let event: Event
    let event_type: Int
    
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
    
    enum Event: Decodable {
        case create(Create)
        case rename(Rename)
        case unlink(Unlink)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            if let create = try? container.decode(Create.self, forKey: .create) {
                self = .create(create)
            } else if let rename = try? container.decode(Rename.self, forKey: .rename) {
                self = .rename(rename)
            } else if let unlink = try? container.decode(Unlink.self, forKey: .unlink) {
                self = .unlink(unlink)
            } else {
                // Default case for unknown events
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown event type"
                ))
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case create, rename, unlink
        }
        
        struct Create: Decodable {
            let destination: Destination
            
            struct Destination: Decodable {
                let existing_file: PathObj
                
                struct PathObj: Decodable { 
                    let path: String 
                }
            }
        }
        
        struct Rename: Decodable {
            let source: PathObj
            let destination: DestinationObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
            
            struct DestinationObj: Decodable {
                let existing_file: PathObj
                
                struct PathObj: Decodable { 
                    let path: String 
                }
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