//
//  HelperToolManager.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2/26/25.
//
import ServiceManagement

@MainActor
class HelperToolManager: ObservableObject {
    private var helperConnection: NSXPCConnection?

    @Published var isHelperToolInstalled: Bool = false
    @Published var statusText: String = "Checking..."

    init() {
        Task {
            await checkHelperToolStatus(error: nil)
        }
    }

    func installHelperTool() async {
        do {
            let plistName = "\(helperToolIdentifier).plist"
            let service = SMAppService.daemon(plistName: plistName)
            try service.register()
            print("Service registered successfully")

            await checkHelperToolStatus(error: nil)

            SMAppService.openSystemSettingsLoginItems()
        } catch {
            await checkHelperToolStatus(error: error) // Check status for detailed error message
            statusText = "Installation failed: \(self.statusText)"
            print("Failed to install helper: \(error.localizedDescription)")
        }
    }

    func uninstallHelperTool() async {
        do {
            let service = SMAppService.daemon(plistName: "\(helperToolIdentifier).plist")
            try await service.unregister()

            // Close any existing connection
            helperConnection?.invalidate()
            helperConnection = nil

            await checkHelperToolStatus(error: nil)
        } catch {
            await checkHelperToolStatus(error: error) // Check status for detailed error message
            statusText = "Uninstallation failed: \(self.statusText)"
            print("Failed to uninstall helper: \(error.localizedDescription)")
        }
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

    func checkHelperToolStatus(error: Error?) async {
        let service = SMAppService.daemon(plistName: "\(helperToolIdentifier).plist")

        // Check for specific error cases first
        if let nsError = error as NSError? {
            switch nsError.code {
            case kSMErrorAlreadyRegistered:
                statusText = "The service is already registered and enabled."
            case kSMErrorLaunchDeniedByUser:
                statusText = "The user denied permission. Go to system settings/preferences > Login Items and enable the service."
            case kSMErrorInvalidSignature:
                statusText = "Invalid code signature. Ensure the app and helper tool is properly signed."
            case 1: // Operation not permitted
                statusText = "The service requires user authorization. Enable it in system settings/preferences > Login Items."
            default:
                statusText = "Installation failed with unknown error: \(nsError.localizedDescription)"
            }
        } else {
            // If no error, check status normally
            switch service.status {
            case .notRegistered:
                statusText = "The service hasn’t been registered, you smay register it now."
            case .enabled:
                statusText = "The service has been successfully registered and is eligible to run."
            case .requiresApproval:
                statusText = "The service has been successfully registered, but the user needs to enable it in system settings/preferences > Login Items."
            case .notFound:
                statusText = "An error occurred and the SM framework couldn’t find this service."
            @unknown default:
                statusText = "Unknown status. Possibly a new or undocumented status code."
            }
        }

        isHelperToolInstalled = (service.status == .enabled)
    }

}

