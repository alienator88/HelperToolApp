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
        return isHelperToolInstalled ? "Installed" : "Not Installed"
    }

    init() {
        Task {
            await manageHelperTool()
        }
    }




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
                    print("Service registered successfully")
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
                    }
                    print("Failed to install helper: \(nsError.localizedDescription)")
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
                print("Failed to uninstall helper: \(nsError.localizedDescription)")
            }

        case .none:
            break
        }

        // Final status check or error processing
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
                message = "Unknown service status (\(service.status)."
            }
        }

        isHelperToolInstalled = (service.status == .enabled)
    }


    func openSMSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }


    func runCommand(_ command: String, completion: @escaping (String) -> Void) async {
        if !isHelperToolInstalled {
            completion("Helper tool is not installed")
            return
        }

        // Create a new connection each time or reuse existing one
        if helperConnection == nil {
            helperConnection = NSXPCConnection(machServiceName: helperToolIdentifier, options: .privileged)

            guard let connection = helperConnection else {
                completion("Failed to create connection")
                return
            }

            // Create the interface and set up protocols
            let interface = NSXPCInterface(with: HelperToolProtocol.self)
            connection.remoteObjectInterface = interface

            // Set up error handler
            connection.invalidationHandler = { [weak self] in
                print("XPC connection invalidated")
                self?.helperConnection = nil
            }

            // Start the connection
            connection.resume()
        }

        guard let connection = helperConnection else {
            completion("Connection not available")
            return
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                completion("Connection error: \(error.localizedDescription)")
            }
        }) as? HelperToolProtocol else {
            completion("Failed to get remote object")
            return
        }

        proxy.runCommand(command: command) { output in
            DispatchQueue.main.async {
                completion(output)
            }
        }
    }



}
