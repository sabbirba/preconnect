import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
public struct NeverMetadata: AlarmMetadata, Codable, Hashable {
    public init() {}
}

@available(iOS 26.0, *)
struct AlarmkitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<NeverMetadata>.self) { context in
            // Lock Screen / Notification Center
            lockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    alarmTitle(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                countdownView(state: context.state, maxWidth: 44)
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                AlarmProgressView(mode: context.state.mode, tint: context.attributes.tintColor)
            } minimal: {
                AlarmProgressView(mode: context.state.mode, tint: context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    // MARK: Lock Screen

    func lockScreenView(
        attributes: AlarmAttributes<NeverMetadata>,
        state: AlarmPresentationState
    ) -> some View {
        VStack(spacing: 12) {
            HStack {
                alarmTitle(attributes: attributes, state: state)
                Spacer()
            }
            bottomView(attributes: attributes, state: state)
        }
        .padding(12)
    }

    func bottomView(
        attributes: AlarmAttributes<NeverMetadata>,
        state: AlarmPresentationState
    ) -> some View {
        HStack {
            countdownView(state: state)
                .font(.system(size: 36, design: .rounded))
            Spacer()
            AlarmControls(presentation: attributes.presentation, state: state)
        }
    }

    // MARK: Shared Subviews

    @ViewBuilder
    func countdownView(
        state: AlarmPresentationState,
        maxWidth: CGFloat = .infinity
    ) -> some View {
        Group {
            switch state.mode {
            case .countdown(let cd):
                Text(timerInterval: Date.now...cd.fireDate, countsDown: true)
            case .paused(let p):
                let remain = Duration.seconds(p.totalCountdownDuration - p.previouslyElapsedDuration)
                let pattern: Duration.TimeFormatStyle.Pattern =
                    remain > .seconds(3600) ? .hourMinuteSecond : .minuteSecond
                Text(remain.formatted(.time(pattern: pattern)))
            default:
                EmptyView()
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    @ViewBuilder
    func alarmTitle(
        attributes: AlarmAttributes<NeverMetadata>,
        state: AlarmPresentationState
    ) -> some View {
        let title: LocalizedStringResource? = switch state.mode {
        case .countdown:
            attributes.presentation.countdown?.title
        case .paused:
            attributes.presentation.paused?.title
        default:
            attributes.presentation.alert.title
        }
        Text(title ?? "")
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .padding(.leading, 4)
    }
}

// MARK: - Progress Indicator

@available(iOS 26.0, *)
struct AlarmProgressView: View {
    let mode: AlarmPresentationState.Mode
    let tint: Color

    var body: some View {
        switch mode {
        case .countdown(let cd):
            ProgressView(
                timerInterval: Date.now...cd.fireDate,
                countsDown: true,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(tint)
        case .paused(let p):
            let rem = p.totalCountdownDuration - p.previouslyElapsedDuration
            ProgressView(
                value: rem,
                total: p.totalCountdownDuration,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(tint)
        case .alert:
            Image(systemName: "bell.fill")
                .foregroundStyle(tint)
        default:
            EmptyView()
        }
    }
}

// MARK: - Control Buttons

@available(iOS 26.0, *)
struct AlarmControls: View {
    let presentation: AlarmPresentation
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 6) {
            switch state.mode {
            case .countdown:
                if let btn = presentation.countdown?.pauseButton {
                    ButtonView(config: btn,
                               intent: PauseIntent(alarmID: state.alarmID.uuidString),
                               tint: .orange)
                }
            case .paused:
                if let btn = presentation.paused?.resumeButton {
                    ButtonView(config: btn,
                               intent: ResumeIntent(alarmID: state.alarmID.uuidString),
                               tint: .green)
                }
            default:
                EmptyView()
            }
            // Always show the stop button
            ButtonView(config: presentation.alert.stopButton,
                       intent: StopIntent(alarmID: state.alarmID.uuidString),
                       tint: .red)
        }
    }
}

@available(iOS 26.0, *)
struct ButtonView<I: AppIntent>: View {
    let config: AlarmButton
    let intent: I
    let tint: Color

    var body: some View {
        Button(intent: intent) {
            Label(config.text, systemImage: config.systemImageName)
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .frame(width: 80, height: 30)
    }
}
