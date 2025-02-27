//
//  ContentView.swift
//  HelperToolApp
//
//  Created by Alin Lupascu on 2/25/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var helperToolManager = HelperToolManager()
    @State private var commandOutput: String = ""
    @State private var commandToRun: String = "whoami"
    @State private var isInstalling: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack {
                    Text("Helper Tool Status: \(helperToolManager.isHelperToolInstalled ? "Installed" : "Not Installed")")
                        .fontWeight(.bold)
                    Text("\(helperToolManager.statusText)")
                }

                Button("Refresh Status") {
                    Task {
                        await helperToolManager.checkHelperToolStatus(error: nil)
                    }
                }

            }



            Button(action: {
                isInstalling = true
                Task {
                    if helperToolManager.isHelperToolInstalled {
                        await helperToolManager.uninstallHelperTool()
                    } else {
                        await helperToolManager.installHelperTool()
                    }
                    isInstalling = false
                }
            }) {
                if isInstalling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text(helperToolManager.isHelperToolInstalled ? "Unregister Helper Tool" : "Register Helper Tool")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling)

            HStack {
                TextField("Command to run", text: $commandToRun)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Run Command") {
                    Task {
                        await helperToolManager.runCommand(commandToRun) { output in
                            commandOutput = output
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!helperToolManager.isHelperToolInstalled || isInstalling)
            }
            .padding(.horizontal)

            ScrollView {
                Text(commandOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
            .padding()
        }
        .padding()
    }
}

