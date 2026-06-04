//
//  FitTrackerRestTimerBundle.swift
//  Slice 7.5: entry point for the FitTrackerRestTimer widget extension.
//  Hosts only the rest-timer Live Activity for now; home-screen widgets
//  (Slice 11+) would be added to this bundle.
//

import WidgetKit
import SwiftUI

@main
struct FitTrackerRestTimerBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}
