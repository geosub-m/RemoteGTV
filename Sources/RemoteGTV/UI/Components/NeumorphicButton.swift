import SwiftUI

struct NeumorphicButtonStyle: ButtonStyle {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = Theme.Layout.cornerRadius
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius))
    
    @State private var isHovering: Bool = false
    
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(Theme.Colors.darkBase)
            .clipShape(shape)
            // Press Effect: Inner Shadow or Scale Down
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1.0))
            .shadow(color: configuration.isPressed ? Theme.Colors.darkBase : Theme.Colors.lightShadow, radius: configuration.isPressed ? 0 : 5, x: configuration.isPressed ? 0 : -3, y: configuration.isPressed ? 0 : -3)
            .shadow(color: configuration.isPressed ? Theme.Colors.darkBase : Theme.Colors.darkShadow, radius: configuration.isPressed ? 0 : 5, x: configuration.isPressed ? 0 : 3, y: configuration.isPressed ? 0 : 3)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                self.isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

struct AnyShape: Shape, Sendable {
    private let _path: @Sendable (CGRect) -> Path
    
    init<S: Shape>(_ wrapped: S) {
        self._path = { rect in
            let path = wrapped.path(in: rect)
            return path
        }
    }
    
    func path(in rect: CGRect) -> Path {
        return _path(rect)
    }
}
