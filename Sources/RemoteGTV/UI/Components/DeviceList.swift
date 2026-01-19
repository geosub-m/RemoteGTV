import SwiftUI
import Network

struct DeviceListOverlay: View {
    @ObservedObject var network = NetworkManager.shared
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Select Android TV")
                .font(.headline)
                .foregroundColor(Theme.Colors.textPrimary)
            
            if network.discoveredDevices.isEmpty {
                Text("Searching...")
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(network.discoveredDevices, id: \.endpoint) { result in
                            Button(action: {
                                network.connect(to: result.endpoint)
                            }) {
                                HStack {
                                    Image(systemName: "tv")
                                    Text(name(for: result.endpoint))
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Theme.Colors.darkBase).shadow(radius: 10))
        .padding()
        .zIndex(2)
    }
    
    func name(for endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return "Unknown Device"
    }
}
