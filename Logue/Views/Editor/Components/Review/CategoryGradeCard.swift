import SwiftUI

struct CategoryGradeCard: View {
    let grade: Grade
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: grade.category.icon)
                    .font(.title3)
                    .foregroundStyle(grade.category.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(grade.category.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text(grade.letterGrade)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor(grade.score))
                }

                Spacer()

                Text("\(grade.score)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(scoreColor(grade.score))

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            ProgressView(value: Double(grade.score), total: 100)
                .tint(scoreColor(grade.score))

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    Text(grade.feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !grade.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppThemeConstants.success)
                                    .font(.caption)
                                Text("Strengths")
                                    .font(.caption.weight(.semibold))
                            }

                            ForEach(grade.strengths, id: \.self) { strength in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•").font(.caption2)
                                    Text(strength).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !grade.improvements.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(AppThemeConstants.warning)
                                    .font(.caption)
                                Text("Areas for Improvement")
                                    .font(.caption.weight(.semibold))
                            }

                            ForEach(grade.improvements, id: \.self) { improvement in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•").font(.caption2)
                                    Text(improvement).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return AppThemeConstants.success
        }
        if score >= 80 {
            return AppThemeConstants.brandPrimary
        }
        if score >= 70 {
            return AppThemeConstants.warning
        }
        return AppThemeConstants.error
    }
}
