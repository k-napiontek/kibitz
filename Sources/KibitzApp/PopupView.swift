import KibitzCore
import SwiftUI

/// Deliberately quiet. This appears over whatever someone is writing, so it
/// borrows system materials and gets out of the way. The one place worth any
/// visual weight is the diff: showing which words changed is the difference
/// between reading an answer and comparing two sentences yourself.
struct PopupView: View {
    let verdict: Verdict
    let original: String
    let hotkeyLabel: String
    let onApply: () -> Void
    let onDismiss: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    private var spans: [SentenceDiff.Span] {
        SentenceDiff.spans(original: original, corrected: verdict.corrected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            correction
            if !verdict.whyL1.isEmpty {
                Text(verdict.whyL1)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(14)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        // simultaneousGesture so Apply and dismiss still receive their taps.
        // NSHostingView swallows the mouse events an AppKit window drag needs,
        // so the move has to be driven from here.
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { onDragChanged($0.translation) }
                .onEnded { _ in onDragEnded() }
        )
    }

    /// Built as one AttributedString so the changed words can carry their own
    /// weight and colour without concatenating Text, which macOS 26 deprecates.
    private var correction: some View {
        var result = AttributedString()
        for span in spans {
            var piece = AttributedString(span.text)
            piece.foregroundColor = span.isChanged ? .primary : .secondary
            piece.inlinePresentationIntent = span.isChanged ? .stronglyEmphasized : nil
            result.append(piece)
        }
        return Text(result)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(verdict.category.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onApply) {
                Text("Apply  \(hotkeyLabel)")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
    }
}
