import SwiftUI
import PassthroughCore
import PassthroughUI

/// A Mac's profile picture: its initial on a color picked from its ID, with an
/// amber dot when it needs you.
struct MacAvatar: View {
    let macID: String
    let name: String
    var badge = false
    var size: CGFloat = 30

    private var color: Color {
        let palette = PTTheme.avatarPalette
        return palette[MacProfiles.colorIndex(macID: macID, paletteCount: palette.count)]
    }

    var body: some View {
        Text(MacProfiles.initial(name))
            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay(alignment: .topTrailing) {
                if badge {
                    Circle().fill(PTTheme.warning)
                        .frame(width: size * 0.4, height: size * 0.4)
                        .overlay(Circle().strokeBorder(PTColor.background, lineWidth: 2))
                        .offset(x: size * 0.1, y: -size * 0.1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your Macs")
            .accessibilityValue(badge ? "\(name), another Mac needs you" : name)
    }
}

/// What the switcher hands its host to present once it has closed.
enum SwitcherNext { case addMac, settings }

/// "Your Macs": every paired Mac with what it's doing, then Add a Mac and Settings.
struct MacSwitcherSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: ShellRouter
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var shell: ShellModel
    @Binding var then: SwitcherNext?

    private struct Row: Identifiable { let id: String; let name: String }

    private var rows: [Row] {
        model.pairedClients.map { client in
            Row(id: client.id, name: shell.macs.first { $0.macID == client.id }?.macName ?? client.name)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PTSurface(padding: 6) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { Divider().padding(.leading, 62) }
                                macRow(row)
                            }
                        }
                    }
                    PTSurface(padding: 6) {
                        VStack(spacing: 0) {
                            actionRow("Add a Mac", systemImage: "plus") { then = .addMac; dismiss() }
                            Divider().padding(.leading, 62)
                            actionRow("Settings", systemImage: "gearshape") { then = .settings; dismiss() }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(PTColor.background)
            .navigationTitle("Your Macs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func macRow(_ row: Row) -> some View {
        let status = shell.status(for: row.id)
        var asking: String?
        if case .asking = status {
            asking = askingSession(on: row.id)
        }
        let current = row.id == shell.selectedMacID
        let isAsking = { if case .asking = status { return true } else { return false } }()
        return Button { choose(row.id, asking: asking) } label: {
            HStack(spacing: 12) {
                MacAvatar(macID: row.id, name: row.name, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.body.weight(.semibold)).lineLimit(1)
                    Text(MacProfiles.statusText(status, now: .now))
                        .font(.caption)
                        .foregroundStyle(isAsking ? PTColor.attentionText : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if current { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(PTTheme.down) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func choose(_ macID: String, asking: String?) {
        dismiss()
        shell.select(macID)
        if let asking {
            // The switch has set up the Mac's tabs; the terminal then attaches to the question.
            DispatchQueue.main.async { router.terminal = .attach(asking) }
        }
    }

    private func actionRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                Text(title).font(.body)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The session waiting on a question on that Mac: this one's live list, or what the watch last saw.
    private func askingSession(on macID: String) -> String? {
        let sessions = macID == shell.selectedMacID ? shell.visibleSessions : (shell.watcher.seen[macID]?.sessions ?? [])
        return sessions.first(where: \.isAsking)?.id
    }
}
