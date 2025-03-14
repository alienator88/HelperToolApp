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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            HStack {
                Text(helperToolManager.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        Task {
                            await helperToolManager.manageHelperTool()
                        }
                    }

                Spacer()

                Button(action: {
                    helperToolManager.openSMSettings()
                }) {
                    Label("Settings", systemImage: "gear")
                        .padding(4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
            }


            Divider()


            HStack {
                TextField("Enter command here", text: $commandToRun)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await helperToolManager.runCommand(commandToRun) { output in
                                commandOutput = output
                            }
                        }
                    }

                Button(action: {
                    Task {
                        await helperToolManager.runCommand(commandToRun) { output in
                            commandOutput = output
                        }
                    }
                }) {
                    Label("Execute", systemImage: "play")
                        .padding(4)
                }
                .buttonStyle(.borderedProminent)

            }

            ScrollView {
                Text(commandOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.tertiary.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .navigationTitle("Helper tool is \(helperToolManager.status.lowercased())")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Register") {
                    Task {
                        await helperToolManager.manageHelperTool(action: .install)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Unregister") {
                    Task {
                        await helperToolManager.manageHelperTool(action: .uninstall)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

            }
        }
        .toolbarBackground(.clear)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await helperToolManager.manageHelperTool()
            }
        }
    }
}

