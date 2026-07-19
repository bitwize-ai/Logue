import SwiftUI

struct FactCheckCard: View {
    let factCheck: FactCheck

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: factCheck.status.icon)
                    .font(.title3)
                    .foregroundStyle(factCheck.status.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(factCheck.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(factCheck.status.color)

                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption2)
                        Text("\(factCheck.confidence)% confidence")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }

            Text(factCheck.claim)
                .font(.subheadline.weight(.medium))
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text(factCheck.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !factCheck.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sources:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(factCheck.sources, id: \.self) { source in
                                HStack(spacing: 4) {
                                    Image(systemName: "link.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AppThemeConstants.brandPrimary)
                                    Text(source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}
