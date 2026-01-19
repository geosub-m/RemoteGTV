import SwiftUI

struct PlaybackControls: View {
    @ObservedObject var network = NetworkManager.shared
    
    var body: some View {
        VStack(spacing: 25) {
            HStack(spacing: 25) {
                FuncButton(icon: "house.fill", label: "Home", action: { network.sendKey(.home) })
                FuncButton(icon: "arrow.uturn.backward", label: "Back", action: { network.sendKey(.back) })
            }
            
            HStack(spacing: 25) {
                FuncButton(icon: "speaker.wave.1", label: "Vol -", action: { network.sendKey(.volumeDown) })
                FuncButton(icon: "speaker.slash", label: "Mute", action: { network.sendKey(.mute) })
                FuncButton(icon: "speaker.wave.3", label: "Vol +", action: { network.sendKey(.volumeUp) })
            }
        }
    }
}

struct FuncButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.caption)
            }
            .foregroundColor(Theme.Colors.textPrimary.opacity(0.9))
        }
        .buttonStyle(NeumorphicButtonStyle(width: 60, height: 60, cornerRadius: 12, shape: AnyShape(RoundedRectangle(cornerRadius: 12))))
    }
}
