import SwiftUI

// MARK: - E1 right pane placeholder (KMD-227)

struct E1ViewerPlaceholderView: View {
    private let tabLabels = ["Rendered", "Source", "D2", "Diff", "CSV"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(label == "Rendered" ? Color.white : Color.kobaMute)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(label == "Rendered" ? Color.kobaInk : Color.clear)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.kobaSurface)
            .overlay(KobaHDivider(), alignment: .bottom)

            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "doc.richtext")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.kobaMute)
                Text("Viewer tabs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.kobaInk)
                Text("KMD-227")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.kobaMute)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kobaPaper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaSurface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Viewer tabs placeholder, KMD-227")
    }
}