import SwiftUI

// MARK: - Diff Change

/// Represents a single change in a text diff.
struct DiffChange: Identifiable, Sendable {
    let id = UUID()
    let type: DiffChangeType
    let text: String
}

enum DiffChangeType: Sendable {
    case unchanged
    case added
    case removed
}

// MARK: - Text Diff

/// Word-level diff computation between two texts using LCS.
struct TextDiff: Sendable {
    let original: String
    let improved: String
    let changes: [DiffChange]

    static func compute(original: String, improved: String) -> TextDiff {
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let improvedWords = improved.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var changes: [DiffChange] = []
        let lcs = longestCommonSubsequence(originalWords, improvedWords)

        var origIdx = 0
        var impIdx = 0
        var lcsIdx = 0

        while origIdx < originalWords.count || impIdx < improvedWords.count {
            if lcsIdx < lcs.count {
                while origIdx < originalWords.count, originalWords[origIdx] != lcs[lcsIdx] {
                    changes.append(DiffChange(type: .removed, text: originalWords[origIdx]))
                    origIdx += 1
                }
                while impIdx < improvedWords.count, improvedWords[impIdx] != lcs[lcsIdx] {
                    changes.append(DiffChange(type: .added, text: improvedWords[impIdx]))
                    impIdx += 1
                }
                if lcsIdx < lcs.count {
                    changes.append(DiffChange(type: .unchanged, text: lcs[lcsIdx]))
                    origIdx += 1
                    impIdx += 1
                    lcsIdx += 1
                }
            } else {
                while origIdx < originalWords.count {
                    changes.append(DiffChange(type: .removed, text: originalWords[origIdx]))
                    origIdx += 1
                }
                while impIdx < improvedWords.count {
                    changes.append(DiffChange(type: .added, text: improvedWords[impIdx]))
                    impIdx += 1
                }
            }
        }

        return TextDiff(original: original, improved: improved, changes: changes)
    }

    private static func longestCommonSubsequence(_ source: [String], _ target: [String]) -> [String] {
        let sourceLen = source.count
        let targetLen = target.count
        guard sourceLen > 0, targetLen > 0 else { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: targetLen + 1), count: sourceLen + 1)

        for i in 1 ... sourceLen {
            for j in 1 ... targetLen {
                if source[i - 1] == target[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = sourceLen, j = targetLen
        while i > 0, j > 0 {
            if source[i - 1] == target[j - 1] {
                result.insert(source[i - 1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result
    }
}
