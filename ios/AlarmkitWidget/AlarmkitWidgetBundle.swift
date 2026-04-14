//
//  AlarmkitWidgetBundle.swift
//  AlarmkitWidget
//
//  Created by Gautier de Lataillade on 19/6/25.
//

import WidgetKit
import SwiftUI

@available(iOS 26.0, *)
@main
struct PreconnectAlarmLiveActivityBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    AlarmkitLiveActivity()
  }
}
