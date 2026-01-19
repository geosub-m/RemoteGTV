import SwiftUI

struct DirectionalPad: View {
    @ObservedObject var network = NetworkManager.shared
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.darkBase)
                .shadow(color: Theme.Colors.lightShadow, radius: 10, x: -5, y: -5)
                .shadow(color: Theme.Colors.darkShadow, radius: 10, x: 5, y: 5)
                .frame(width: 220, height: 220)
            
            VStack(spacing: 5) {
                NavButton(icon: "chevron.up", action: { network.sendKey(.dpadUp) })
                HStack(spacing: 5) {
                    NavButton(icon: "chevron.left", action: { network.sendKey(.dpadLeft) })
                    
                    Button(action: { network.sendKey(.dpadCenter) }) {
                        Text("OK")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .buttonStyle(NeumorphicButtonStyle(width: 70, height: 70, shape: AnyShape(Circle())))
                    
                    NavButton(icon: "chevron.right", action: { network.sendKey(.dpadRight) })
                }
                NavButton(icon: "chevron.down", action: { network.sendKey(.dpadDown) })
            }
        }
    }
}

struct NavButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.Colors.textPrimary.opacity(0.8))
        }
        .buttonStyle(NeumorphicButtonStyle(width: 50, height: 50, cornerRadius: 10, shape: AnyShape(RoundedRectangle(cornerRadius: 10))))
    }
}
