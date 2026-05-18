import Foundation

/// String normalization helpers for comparing transcribed speech with target sentences.
enum TextNormalizer {
    /// Apply the full normalization pipeline used by the audio matcher.
    static func normalize(_ input: String, stripFinalCopula: Bool) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop punctuation and whitespace-equivalent characters.
        let punct = CharacterSet(charactersIn:
            "。、，,．.!！?？「」『』()（）[]［］{}｛｝・…ー~〜:：;；'\"\u{3000}")
            .union(.whitespaces)
        s = String(s.unicodeScalars.filter { !punct.contains($0) })

        // Katakana → Hiragana, then fullwidth → halfwidth for any latin/digits.
        s = s.applyingTransform(StringTransform("Katakana-Hiragana"), reverse: false) ?? s
        s = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        s = s.lowercased()

        if stripFinalCopula {
            for suffix in ["でした", "ました", "です", "ます", "だった", "だ"] where s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                break
            }
        }
        return s
    }
}
