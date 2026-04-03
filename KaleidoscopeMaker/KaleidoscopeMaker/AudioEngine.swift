import AVFoundation
import Accelerate

class AudioEngine: ObservableObject {
    @Published var bass: Float = 0
    @Published var mid: Float = 0
    @Published var high: Float = 0
    @Published var isActive = false
    @Published var fileName: String?
    @Published var errorMessage: String?
    @Published var audioBuffer: AVAudioPCMBuffer?

    var sensitivity: Float = 0.5

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private let fftSize = 2048

    // Stored frequency magnitudes for waveform display
    @Published var magnitudes: [Float] = Array(repeating: 0, count: 32)

    func loadFile(url: URL) {
        stop()

        do {
            let file = try AVAudioFile(forReading: url)

            // Check duration
            let duration = Double(file.length) / file.processingFormat.sampleRate
            if duration > 60 {
                errorMessage = "Max 60 seconds. This file is \(Int(duration))s."
                return
            }

            // Check file size (~20MB)
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            if fileSize > 20 * 1024 * 1024 {
                errorMessage = "File too large (max 20MB)."
                return
            }

            audioFile = file
            fileName = url.lastPathComponent

            // Read entire buffer for offline export
            file.framePosition = 0
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            audioBuffer = buffer

            // Reset file position for playback
            file.framePosition = 0

            startPlayback()
        } catch {
            errorMessage = "Could not load audio file."
        }
    }

    func startMic() {
        stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            errorMessage = "Mic not available."
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            self.engine = engine
            fileName = "Microphone"
            isActive = true
        } catch {
            errorMessage = "Mic not available."
        }
    }

    func stop() {
        playerNode?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        playerNode = nil
        isActive = false
        fileName = nil
        audioFile = nil
        audioBuffer = nil
        errorMessage = nil
        bass = 0
        mid = 0
        high = 0
        magnitudes = Array(repeating: 0, count: 32)
    }

    private func startPlayback() {
        guard let audioFile = audioFile else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: audioFile.processingFormat)

        let mixerNode = engine.mainMixerNode
        let mixerFormat = mixerNode.outputFormat(forBus: 0)

        mixerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: mixerFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            try engine.start()
            self.engine = engine
            self.playerNode = player

            schedulePlayback()
            isActive = true
        } catch {
            errorMessage = "Could not play audio."
        }
    }

    private func schedulePlayback() {
        guard let player = playerNode, let file = audioFile else { return }
        file.framePosition = 0
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.schedulePlayback()
            }
        }
        player.play()
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Simple energy-based band analysis
        var bassEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0

        // Use vDSP for magnitude
        var magnitudesArray = [Float](repeating: 0, count: frameCount)
        vDSP_vabs(channelData, 1, &magnitudesArray, 1, vDSP_Length(frameCount))

        // Split into rough frequency bands based on position in buffer
        // This is approximate but sufficient for reactive visuals
        let third = frameCount / 3
        var sum: Float = 0

        vDSP_sve(magnitudesArray, 1, &sum, vDSP_Length(min(third, frameCount)))
        bassEnergy = sum / Float(third)

        if frameCount > third {
            sum = 0
            vDSP_sve(Array(magnitudesArray[third..<min(third*2, frameCount)]), 1, &sum, vDSP_Length(third))
            midEnergy = sum / Float(third)
        }

        if frameCount > third * 2 {
            sum = 0
            let remaining = frameCount - third * 2
            vDSP_sve(Array(magnitudesArray[(third*2)..<frameCount]), 1, &sum, vDSP_Length(remaining))
            highEnergy = sum / Float(remaining)
        }

        // Scale for visibility
        let scale: Float = 8.0

        // Compute waveform bars
        let barCount = 32
        let samplesPerBar = max(1, frameCount / barCount)
        var newMagnitudes = [Float](repeating: 0, count: barCount)
        for i in 0..<barCount {
            let start = i * samplesPerBar
            let end = min(start + samplesPerBar, frameCount)
            if start < end {
                var barSum: Float = 0
                vDSP_sve(Array(magnitudesArray[start..<end]), 1, &barSum, vDSP_Length(end - start))
                newMagnitudes[i] = min(1, (barSum / Float(end - start)) * scale)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.bass = min(1, bassEnergy * scale)
            self.mid = min(1, midEnergy * scale)
            self.high = min(1, highEnergy * scale)
            self.magnitudes = newMagnitudes
        }
    }

    // Offline audio analysis for video export
    func analyzeOffline(fps: Int, totalFrames: Int) -> [(bass: Float, mid: Float, high: Float)] {
        guard let buffer = audioBuffer, let channelData = buffer.floatChannelData?[0] else {
            return Array(repeating: (bass: Float(0), mid: Float(0), high: Float(0)), count: totalFrames)
        }

        let sampleRate = buffer.format.sampleRate
        let totalSamples = Int(buffer.frameLength)
        let windowSize = fftSize
        var snapshots: [(bass: Float, mid: Float, high: Float)] = []

        for frame in 0..<totalFrames {
            let t = Double(frame) / Double(fps)
            let sampleOffset = Int(t * sampleRate)

            if sampleOffset + windowSize > totalSamples {
                snapshots.append((bass: 0, mid: 0, high: 0))
                continue
            }

            var chunk = [Float](repeating: 0, count: windowSize)
            for j in 0..<windowSize {
                chunk[j] = abs(channelData[sampleOffset + j])
            }

            let third = windowSize / 3
            var bassSum: Float = 0, midSum: Float = 0, highSum: Float = 0
            vDSP_sve(chunk, 1, &bassSum, vDSP_Length(third))
            vDSP_sve(Array(chunk[third..<third*2]), 1, &midSum, vDSP_Length(third))
            vDSP_sve(Array(chunk[(third*2)..<windowSize]), 1, &highSum, vDSP_Length(windowSize - third*2))

            let scale: Float = 8.0
            snapshots.append((
                bass: min(1, (bassSum / Float(third)) * scale),
                mid: min(1, (midSum / Float(third)) * scale),
                high: min(1, (highSum / Float(windowSize - third*2)) * scale)
            ))
        }

        return snapshots
    }
}
