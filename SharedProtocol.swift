//
//  SharedProtocol.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2/25/25.
//

import Foundation

let helperToolIdentifier = "com.alienator88.HelperApp.HelperTool"

@objc(HelperToolProtocol)
public protocol HelperToolProtocol {
    func runCommand(command: String, withReply reply: @escaping (String) -> Void)
}
