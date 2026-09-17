import SwiftUI

struct DropShelfView: View {
    @Binding var isTargeted: Bool
    var arrowX: CGFloat = MenuBarDropAnchor.shelfSize.width / 2
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
        .padding(.top, MenuBarDropAnchor.arrowHeight + 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            DropShelfBubble(arrowX: arrowX)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            DropShelfBubble(arrowX: arrowX)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                    lineWidth: isTargeted ? 2 : 1
                )
        }
        .clipShape(DropShelfBubble(arrowX: arrowX))
        .contentShape(DropShelfBubble(arrowX: arrowX))
        .compositingGroup()
        .scaleEffect(
            isExpanded ? 1 : 0.28,
            anchor: UnitPoint(x: arrowX / MenuBarDropAnchor.shelfSize.width, y: 0)
        )
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

private struct DropShelfBubble: InsettableShape {
    var arrowX: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let arrowHeight = MenuBarDropAnchor.arrowHeight
        let arrowHalf: CGFloat = 9
        let bubble = CGRect(
            x: insetRect.minX,
            y: insetRect.minY + arrowHeight,
            width: insetRect.width,
            height: max(0, insetRect.height - arrowHeight)
        )
        let radius = max(4, 14 - insetAmount)
        let cx = min(max(bubble.minX + radius + arrowHalf, arrowX), bubble.maxX - radius - arrowHalf)
        var path = Path()
        path.move(to: CGPoint(x: bubble.minX + radius, y: bubble.minY))
        path.addLine(to: CGPoint(x: cx - arrowHalf, y: bubble.minY))
        path.addLine(to: CGPoint(x: cx, y: insetRect.minY))
        path.addLine(to: CGPoint(x: cx + arrowHalf, y: bubble.minY))
        path.addLine(to: CGPoint(x: bubble.maxX - radius, y: bubble.minY))
        path.addArc(
            center: CGPoint(x: bubble.maxX - radius, y: bubble.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bubble.maxX, y: bubble.maxY - radius))
        path.addArc(
            center: CGPoint(x: bubble.maxX - radius, y: bubble.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bubble.minX + radius, y: bubble.maxY))
        path.addArc(
            center: CGPoint(x: bubble.minX + radius, y: bubble.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bubble.minX, y: bubble.minY + radius))
        path.addArc(
            center: CGPoint(x: bubble.minX + radius, y: bubble.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> DropShelfBubble {
        DropShelfBubble(arrowX: arrowX, insetAmount: insetAmount + amount)
    }
}
