import Foundation

/// The user message every backend sends, in the shape `system-prompt.md` documents.
///
/// This lives outside any one provider because the contract belongs to the
/// prompt, not to a transport. Two backends formatting it differently would be
/// a silent behaviour change that no test downstream could catch.
public enum CheckInput {

    /// Context above the separator, the sentence to judge below it.
    ///
    /// `NONE` keeps the shape constant when there is no preceding sentence, so
    /// the cached prefix stays stable across calls.
    public static func format(sentence: String, previous: String?) -> String {
        let context = previous?.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = (context?.isEmpty == false ? context! : "NONE")
        return "\(head)\n---\n\(sentence)"
    }
}
