import SwiftUI

/// A button that briefly swaps its icon for a checkmark when its action succeeds. With alternatives,
/// it becomes a split button whose menu offers them too.
struct FlashButton: View {
    struct Alternative: Identifiable {
        let title: String
        let action: () async -> Bool

        var id: String { title }
    }

    private let title: String
    private let systemImage: String
    private let doneTitle: String
    private let alternatives: [Alternative]
    private let action: () async -> Bool

    @State private var isDone = false

    init(
        _ title: String,
        systemImage: String,
        doneTitle: String,
        alternatives: [Alternative] = [],
        action: @escaping () async -> Bool
    ) {
        self.title = title
        self.systemImage = systemImage
        self.doneTitle = doneTitle
        self.alternatives = alternatives
        self.action = action
    }

    var body: some View {
        Group {
            if alternatives.isEmpty {
                Button { run(action) } label: { label }
            } else {
                Menu {
                    ForEach(alternatives) { alternative in
                        Button(alternative.title) { run(alternative.action) }
                    }
                } label: {
                    label
                } primaryAction: {
                    run(action)
                }
                .fixedSize()
            }
        }
        .help(isDone ? doneTitle : title)
    }

    private var label: some View {
        Label(isDone ? doneTitle : title, systemImage: isDone ? "checkmark" : systemImage)
            .contentTransition(.symbolEffect(.replace))
    }

    private func run(_ action: @escaping () async -> Bool) {
        Task {
            guard await action() else {
                return
            }

            isDone = true
            try? await Task.sleep(for: .seconds(1.5))
            isDone = false
        }
    }
}
