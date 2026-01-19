import SwiftUI
import AppKit
import OSLog

struct ContentView: View {
    @StateObject var network = NetworkManager.shared
    @State private var showLogs: Bool = false
    
    var body: some View {
        ZStack {
            Theme.Colors.darkBase.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Header / Status
                HeaderView(showLogs: $showLogs, statusMessage: network.statusMessage, connectionState: network.connectionState)
                
                // Device List Overlay
                if network.connectionState == .disconnected || network.connectionState == .searching || network.connectionState == .connected {
                    if network.connectionState != .connected {
                        DeviceListOverlay()
                    }
                }
                
                // Voice Button
                MicrophoneButton()
                
                Spacer()
                
                // D-Pad
                DirectionalPad()
                
                Spacer()
                
                // Functional Buttons
                PlaybackControls()
                
                // Pairing Prompt
                if network.isPairing {
                   PairingView()
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
    
    func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if network.isPairing { return event }
            
            switch event.keyCode {
            case 123: network.sendKey(.dpadLeft); return nil
            case 124: network.sendKey(.dpadRight); return nil
            case 125: network.sendKey(.dpadDown); return nil
            case 126: network.sendKey(.dpadUp); return nil
            case 36: network.sendKey(.dpadCenter); return nil // Enter
            case 53: network.sendKey(.back); return nil // Esc
            case 51: network.sendKey(.back); return nil // Backspace
            case 4: network.sendKey(.home); return nil // H
            case 103: network.sendKey(.volumeUp); return nil
            default: return event
            }
        }
    }
}

struct HeaderView: View {
    @Binding var showLogs: Bool
    let statusMessage: String
    let connectionState: NetworkManager.ConnectionState
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusMessage)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Button(action: { showLogs = true }) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
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
    }
    
    var statusColor: Color {
        switch connectionState {
        case .connected: return Theme.Colors.statusConnected
        case .connecting: return Theme.Colors.statusConnecting
        case .error(_): return Theme.Colors.statusError
        default: return Theme.Colors.statusDisconnected
        }
    }
}

struct PairingView: View {
    @ObservedObject var network = NetworkManager.shared
    @State private var pairingCode: String = ""
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Pairing Required")
                .font(.headline)
                .foregroundColor(Theme.Colors.textPrimary)
            
            TextField("Enter 6-digit code", text: $pairingCode)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(10)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .foregroundColor(Theme.Colors.textPrimary)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 200)
                .focused($isFieldFocused)
                .onSubmit {
                     network.sendPairingSecret(pairingCode)
                     pairingCode = ""
                }
            
            HStack(spacing: 15) {
                Button("Cancel") {
                    network.isPairing = false
                    network.disconnect()
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.3))
                .cornerRadius(6)
                
                Button("Pair Device") {
                    network.sendPairingSecret(pairingCode)
                    pairingCode = ""
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.3))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Theme.Colors.darkBase).shadow(radius: 10))
        .padding()
        .zIndex(3)
        .onAppear {
            isFieldFocused = true
        }
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
                Button("Clear") { logger.clear() }
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
        }.padding().background(Theme.Colors.darkBase)
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

struct MicrophoneButton: View {
    @ObservedObject var network = NetworkManager.shared
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red : Color.blue)
                .shadow(color: isRecording ? Color.red.opacity(0.6) : Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)
            
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 64, height: 64)
        .scaleEffect(isRecording ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
        .gesture(
            DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isRecording {
                    isRecording = true
                    network.startVoiceSearch()
                }
            }
            .onEnded { _ in
                isRecording = false
                network.stopVoiceSearch()
            }
        )
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
