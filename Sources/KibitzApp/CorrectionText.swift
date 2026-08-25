import KibitzCore
import SwiftUI

/// A corrected sentence with the changed words carrying the weight.
///
/// One renderer, used by the popup and by the weekly review. The two of them
/// showing the same correction differently would be a bug nobody would think to
/// go looking for.
///
/// Built as a single `AttributedString` rather than concatenated `Text`, which
/// macOS 26 deprecates.
struct CorrectionText: View {
    let original: String
    let corrected: String

    var body: some View {
        Text(Self.attributed(original: original, corrected: corrected))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(original: String, corrected: String) -> AttributedString {
        var result = AttributedString()
        for span in SentenceDiff.spans(original: original, corrected: corrected) {
            var piece = AttributedString(span.text)
            piece.foregroundColor = span.isChanged ? .primary : .secondary
            piece.inlinePresentationIntent = span.isChanged ? .stronglyEmphasized : nil
            result.append(piece)
        }
        return result
    }
}
