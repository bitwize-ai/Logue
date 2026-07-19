import SwiftUI

/// Displays the Logue split-L icon mark from the bundled SVG resource.
/// Automatically picks dark or light variant based on the current color scheme.
struct LogoBrandView: View {
    var height: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme

    private var resourceName: String {
        colorScheme == .light ? "LogueMarkLight" : "LogueMark"
    }

    var body: some View {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
           let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel("Logue logo")
                .accessibilityAddTraits(.isImage)
        }
    }
}
