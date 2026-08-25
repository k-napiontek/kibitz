import Foundation

/// Turns recorded mistakes into a file Anki can import.
///
/// A plain text file rather than an `.apkg` or a call to AnkiConnect: it needs
/// no library, no running Anki and no undocumented format that shifts between
/// versions, and you can read the whole thing before you import it.
public enum AnkiExport {

    /// Anki reads these before the first card. `#html:true` is what makes the
    /// bold render instead of showing as literal tags.
    public static let header = ["#separator:tab", "#html:true", "#tags column:3"]

    public static func tsv(for mistakes: [Mistake]) -> String {
        (header + [""] + mistakes.map(row)).joined(separator: "\n") + "\n"
    }

    /// Dated, so exporting two weeks running does not silently overwrite the
    /// first file while it is still sitting in Downloads unimported.
    public static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "kibitz-\(formatter.string(from: date)).tsv"
    }

    private static func row(_ mistake: Mistake) -> String {
        [front(mistake), back(mistake), tags(mistake)].joined(separator: "\t")
    }

    /// The sentence as it was written. Recalling the whole pattern is the point,
    /// so the card asks the same question the popup answered.
    private static func front(_ mistake: Mistake) -> String {
        field(mistake.original)
    }

    private static func back(_ mistake: Mistake) -> String {
        let correction = SentenceDiff.spans(original: mistake.original, corrected: mistake.corrected)
            .map { span in
                // Escaped first, wrapped second. The other order turns the <b>
                // this line just added into &lt;b&gt; and the card shows the tag.
                let text = field(span.text)
                return span.isChanged ? "<b>\(text)</b>" : text
            }
            .joined()
        guard !mistake.whyL1.isEmpty else { return correction }
        return "\(correction)<br>\(field(mistake.whyL1))"
    }

    /// Anki splits tags on whitespace, so nothing here may contain a space.
    /// `Category` raw values are hyphenated for exactly this reason and a test
    /// walks `allCases` to keep it that way.
    private static func tags(_ mistake: Mistake) -> String {
        "kibitz \(mistake.category.rawValue) \(mistake.severity.rawValue)"
    }

    /// One field, safe to sit between two tabs.
    ///
    /// The quote is escaped even though HTML does not need it outside a tag:
    /// Anki reads the file with a CSV reader, and a field that begins with `"`
    /// opens a quoted region that swallows everything up to the next one.
    /// Escaping it at the source means no field can ever start with a quote, so
    /// the quoting rules never come into play at all.
    ///
    /// A tab would become a fourth column and a newline a second card, so
    /// neither is allowed to survive. Newlines become `<br>` because `#html:true`
    /// is on and a line break is what you wanted to see anyway.
    private static func field(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "\t", with: " ")
        result = result.replacingOccurrences(of: "\r\n", with: "<br>")
        result = result.replacingOccurrences(of: "\n", with: "<br>")
        return result.replacingOccurrences(of: "\r", with: "<br>")
    }
}
