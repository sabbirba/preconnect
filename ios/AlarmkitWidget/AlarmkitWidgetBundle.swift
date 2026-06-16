

import WidgetKit
import SwiftUI

@available(iOS 26.0, *)
@main
struct PreConnectAlarmLiveActivityBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    AlarmkitLiveActivity()
  }
}
