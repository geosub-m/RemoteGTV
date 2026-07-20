import SwiftUI
import AppKit

struct PowerButton: View {
    @ObservedObject var network = NetworkManager.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            network.sendKey(.power)
        }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.95, green: 0.25, blue: 0.25),
                                Color(red: 0.75, green: 0.1, blue: 0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.red.opacity(isHovered ? 0.6 : 0.35), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
                
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Power ON / OFF")
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
