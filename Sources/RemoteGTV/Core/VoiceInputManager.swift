import Foundation
import AVFoundation

class VoiceInputManager: NSObject, ObservableObject {
    static let shared = VoiceInputManager()
    
    private let engine = AVAudioEngine()
    private var isRecording = false
    private var dataHandler: ((Data) -> Void)?
    
    // Google TV requires 16000 Hz, 16-bit, Mono, PCM
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted { print("Microphone access granted") }
            }
        case .denied, .restricted:
            print("Microphone access denied")
        @unknown default:
            break
        }
    }
    
    func startRecording(handler: @escaping (Data) -> Void) {
        if isRecording { return }
        checkPermission()
        
        self.dataHandler = handler
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            print("[VoiceInput] Invalid sample rate")
            return
        }
        
        // Setup Converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[VoiceInput] Failed to create audio converter")
            return
        }
        
        // Install Tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            // Calculate required capacity for output buffer
            // Ratio = TargetRate / SourceRate
            let ratio = 16000.0 / inputFormat.sampleRate
            let capacity = UInt32(Double(buffer.frameLength) * ratio) + 100 // Safety margin
            
            if let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) {
                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputCallback)
                
                if status != .error, outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData {
                    let channelPointer = channelData[0]
                    let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
                    let data = Data(bytes: channelPointer, count: byteCount)
                    
                    handler(data)
                }
            }
        }
        
        do {
            try engine.start()
            isRecording = true
            print("[VoiceInput] Audio Engine Started")
        } catch {
            print("[VoiceInput] Start Error: \(error)")
        }
    }
    
    func stopRecording() {
        if !isRecording { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        print("[VoiceInput] Stopped")
    }
}
