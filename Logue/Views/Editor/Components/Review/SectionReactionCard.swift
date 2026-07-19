import SwiftUI

struct SectionReactionCard: View {
    let reaction: SectionReaction

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: reaction.dominantEmotion.icon)
                    .font(.title3)
                    .foregroundStyle(reaction.dominantEmotion.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reaction.sectionTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(reaction.dominantEmotion.rawValue)
                        .font(.caption)
                        .foregroundStyle(reaction.dominantEmotion.color)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text(reaction.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(Array(reaction.typedEmotionScores.sorted { $0.value > $1.value }), id: \.key) { emotion, score in
                            HStack(spacing: 8) {
                                Image(systemName: emotion.icon)
                                    .font(.caption2)
                                    .foregroundStyle(emotion.color)
                                    .frame(width: 16)

                                Text(emotion.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                ProgressView(value: Double(score), total: 100)
                                    .tint(emotion.color)

                                Text("\(score)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
