
import WidgetKit
import SwiftUI

@available(iOS 26.0, *)
@main
struct AlarmLiveActivityBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    AlarmkitLiveActivity()
  }
}
