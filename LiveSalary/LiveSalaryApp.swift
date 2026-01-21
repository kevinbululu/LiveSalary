//
//  LiveSalaryApp.swift
//  LiveSalary
//
//  Created by jiquanbai on 2026/1/16.
//

import SwiftUI

@main
struct LiveSalaryApp: App {
    @StateObject private var store = SalaryStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(store: store)
        } label: {
            MenuBarLabelView(store: store)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("LiveSalary", id: "main") {
            ContentView()
                .environmentObject(store)
        }
        .handlesExternalEvents(matching: ["main"])
    }
}
