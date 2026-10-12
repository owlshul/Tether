//
//  MessagesPane.swift
//  Tether
//

import SwiftUI

struct MessagesPane: View {
    @Bindable var device: DeviceViewModel
    @State private var selectedThreadId: Int64?
    @State private var searchText = ""

    private var filteredThreads: [SMSConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return device.smsThreads }
        return device.smsThreads.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.snippet.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedThread: SMSConversation? {
        guard let selectedThreadId else { return nil }
        return device.smsThreads.first { $0.id == selectedThreadId }
    }

    var body: some View {
        if device.smsThreads.isEmpty {
            ContentUnavailableView {
                Label("No Conversations", systemImage: "message")
            } description: {
                Text("Text messages sync from \(device.name). Make sure KDE Connect has SMS permission on the phone.")
            } actions: {
                Button("Sync Messages") { device.refreshMessages() }
            }
            .task { device.refreshMessages() }
        } else {
            HStack(spacing: 0) {
                threadList
                    .frame(width: 280)
                Divider()
                Group {
                    if let selectedThread {
                        ConversationView(thread: selectedThread, device: device)
                            .id(selectedThread.id)
                    } else {
                        ContentUnavailableView("No Conversation Selected", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                if selectedThreadId == nil { selectedThreadId = device.smsThreads.first?.id }
            }
            .onChange(of: selectedThreadId) {
                if let selectedThreadId { device.openThread(selectedThreadId) }
            }
        }
    }

    private var threadList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { searchText = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: 8, style: .continuous))
            .padding(10)

            List(filteredThreads, selection: $selectedThreadId) { thread in
                ThreadRow(thread: thread)
                    .tag(thread.id)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ThreadRow: View {
    let thread: SMSConversation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            InitialsAvatar(name: thread.title, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.title)
                        .fontWeight(thread.unreadCount > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MessageDate.short(thread.lastDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(thread.snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if thread.unreadCount > 0 {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                            .accessibilityLabel("Unread")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ConversationView: View {
    let thread: SMSConversation
    let device: DeviceViewModel
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    private struct DayGroup: Identifiable {
        let day: Date
        var messages: [SMSMessage]
        var id: Date { day }
    }

    /// Messages split into calendar days, in order.
    private var days: [DayGroup] {
        let calendar = Calendar.current
        var result: [DayGroup] = []
        for message in thread.messages.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: message.date)
            if result.last?.day == day {
                result[result.count - 1].messages.append(message)
            } else {
                result.append(DayGroup(day: day, messages: [message]))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                InitialsAvatar(name: thread.title, size: 28)
                Text(thread.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(days) { group in
                        Text(group.day.formatted(date: .complete, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        ForEach(group.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)

            composer
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Text Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5)
                }

            Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title)
                .foregroundStyle(.tint)
                .disabled(trimmedDraft.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty, !thread.addresses.isEmpty else { return }
        device.sendSMS(to: thread.addresses, message: text, threadId: thread.threadId)
        draft = ""
        isComposerFocused = true
    }
}

private struct MessageBubble: View {
    let message: SMSMessage

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 80) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                if !message.attachments.isEmpty {
                    Label("\(message.attachments.count) attachment\(message.attachments.count == 1 ? "" : "s")", systemImage: "paperclip")
                        .font(.caption)
                }
                if !message.body.isEmpty {
                    Text(message.body)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(message.isOutgoing ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                message.isOutgoing ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)),
                in: .rect(cornerRadius: 17, style: .continuous)
            )
            .help(message.date.formatted(date: .abbreviated, time: .shortened))

            if !message.isOutgoing { Spacer(minLength: 80) }
        }
    }
}

enum MessageDate {
    /// Time for today, weekday within a week, short date otherwise (like Messages).
    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
