import SwiftUI
import Network
import AppKit
import os.log

struct NeumorphicButtonStyle: ButtonStyle {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 10
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 10))
    
    @State private var isHovering: Bool = false
    
    // Aesthetic Tokens
    let darkBase = Color(red: 0.15, green: 0.15, blue: 0.17)
    let lightShadow = Color(red: 0.2, green: 0.2, blue: 0.22)
    let darkShadow = Color(red: 0.1, green: 0.1, blue: 0.12)
    
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(darkBase)
            .clipShape(shape)
            // Press Effect: Inner Shadow or Scale Down
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1.0))
            .shadow(color: configuration.isPressed ? darkBase : lightShadow, radius: configuration.isPressed ? 0 : 5, x: configuration.isPressed ? 0 : -3, y: configuration.isPressed ? 0 : -3)
            .shadow(color: configuration.isPressed ? darkBase : darkShadow, radius: configuration.isPressed ? 0 : 5, x: configuration.isPressed ? 0 : 3, y: configuration.isPressed ? 0 : 3)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            // Hover logic
            .onHover { hovering in
                self.isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

// Wrapper to type-erase shapes
struct AnyShape: Shape {
    private let path: (CGRect) -> Path
    
    init<S: Shape>(_ wrapped: S) {
        self.path = { rect in
            let path = wrapped.path(in: rect)
            return path
        }
    }
    
    func path(in rect: CGRect) -> Path {
        return path(rect)
    }
}

struct ContentView: View {
    @StateObject var network = NetworkManager.shared
    @State private var pairingCode: String = ""
    @State private var showLogs: Bool = false
    @State private var showPairing: Bool = false
    
    // Neumorphic Colors
    let darkBase = Color(red: 0.15, green: 0.15, blue: 0.17)
    let lightShadow = Color(red: 0.2, green: 0.2, blue: 0.22)
    let darkShadow = Color(red: 0.1, green: 0.1, blue: 0.12)
    
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        ZStack {
            darkBase.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Header / Status
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(network.statusMessage)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: { showLogs = true }) {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .popover(isPresented: $showLogs, arrowEdge: .bottom) {
                        LogView()
                            .frame(width: 400, height: 300)
                    }
                }
                .padding(.horizontal)
                
                if network.connectionState == .disconnected || network.connectionState == .searching || network.connectionState == .connected {
                    if network.connectionState != .connected {
                        // DEVICE LIST OVERLAY
                        VStack(spacing: 10) {
                            Text("Select Android TV")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            if network.discoveredDevices.isEmpty {
                                Text("Searching...")
                                    .foregroundColor(.gray)
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
                        .background(RoundedRectangle(cornerRadius: 15).fill(darkBase).shadow(radius: 10))
                        .padding()
                        .zIndex(2)
                    }
                }
                
                Spacer()
                
                // D-Pad
                ZStack {
                    Circle()
                        .fill(darkBase)
                        .shadow(color: lightShadow, radius: 10, x: -5, y: -5)
                        .shadow(color: darkShadow, radius: 10, x: 5, y: 5)
                        .frame(width: 220, height: 220)
                    
                    VStack(spacing: 5) {
                        NavButton(icon: "chevron.up", action: { network.sendKey(.dpadUp) })
                        HStack(spacing: 5) {
                            NavButton(icon: "chevron.left", action: { network.sendKey(.dpadLeft) })
                            
                            Button(action: { network.sendKey(.dpadCenter) }) {
                                Text("OK")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(NeumorphicButtonStyle(width: 70, height: 70, shape: AnyShape(Circle())))
                            
                            NavButton(icon: "chevron.right", action: { network.sendKey(.dpadRight) })
                        }
                        NavButton(icon: "chevron.down", action: { network.sendKey(.dpadDown) })
                    }
                }
                
                Spacer()
                
                // Functional Buttons
                HStack(spacing: 25) {
                    FuncButton(icon: "house.fill", label: "Home", action: { network.sendKey(.home) })
                    FuncButton(icon: "arrow.uturn.backward", label: "Back", action: { network.sendKey(.back) })
                }
                
                HStack(spacing: 25) {
                    FuncButton(icon: "speaker.wave.1", label: "Vol -", action: { network.sendKey(.volumeDown) })
                    FuncButton(icon: "speaker.slash", label: "Mute", action: { network.sendKey(.mute) })
                    FuncButton(icon: "speaker.wave.3", label: "Vol +", action: { network.sendKey(.volumeUp) })
                }
                
                if network.isPairing {
                    VStack(spacing: 12) {
                        Text("Pairing Required")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        TextField("Enter 6-digit code", text: $pairingCode)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 200)
                            .focused($isFieldFocused)
                            .onChange(of: network.isPairing) { _, newValue in
                                if newValue { isFieldFocused = true }
                            }
                        
                        HStack(spacing: 15) {
                            Button("Cancel") {
                                network.isPairing = false
                                network.disconnect()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.3))
                            .cornerRadius(6)
                            
                            Button("Pair Device") {
                                network.sendPairingSecret(pairingCode)
                                pairingCode = ""
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.3))
                            .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 15).fill(darkBase).shadow(radius: 10))
                    .padding()
                    .zIndex(3)
                    .onAppear {
                        isFieldFocused = true
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            setupKeyboardHandling()
        }
    }
    
    var statusColor: Color {
        switch network.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .error(_): return .red
        default: return .gray
        }
    }
    
    func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // If we are currently pairing (typing code), don't intercept keys
            if network.isPairing {
                return event
            }
            
            switch event.keyCode {
            case 123: network.sendKey(.dpadLeft); return nil
            case 124: network.sendKey(.dpadRight); return nil
            case 125: network.sendKey(.dpadDown); return nil
            case 126: network.sendKey(.dpadUp); return nil
            case 36: network.sendKey(.dpadCenter); return nil // Enter
            case 53: network.sendKey(.back); return nil // Esc
            case 4: network.sendKey(.home); return nil // H
            case 103: network.sendKey(.volumeUp); return nil
            default: return event
            }
        }
    }
    
    func name(for endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return "Unknown Device"
    }
}

