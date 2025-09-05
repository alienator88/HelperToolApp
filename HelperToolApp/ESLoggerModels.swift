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
        case copyfile(Copyfile)
        case exchangedata(Exchangedata)
        case link(Link)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            if let create = try? container.decode(Create.self, forKey: .create) {
                self = .create(create)
            } else if let rename = try? container.decode(Rename.self, forKey: .rename) {
                self = .rename(rename)
            } else if let unlink = try? container.decode(Unlink.self, forKey: .unlink) {
                self = .unlink(unlink)
            } else if let copyfile = try? container.decode(Copyfile.self, forKey: .copyfile) {
                self = .copyfile(copyfile)
            } else if let exchangedata = try? container.decode(Exchangedata.self, forKey: .exchangedata) {
                self = .exchangedata(exchangedata)
            } else if let link = try? container.decode(Link.self, forKey: .link) {
                self = .link(link)
            } else {
                // Default case for unknown events
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown event type"
                ))
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case create, rename, unlink, copyfile, exchangedata, link
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
                let existing_file: PathObj?
                let new_path: NewPath?
                
                struct PathObj: Decodable { 
                    let path: String 
                }
                
                struct NewPath: Decodable {
                    let filename: String
                    let dir: DirObj
                    
                    struct DirObj: Decodable {
                        let path: String
                    }
                }
                
                // Computed property to get the final destination path
                var finalPath: String {
                    if let existingFile = existing_file {
                        return existingFile.path
                    } else if let newPath = new_path {
                        return "\(newPath.dir.path)/\(newPath.filename)"
                    } else {
                        return "Unknown"
                    }
                }
            }
        }
        
        struct Unlink: Decodable {
            let target: PathObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
        }
        
        struct Copyfile: Decodable {
            let source: PathObj
            let target: PathObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
        }
        
        struct Exchangedata: Decodable {
            let file1: PathObj
            let file2: PathObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
        }
        
        struct Link: Decodable {
            let source: PathObj
            let target: PathObj
            
            struct PathObj: Decodable { 
                let path: String 
            }
        }
    }
}