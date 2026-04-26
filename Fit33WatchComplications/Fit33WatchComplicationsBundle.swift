//
//  Fit33WatchComplicationsBundle.swift
//  Fit33WatchComplications
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Widget extension bundle for the watchOS complication.
//  The bundle declares which widgets ship in the extension; for v1
//  we only ship one (the GraphicCircular ring for the user's top
//  active 1v1 challenge).
//

import SwiftUI
import WidgetKit

@main
struct Fit33WatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        Fit33ChallengeRingComplication()
    }
}
