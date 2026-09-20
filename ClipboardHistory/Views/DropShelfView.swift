import SwiftUI

struct DropShelfView: View {
    @Binding var isTargeted: Bool
    var isExpanded: Bool = true
    var onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "tray.and.arrow.down")
                .font(.title3)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Barclip")
                .font(.headline)
            Text("拖到此处暂存")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(DropShelfGlassEffect())
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .compositingGroup()
        .scaleEffect(isExpanded ? 1 : 0.28, anchor: .top)
        .opacity(isExpanded ? 1 : 0)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            FileStagingTransfer.scheduleLoad(providers) { urls in
                if !urls.isEmpty { onDrop(urls) }
            }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("拖到此处暂存")
        .accessibilityValue("Barclip")
    }
}

private struct DropShelfGlassEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}
