import KibitzCore
import SwiftUI

/// The week's mistakes, most repeated first, each one a card you can decline.
///
/// Deliberately louder than `PopupView`. That one appears over what you are
/// writing and has to get out of the way; this one you opened on purpose and
/// came to read.
struct ReviewView: View {
    @Bindable var model: ReviewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mistakes worth repeating")
                .font(.headline)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private var summary: String {
        guard let counts = model.digest?.counts else { return "Reading the log..." }
        guard counts.checked > 0 else { return "No sentences checked yet." }
        return "\(counts.checked) sentences checked, \(counts.withMistake) had a mistake."
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let failure = model.failure {
            message(
                title: "The mistake log is not readable",
                detail: failure,
                action: ("Reveal in Finder", model.revealLog)
            )
        } else if model.isEmpty {
            message(
                title: "Nothing to review",
                detail: "Either you made no mistakes, or every one of them is already a card.",
                action: nil
            )
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(model.digest?.groups ?? []) { group in
                Section {
                    ForEach(group.items) { mistake in
                        row(mistake)
                    }
                } header: {
                    HStack {
                        Text(group.category.rawValue)
                        Spacer()
                        Text("\(group.count) this week")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ mistake: Mistake) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { model.selected.contains(mistake.id) },
                    set: { _ in model.toggle(mistake.id) }
                )
            ) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(mistake.original)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                CorrectionText(original: mistake.original, corrected: mistake.corrected)
                    .font(.callout)
                if !mistake.whyL1.isEmpty {
                    Text(mistake.whyL1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if mistake.severity == .high {
                Text("serious")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func message(title: String, detail: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Select all", action: model.selectAll)
            Button("Select none", action: model.selectNone)
            if let note = model.lastExport {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Export \(model.selected.count) to Anki...") {
                Task { await model.exportSelected() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty)
        }
        .padding(12)
    }
}
