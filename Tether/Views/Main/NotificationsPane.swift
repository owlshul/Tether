//
//  NotificationsPane.swift
//  Tether
//

import SwiftUI

struct NotificationsPane: View {
    let device: DeviceViewModel

    var body: some View {
        if device.notifications.isEmpty {
            ContentUnavailableView(
                "No Notifications",
                systemImage: "bell.slash",
                description: Text("Notifications on \(device.name) show up here and in Notification Center. Turn on notification sync in KDE Connect on your phone if they don't.")
            )
        } else {
            Form {
                Section {
                    ForEach(device.notifications) { notification in
                        NotificationRow(notification: notification, device: device)
                    }
                } header: {
                    HStack {
                        Text("On \(device.name)")
                        Spacer()
                        if device.notifications.contains(where: \.isDismissable) {
                            Button("Clear All") {
                                for notification in device.notifications where notification.isDismissable {
                                    device.dismiss(notification)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.default, value: device.notifications)
        }
    }
}

private struct NotificationRow: View {
    let notification: PhoneNotification
    let device: DeviceViewModel

    @State private var isReplying = false
    @State private var reply = ""
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(notification.appName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(notification.date, format: .relative(presentation: .named))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !notification.title.isEmpty {
                Text(notification.title)
                    .fontWeight(.semibold)
            }
            if !notification.text.isEmpty {
                Text(notification.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isReplying {
                HStack(spacing: 8) {
                    TextField("Reply to \(notification.title.isEmpty ? notification.appName : notification.title)", text: $reply)
                        .textFieldStyle(.roundedBorder)
                        .focused($isReplyFocused)
                        .onSubmit(sendReply)
                    Button("Cancel") { isReplying = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Send", action: sendReply)
                        .keyboardShortcut(.defaultAction)
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
                .onAppear { isReplyFocused = true }
            } else if notification.code != nil || notification.replyId != nil || notification.isDismissable {
                HStack(spacing: 16) {
                    if let code = notification.code {
                        CopyCodeButton(code: code)
                    }
                    if notification.replyId != nil {
                        Button("Reply") { isReplying = true }
                    }
                    if notification.isDismissable {
                        Button("Dismiss") { device.dismiss(notification) }
                    }
                }
                .buttonStyle(.link)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let code = notification.code {
                Button("Copy Code \(code)") { NotificationPlugin.copyToPasteboard(code) }
            }
            if notification.replyId != nil {
                Button("Reply") { isReplying = true }
            }
            if notification.isDismissable {
                Button("Dismiss on Phone") { device.dismiss(notification) }
            }
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(notification.text, forType: .string)
            }
        }
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        device.reply(to: notification, text: text)
        reply = ""
        isReplying = false
    }
}

/// Copies a verification code and says so for a moment.
struct CopyCodeButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            NotificationPlugin.copyToPasteboard(code)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Text(copied ? "Copied" : "Copy Code \(code)")
                .monospacedDigit()
        }
        .accessibilityLabel(copied ? "Copied" : "Copy code \(code.map(String.init).joined(separator: " "))")
    }
}

#if DEBUG
#Preview {
    NotificationsPane(device: .mockConnectedPhone())
        .frame(width: 640, height: 520)
}
#endif
