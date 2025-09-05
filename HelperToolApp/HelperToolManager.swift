//
//  HelperToolManager.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2/26/25.
//
import ServiceManagement

@objc(HelperToolProtocol)
public protocol HelperToolProtocol {
    func runCommand(command: String, withReply reply: @escaping (String) -> Void)
    func startESLogger(withReply reply: @escaping (Bool, String?) -> Void)
    func stopESLogger(withReply reply: @escaping (Bool, String?) -> Void)
    func getESLoggerEvents(withReply reply: @escaping ([String]) -> Void)
    func runESLoggerForDuration(duration: Double, withReply reply: @escaping (String?, String?) -> Void)
}

enum HelperToolAction {
    case none      // Only check status
    case install   // Install the helper tool
    case uninstall // Uninstall the helper tool
}

@MainActor
class HelperToolManager: ObservableObject {
    private var helperConnection: NSXPCConnection?
    let helperToolIdentifier = "com.alienator88.HelperApp.HelperTool"
    @Published var isHelperToolInstalled: Bool = false
    @Published var message: String = "Checking..."
    var status: String {
        return isHelperToolInstalled ? "Registered" : "Not Registered"
    }

    init() {
        Task {
            await manageHelperTool()
        }
    }

    // Function to manage the helper tool installation/uninstallation
    func manageHelperTool(action: HelperToolAction = .none) async {
        let plistName = "\(helperToolIdentifier).plist"
        let service = SMAppService.daemon(plistName: plistName)
        var occurredError: NSError?

        // Perform install/uninstall actions if specified
        switch action {
        case .install:
            // Pre-check before registering
            switch service.status {
            case .requiresApproval:
                message = "Registered but requires enabling in System Settings > Login Items."
                SMAppService.openSystemSettingsLoginItems()
            case .enabled:
                message = "Service is already enabled."
            default:
                do {
                    try service.register()
                    if service.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } catch let nsError as NSError {
                    occurredError = nsError
                    if nsError.code == 1 { // Operation not permitted
                        message = "Permission required. Enable in System Settings > Login Items."
                        SMAppService.openSystemSettingsLoginItems()
                    } else {
                        message = "Installation failed: \(nsError.localizedDescription)"
                        print("Failed to register helper: \(nsError.localizedDescription)")
                    }

                }
            }

        case .uninstall:
            do {
                try await service.unregister()
                // Close any existing connection
                helperConnection?.invalidate()
                helperConnection = nil
            } catch let nsError as NSError {
                occurredError = nsError
                print("Failed to unregister helper: \(nsError.localizedDescription)")
            }

        case .none:
            break
        }

        updateStatusMessages(with: service, occurredError: occurredError)
        isHelperToolInstalled = (service.status == .enabled)
    }

    // Function to open Settings > Login Items
    func openSMSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // Function to run privileged commands
    func runCommand(_ command: String, completion: @escaping (String) -> Void) async {
        if !isHelperToolInstalled {
            completion("XPC: Helper tool is not installed")
            return
        }

        guard let connection = getConnection() else {
            completion("XPC: Connection not available")
            return
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                completion("XPC: Connection error: \(error.localizedDescription)")
            }
        }) as? HelperToolProtocol else {
            completion("XPC: Failed to get remote object")
            return
        }

        proxy.runCommand(command: command) { output in
            DispatchQueue.main.async {
                completion(output)
            }
        }
    }


    // Create/reuse XPC connection
    private func getConnection() -> NSXPCConnection? {
        if let connection = helperConnection {
            return connection
        }
        let connection = NSXPCConnection(machServiceName: helperToolIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperToolProtocol.self)
        connection.invalidationHandler = { [weak self] in
            self?.helperConnection = nil
        }
        connection.resume()
        helperConnection = connection
        return connection
    }



    // ESLogger management functions
    func startESLogger(completion: @escaping (Bool, String?) -> Void) async {
        guard isHelperToolInstalled else {
            completion(false, "Helper tool is not installed")
            return
        }
        
        guard let connection = getConnection() else {
            completion(false, "XPC: Connection not available")
            return
        }
        
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                completion(false, "XPC: Connection error: \(error.localizedDescription)")
            }
        }) as? HelperToolProtocol else {
            completion(false, "XPC: Failed to get remote object")
            return
        }
        
        proxy.startESLogger { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func stopESLogger(completion: @escaping (Bool, String?) -> Void) async {
        guard isHelperToolInstalled else {
            completion(false, "Helper tool is not installed")
            return
        }
        
        guard let connection = getConnection() else {
            completion(false, "XPC: Connection not available")
            return
        }
        
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                completion(false, "XPC: Connection error: \(error.localizedDescription)")
            }
        }) as? HelperToolProtocol else {
            completion(false, "XPC: Failed to get remote object")
            return
        }
        
        proxy.stopESLogger { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func getESLoggerEvents(completion: @escaping ([String]) -> Void) async {
        guard isHelperToolInstalled else {
            completion([])
            return
        }
        
        guard let connection = getConnection() else {
            completion([])
            return
        }
        
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                completion([])
            }
        }) as? HelperToolProtocol else {
            completion([])
            return
        }
        
        proxy.getESLoggerEvents { events in
            DispatchQueue.main.async {
                completion(events)
            }
        }
    }
    
    func runESLoggerForDuration(duration: Double, completion: @escaping (String?, String?) -> Void) async {
        guard isHelperToolInstalled else {
            completion(nil, "Helper tool is not installed")
            return
        }
        
        guard let connection = getConnection() else {
            completion(nil, "XPC: Connection not available")
            return
        }
        
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                completion(nil, "XPC: Connection error: \(error.localizedDescription)")
            }
        }) as? HelperToolProtocol else {
            completion(nil, "XPC: Failed to get remote object")
            return
        }
        
        proxy.runESLoggerForDuration(duration: duration) { jsonOutput, error in
            DispatchQueue.main.async {
                completion(jsonOutput, error)
            }
        }
    }
    
    
    
    // Helper to update helper status messages
    func updateStatusMessages(with service: SMAppService, occurredError: NSError?) {
        if let nsError = occurredError {
            switch nsError.code {
            case kSMErrorAlreadyRegistered:
                message = "Service is already registered and enabled."
            case kSMErrorLaunchDeniedByUser:
                message = "User denied permission. Enable in System Settings > Login Items."
            case kSMErrorInvalidSignature:
                message = "Invalid signature, ensure proper signing on the application and helper tool."
            case 1:
                message = "Authorization required in Settings > Login Items."
            default:
                message = "Operation failed: \(nsError.localizedDescription)"
            }
        } else {
            switch service.status {
            case .notRegistered:
                message = "Service hasn’t been registered. You may register it now."
            case .enabled:
                message = "Service successfully registered and eligible to run."
            case .requiresApproval:
                message = "Service registered but requires user approval in Settings > Login Items."
            case .notFound:
                message = "Service is not installed."
            @unknown default:
                message = "Unknown service status (\(service.status))."
            }
        }
    }



}
