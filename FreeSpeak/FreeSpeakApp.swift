//
//  FreeSpeakApp.swift
//  FreeSpeak
//
//  Created by Aritra Das on 9/19/26.
//

import SwiftUI

@main
struct FreeSpeakApp: App {
  @State private var store = AppStore()
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(store)
    }
  }
}
