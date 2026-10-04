import Foundation
import Testing
@testable import JLPT_Grammar_Drill

/// Covers the occurrence-targeted blanking added for sentences where the blank
/// target appears more than once (`blank_occurrence` in the exercise JSON).
struct BlankOccurrenceTests {
    private let blank = "＿＿＿"

    private func makeExercise(sentence: String, target: String, occurrence: Int?) -> SessionExercise {
        SessionExercise(
            id: "test_001_1",
            grammarId: "test_001",
            pattern: target,
            meaning: "meaning",
            level: "N4",
            exampleSentence: sentence,
            translation: "translation",
            blankTarget: target,
            wrongChoices: [],
            wrongChoiceExplanations: [],
            blankOccurrence: occurrence
        )
    }

    // MARK: - String.rangeOfOccurrence

    @Test func firstOccurrenceRange() {
        let s = "ABCABCABC"
        let r = s.rangeOfOccurrence(of: "B", occurrence: 1)
        #expect(r != nil)
        #expect(s.distance(from: s.startIndex, to: r!.lowerBound) == 1)
    }

    @Test func nthOccurrenceRange() {
        let s = "ABCABCABC"
        let r = s.rangeOfOccurrence(of: "B", occurrence: 3)
        #expect(r != nil)
        #expect(s.distance(from: s.startIndex, to: r!.lowerBound) == 7)
    }

    @Test func occurrenceBeyondCountIsNil() {
        #expect("ABCABC".rangeOfOccurrence(of: "B", occurrence: 3) == nil)
    }

    @Test func zeroAndNegativeOccurrencesAreNil() {
        #expect("ABC".rangeOfOccurrence(of: "B", occurrence: 0) == nil)
        #expect("ABC".rangeOfOccurrence(of: "B", occurrence: -1) == nil)
    }

    @Test func emptyTargetIsNil() {
        #expect("ABC".rangeOfOccurrence(of: "", occurrence: 1) == nil)
    }

    @Test func occurrencesDoNotOverlap() {
        // "aaa" contains "aa" at 0 and (overlapping) at 1; non-overlapping search
        // must not find a second occurrence.
        #expect("aaa".rangeOfOccurrence(of: "aa", occurrence: 2) == nil)
    }

    // MARK: - SessionExercise.blanked(with:)

    @Test func nilOccurrenceBlanksEveryOccurrence() {
        // Paired patterns (〜とか〜とか) want every occurrence blanked.
        let ex = makeExercise(sentence: "りんごとかみかんとか買った", target: "とか", occurrence: nil)
        #expect(ex.blanked(with: blank) == "りんご\(blank)みかん\(blank)買った")
    }

    @Test func occurrenceBlanksOnlyThatOccurrence() {
        // し appears in 面白いし and in 勉強しています; occurrence 1 is the grammar point.
        let ex = makeExercise(sentence: "面白いし、毎日勉強しています", target: "し", occurrence: 1)
        #expect(ex.blanked(with: blank) == "面白い\(blank)、毎日勉強しています")
    }

    @Test func secondOccurrenceLeavesFirstIntact() {
        let ex = makeExercise(sentence: "ABxAB", target: "AB", occurrence: 2)
        #expect(ex.blanked(with: blank) == "ABx\(blank)")
    }

    @Test func outOfRangeOccurrenceFallsBackToBlankingAll() {
        let ex = makeExercise(sentence: "ABxAB", target: "AB", occurrence: 5)
        #expect(ex.blanked(with: blank) == "\(blank)x\(blank)")
    }

    // MARK: - SessionExercise.blankRange

    @Test func blankRangeUsesOccurrence() {
        let ex = makeExercise(sentence: "ABxAB", target: "AB", occurrence: 2)
        let r = ex.blankRange
        #expect(r != nil)
        #expect(ex.exampleSentence.distance(from: ex.exampleSentence.startIndex, to: r!.lowerBound) == 3)
    }

    @Test func blankRangeDefaultsToFirstOccurrence() {
        let ex = makeExercise(sentence: "ABxAB", target: "AB", occurrence: nil)
        let r = ex.blankRange
        #expect(r != nil)
        #expect(r!.lowerBound == ex.exampleSentence.startIndex)
    }
}
