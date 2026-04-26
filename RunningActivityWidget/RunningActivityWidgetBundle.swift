//
//  RunningActivityWidgetBundle.swift
//  RunningActivityWidget
//
//  Created by Joseph Reed on 12/21/25.
//

import WidgetKit
import SwiftUI

@main
struct RunningActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunningActivityWidget()
        ActiveChallengeWidget()
        RunningActivityWidgetControl()
        RunningActivityWidgetLiveActivity()
    }
}