// Re-defining helpers because multi_replace was used
struct NavButton: View {
    let icon: String
    let action: () -> Void
    let darkBase = Color(red: 0.15, green: 0.15, blue: 0.17)
    let lightShadow = Color(red: 0.2, green: 0.2, blue: 0.22)
    let darkShadow = Color(red: 0.1, green: 0.1, blue: 0.12)
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
        }
        .buttonStyle(NeumorphicButtonStyle(width: 50, height: 50, cornerRadius: 10, shape: AnyShape(RoundedRectangle(cornerRadius: 10))))
    }
}

struct FuncButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    let darkBase = Color(red: 0.15, green: 0.15, blue: 0.17)
    let lightShadow = Color(red: 0.2, green: 0.2, blue: 0.22)
    let darkShadow = Color(red: 0.1, green: 0.1, blue: 0.12)
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.caption)
            }
            .foregroundColor(.white.opacity(0.9))
        }
        .buttonStyle(NeumorphicButtonStyle(width: 60, height: 60, cornerRadius: 12, shape: AnyShape(RoundedRectangle(cornerRadius: 12))))
    }
}

struct LogView: View {
    @ObservedObject var logger = Logger.shared
    var body: some View {
        VStack {
            HStack {
                Text("System Logs").font(.headline)
                Spacer()
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logger.exportLogs(), forType: .string)
                }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                Button("Clear") { logger.clear() }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }.padding()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(logger.logs) { log in
                        HStack(alignment: .top) {
                            Text(timeString(from: log.date)).font(.caption2).foregroundColor(.gray).frame(width: 60, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text("[\(log.category)]").font(.caption2).fontWeight(.bold).foregroundColor(.blue)
                                Text(log.message).font(.caption).foregroundColor(color(for: log.type))
                            }
                        }
                    }
                }.padding()
            }.background(Color.black.opacity(0.8)).cornerRadius(8)
        }.padding().background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }
    func timeString(from date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss.SSS"; return formatter.string(from: date)
    }
    func color(for type: OSLogType) -> Color {
        switch type {
        case .error, .fault: return .red
        case .debug: return .gray
        default: return .white
        }
    }
}
