import Foundation
import AVFoundation

class VoiceInputManager: NSObject, ObservableObject {
    static let shared = VoiceInputManager()
    
    private let engine = AVAudioEngine()
    private var isRecording = false
    private var dataHandler: ((Data) -> Void)?
    
    // Google TV requires 8000 Hz, 16-bit, Mono, PCM.
    // Audio is sent as Big Endian chunks.
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000.0, channels: 1, interleaved: true)!
    
    // Buffer to accumulate audio data before sending to avoid small packet overhead
    private var audioBuffer = Data()
    private let chunkSize = 3200 // ~200ms of audio (8000Hz * 2 bytes * 0.2s)
    
    // Debug logging
    // private var debugFileHandle: FileHandle?

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
        self.audioBuffer.removeAll() // Clear previous buffer
        
        // Setup debug file logging
        /*
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "VoiceDebug_\(dateFormatter.string(from: Date())).raw"
        let fileURL = URL(fileURLWithPath: "/Users/geosub/Projects/RemoteGTV/\(filename)")
        
        if FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) {
            do {
                self.debugFileHandle = try FileHandle(forWritingTo: fileURL)
                print("[VoiceInput] Logging audio to \(fileURL.path)")
            } catch {
                print("[VoiceInput] Failed to open debug file: \(error)")
            }
        }
        */
        
        // Ensure input node is ready
        let inputNode = engine.inputNode
        // Check input format
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
            let ratio = 8000.0 / inputFormat.sampleRate

            let capacity = UInt32(Double(buffer.frameLength) * ratio) + 100 // Safety margin
            
            if let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) {
                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputCallback)
                
                if status != .error, outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData {
                    let channelPointer = channelData[0]
                    let frameCount = Int(outputBuffer.frameLength)
                    
                    // Convert Native (Little) Endian to Big Endian manually
                    var bigEndianData = Data(count: frameCount * 2)
                    bigEndianData.withUnsafeMutableBytes { ptr in
                        let typedPtr = ptr.bindMemory(to: UInt16.self) // Use UInt16 for bit pattern
                        for i in 0..<frameCount {
                            // Read Int16 from pointer
                            let sample = channelPointer[i]
                            // Swap to Big Endian
                            let swapped = sample.bigEndian
                            // Store
                            typedPtr[i] = UInt16(bitPattern: swapped)
                        }
                    }
                    
                    // NEW: Buffer accumulation
                    self.audioBuffer.append(bigEndianData)
                    
                    // Send chunks of fixed size
                    while self.audioBuffer.count >= self.chunkSize {
                        let chunk = self.audioBuffer.prefix(self.chunkSize)
                        handler(chunk)
                        
                        // Log to file
                        // self.debugFileHandle?.write(chunk)
                        
                        self.audioBuffer.removeFirst(self.chunkSize)
                    }
                }
            }
        }
        
        do {
            try engine.start()
            isRecording = true
            print("[VoiceInput] Audio Engine Started (8kHz Big Endian)")
        } catch {
            print("[VoiceInput] Start Error: \(error)")
            // Cleanup on error
            // try? self.debugFileHandle?.close()
            // self.debugFileHandle = nil
        }
    }
    
    func stopRecording() {
        if !isRecording { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        // Close debug file
        // try? debugFileHandle?.close()
        // debugFileHandle = nil
        
        print("[VoiceInput] Stopped")
    }
}
