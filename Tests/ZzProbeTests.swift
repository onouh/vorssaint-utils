// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

private struct ProbeBody: View {
    let event: NotchCalendarEvent
    let day: Date
    let now: Date
    let isNext: Bool
    let text: NotchCalendarStrings
    let countdown: Bool?
    @Environment(\.colorSchemeContrast) private var contrast

    private var ongoing: Bool { !event.allDay && event.start <= now && event.end > now }
    private var ended: Bool { event.end <= now }

    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ongoing || isNext {
                Text(ongoing ? text.ongoing : text.next)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ongoing ? .mint : .white.opacity(0.7))
                    .lineLimit(1)
            }
            Text(event.title.isEmpty ? text.untitled : event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(ended ? 0.65 : 1))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Group {
                    Text(event.start, format: .dateTime.hour().minute())
                        + Text(" · ") + Text(event.end, format: .dateTime.hour().minute())
                }
                .fixedSize(horizontal: false, vertical: true)
                if countdown == true {
                    Image(systemName: "timer")
                        .accessibilityLabel(text.countdown)
                        .frame(maxHeight: 14)
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            Text(event.calendar)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue))
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue).opacity(ongoing ? 0.2 : 0.1)),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : ongoing ? 0.16 : 0.05), lineWidth: 0.75)
        }
        .clipped()
    }
}

private struct ProbeSpanLess: View {
    let event: NotchCalendarEvent
    let day: Date
    let now: Date
    let isNext: Bool
    let text: NotchCalendarStrings
    let countdown: Bool?
    @Environment(\.colorSchemeContrast) private var contrast

    private var ongoing: Bool { !event.allDay && event.start <= now && event.end > now }
    private var ended: Bool { event.end <= now }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ongoing || isNext {
                Text(ongoing ? text.ongoing : text.next)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ongoing ? .mint : .white.opacity(0.7))
                    .lineLimit(1)
            }
            Text(event.title.isEmpty ? text.untitled : event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(ended ? 0.65 : 1))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(event.start, format: .dateTime.hour().minute())
                    + Text(" · ") + Text(event.end, format: .dateTime.hour().minute())
                if countdown == true {
                    Image(systemName: "timer")
                        .accessibilityLabel(text.countdown)
                        .frame(maxHeight: 14)
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            Text(event.calendar)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue))
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue).opacity(ongoing ? 0.2 : 0.1)),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : ongoing ? 0.16 : 0.05), lineWidth: 0.75)
        }
        .clipped()
    }
}

extension NotchCompactTests {
    static func probe(_ suite: TestSuite) {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let text = FeatureStrings.notchCalendar(.sk)

        func measure(_ view: some View) -> CGFloat {
            let host = NSHostingView(rootView: view.frame(width: 192))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }

        func event(title: String) -> NotchCalendarEvent {
            NotchCalendarEvent(id: "layout", title: title, calendar: "Calendar",
                               start: day, end: day.addingTimeInterval(3600),
                               allDay: false, location: "Meeting room")
        }

        // b0: raw card only (no button, no contextMenu)
        let b0short = measure(ProbeBody(event: event(title: "Meeting"), day: day, now: day, isNext: true, text: text, countdown: nil))
        let b0chosen = measure(ProbeBody(event: event(title: "Meeting"), day: day, now: day, isNext: true, text: text, countdown: true))
        // b1: card wrapped in Button(.plain)
        let b1short = measure(Button { } label: { ProbeBody(event: event(title: "Meeting"), day: day, now: day, isNext: true, text: text, countdown: nil) }.buttonStyle(.plain))
        let b1chosen = measure(Button { } label: { ProbeBody(event: event(title: "Meeting"), day: day, now: day, isNext: true, text: text, countdown: true) }.buttonStyle(.plain))
        // b2: card wrapped in Button plus production contextMenu modifier
        let b2short = measure(Button { } label: { ProbeBody(event: event(title: "Meeting"), day: day, now: day, isNext: true, text: text, countdown: nil) }.buttonStyle(.plain)
            .modifier(NotchCountdownChoice(chosen: nil, text: text, choose: { _ in })))
        let b2chosen = measure(Button { } label: { ProbeBody(event: event(title: "Meeting"), day: day, now: day, isNext: true, text: text, countdown: true) }.buttonStyle(.plain)
            .modifier(NotchCountdownChoice(chosen: true, text: text, choose: { _ in })))
        // b3: production body, but the span Group replaced by a plain Text
        // (no branch Group wrapper). Isolates whether the Group wrapper with
        // branches is the layout difference between twin and production row.
        let b3short = measure(spanText(event: event(title: "Meeting"), day: day, text: text, chosen: nil))
        let b3chosen = measure(spanText(event: event(title: "Meeting"), day: day, text: text, chosen: true))
        print("PROBECHROME2: b3 short=\(b3short) chosen=\(b3chosen)")
        suite.expect(true, "probe ran")
    }

    static func spanText(event: NotchCalendarEvent, day: Date, text: NotchCalendarStrings, chosen: Bool?) -> some View {
        ProbeSpanLess(event: event, day: day, now: day, isNext: true, text: text, countdown: chosen)
    }
}

enum ZzProbeTests {
    static func run(_ suite: TestSuite) {
        NotchCompactTests.probe(suite)
    }
}
