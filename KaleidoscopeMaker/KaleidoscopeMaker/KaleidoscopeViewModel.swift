import SwiftUI
import UIKit
import Combine

// MARK: - Mood Presets

struct MoodPreset {
    let rotationSpeed: Double    // degrees/second
    let zoomRange: (Double, Double)
    let zoomSpeed: Double        // oscillations/second
    let breathRange: (Double, Double)
    let breathSpeed: Double      // oscillations/second
}

enum Mood: String, CaseIterable, Identifiable {
    case meditative = "Meditative"
    case gentle = "Gentle"
    case dramatic = "Dramatic"
    case psychedelic = "Psychedelic"

    var id: String { rawValue }

    var preset: MoodPreset {
        switch self {
        case .meditative:
            return MoodPreset(rotationSpeed: 5, zoomRange: (0.95, 1.05), zoomSpeed: 0.15, breathRange: (0.98, 1.02), breathSpeed: 0.3)
        case .gentle:
            return MoodPreset(rotationSpeed: 10, zoomRange: (0.9, 1.1), zoomSpeed: 0.25, breathRange: (0.97, 1.03), breathSpeed: 0.5)
        case .dramatic:
            return MoodPreset(rotationSpeed: 20, zoomRange: (0.8, 1.2), zoomSpeed: 0.4, breathRange: (0.95, 1.05), breathSpeed: 0.8)
        case .psychedelic:
            return MoodPreset(rotationSpeed: 45, zoomRange: (0.7, 1.3), zoomSpeed: 0.6, breathRange: (0.93, 1.07), breathSpeed: 1.2)
        }
    }
}

// MARK: - Animation Parameters

struct AnimParams {
    var rotation: Double = 0
    var zoomMult: Double = 1.0
    var breathScale: Double = 1.0
}

// MARK: - Export State

enum ExportState: Equatable {
    case idle
    case preparing
    case rendering(frame: Int, total: Int)
    case encoding
    case preview(URL)
    case error(String)

    static func == (lhs: ExportState, rhs: ExportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.encoding, .encoding): return true
        case (.rendering(let a, let b), .rendering(let c, let d)): return a == c && b == d
        case (.preview(let a), .preview(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ViewModel

class KaleidoscopeViewModel: ObservableObject {
    @Published var sourceImage: UIImage? {
        didSet {
            if sourceImage != nil && oldValue !== sourceImage {
                centerX = 0.5
                centerY = 0.5
                zoom = 1.0
                rotation = 0
                segments = 12
                segmentsFloat = 6
            }
            renderKaleidoscope()
        }
    }

    @Published var centerX: Double = 0.5 { didSet { if !isAnimating { renderKaleidoscope() } } }
    @Published var centerY: Double = 0.5 { didSet { if !isAnimating { renderKaleidoscope() } } }
    @Published var segments: Int = 12 { didSet { if !isAnimating { renderKaleidoscope() } } }
    @Published var segmentsFloat: Double = 6
    @Published var zoom: Double = 1.0 { didSet { if !isAnimating { renderKaleidoscope() } } }
    @Published var rotation: Double = 0 { didSet { if !isAnimating { renderKaleidoscope() } } }
    @Published var renderedImage: UIImage?

    // Animation
    @Published var isAnimating = false
    @Published var mood: Mood = .gentle
    @Published var speed: Double = 1.0

    // Export
    @Published var exportState: ExportState = .idle
    @Published var exportDuration: Double = 6
    @Published var exportAspect: String = "1:1"
    @Published var includeAudio = true
    var exportCancelled = false

    // Audio
    @Published var audioEngine = AudioEngine()

    private let outputSize: CGFloat = 1080
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var animRotation: Double = 0
    private var animZoomPhase: Double = 0
    private var animBreathPhase: Double = 0
    private var onsetProgress: Double = 0
    private let onsetDuration: Double = 0.8

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-render when audio levels change (throttled)
        audioEngine.$bass
            .combineLatest(audioEngine.$mid, audioEngine.$high)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self = self, self.isAnimating else { return }
                // Animation loop handles rendering
            }
            .store(in: &cancellables)
    }

    // MARK: - Animation

    func toggleAnimation() {
        if isAnimating {
            stopAnimation()
        } else {
            startAnimation()
        }
    }

    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        lastFrameTime = 0
        onsetProgress = 0

        let link = CADisplayLink(target: self, selector: #selector(animationTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopAnimation() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func animationTick(_ link: CADisplayLink) {
        guard isAnimating else { return }

        let timestamp = link.timestamp
        if lastFrameTime == 0 { lastFrameTime = timestamp }
        let dt = min(timestamp - lastFrameTime, 0.1)
        lastFrameTime = timestamp

        let params = computeAnimParams(dt: dt)
        renderKaleidoscope(animParams: params)
    }

    private func computeAnimParams(dt: Double) -> AnimParams {
        let preset = mood.preset
        let speedMult = speed

        // Gentle onset
        if onsetProgress < 1 {
            onsetProgress = min(1, onsetProgress + dt / onsetDuration)
        }
        let p = onsetProgress
        let ease = p * p * (3 - 2 * p) // smoothstep

        let rotSpeed = preset.rotationSpeed * speedMult * ease
        animRotation += rotSpeed * dt

        animZoomPhase += preset.zoomSpeed * speedMult * ease * dt * .pi * 2
        animBreathPhase += preset.breathSpeed * speedMult * ease * dt * .pi * 2

        // Audio modulation
        let sens = audioEngine.sensitivity
        let audioBreathMod = Double(audioEngine.bass * sens) * 0.1
        let audioRotMod = Double(audioEngine.mid * sens) * 0.5
        let audioZoomMod = Double(audioEngine.high * sens) * 0.15

        let zoomMult = lerp(preset.zoomRange.0, preset.zoomRange.1,
                            (sin(animZoomPhase) + 1) / 2) + audioZoomMod
        let breathScale = lerp(preset.breathRange.0, preset.breathRange.1,
                               (sin(animBreathPhase) + 1) / 2) + audioBreathMod

        return AnimParams(
            rotation: (animRotation + audioRotMod) * .pi / 180,
            zoomMult: zoomMult,
            breathScale: breathScale
        )
    }

    // Compute animation state at a specific time for offline export
    func animParamsAtTime(_ t: Double, audioSnapshot: (bass: Float, mid: Float, high: Float)? = nil) -> AnimParams {
        let preset = mood.preset
        let speedMult = speed
        let ease: Double = t < onsetDuration ? {
            let p = t / onsetDuration
            return p * p * (3 - 2 * p)
        }() : 1

        let rotation = preset.rotationSpeed * speedMult * ease * t
        let zoomPhase = preset.zoomSpeed * speedMult * ease * t * .pi * 2
        let breathPhase = preset.breathSpeed * speedMult * ease * t * .pi * 2

        let sens = audioEngine.sensitivity
        var audioBreathMod = 0.0
        var audioRotMod = 0.0
        var audioZoomMod = 0.0

        if let snap = audioSnapshot {
            audioBreathMod = Double(snap.bass * sens) * 0.1
            audioRotMod = Double(snap.mid * sens) * 0.5
            audioZoomMod = Double(snap.high * sens) * 0.15
        }

        let zoomMult = lerp(preset.zoomRange.0, preset.zoomRange.1,
                            (sin(zoomPhase) + 1) / 2) + audioZoomMod
        let breathScale = lerp(preset.breathRange.0, preset.breathRange.1,
                               (sin(breathPhase) + 1) / 2) + audioBreathMod

        return AnimParams(
            rotation: (rotation + audioRotMod) * .pi / 180,
            zoomMult: zoomMult,
            breathScale: breathScale
        )
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    // MARK: - Shuffle

    func shuffle() {
        centerX = Double.random(in: 0.15...0.85)
        centerY = Double.random(in: 0.15...0.85)
        let segOptions = [6, 8, 10, 12, 16, 20, 24]
        segments = segOptions.randomElement() ?? 12
        segmentsFloat = Double(segments / 2)
        zoom = Double.random(in: 0.5...2.0)
        rotation = Double.random(in: 0...(Double.pi * 2))
    }

    // MARK: - Rendering

    func renderKaleidoscope(animParams: AnimParams? = nil) {
        guard let source = sourceImage else {
            renderedImage = nil
            return
        }

        renderedImage = renderImage(source: source, size: outputSize, animParams: animParams)
    }

    func renderImage(source: UIImage, size: CGFloat, animParams: AnimParams? = nil) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        return renderer.image { context in
            let cgCtx = context.cgContext
            let numSegments = segments
            let halfAngle = CGFloat.pi / CGFloat(numSegments)
            let cx = size / 2
            let cy = size / 2
            let radius = size * 0.75

            let effectiveZoom = zoom * (animParams?.zoomMult ?? 1.0)
            let effectiveRotation = rotation + (animParams?.rotation ?? 0)
            let breathScale = CGFloat(animParams?.breathScale ?? 1.0)

            let sourceSize = source.size
            let scale = (size / min(sourceSize.width, sourceSize.height)) * effectiveZoom
            let drawW = sourceSize.width * scale
            let drawH = sourceSize.height * scale
            let srcCx = sourceSize.width * centerX
            let srcCy = sourceSize.height * centerY
            let drawX = cx - srcCx * scale
            let drawY = cy - srcCy * scale

            let tmpRenderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let tmpImage = tmpRenderer.image { tmpCtx in
                let ctx = tmpCtx.cgContext
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: effectiveRotation)
                ctx.translateBy(x: -cx, y: -cy)
                source.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
            }

            guard let tmpCGImage = tmpImage.cgImage else { return }

            for i in 0..<numSegments {
                let angle = (2 * CGFloat.pi / CGFloat(numSegments)) * CGFloat(i)
                let mirrored = i % 2 == 1

                cgCtx.saveGState()
                cgCtx.translateBy(x: cx, y: cy)
                cgCtx.rotate(by: angle)

                if mirrored {
                    cgCtx.scaleBy(x: 1, y: -1)
                }

                // Apply breath scale
                if breathScale != 1.0 {
                    cgCtx.scaleBy(x: breathScale, y: breathScale)
                }

                cgCtx.beginPath()
                cgCtx.move(to: .zero)
                cgCtx.addLine(to: CGPoint(
                    x: radius * cos(-halfAngle),
                    y: radius * sin(-halfAngle)
                ))
                cgCtx.addArc(
                    center: .zero,
                    radius: radius,
                    startAngle: -halfAngle,
                    endAngle: halfAngle,
                    clockwise: false
                )
                cgCtx.closePath()
                cgCtx.clip()

                // Undo breath scale for image draw
                if breathScale != 1.0 {
                    cgCtx.scaleBy(x: 1 / breathScale, y: 1 / breathScale)
                }

                cgCtx.draw(tmpCGImage, in: CGRect(x: -cx, y: -cy, width: size, height: size))
                cgCtx.restoreGState()
            }

            // Vignette
            let colors = [
                UIColor.black.withAlphaComponent(0).cgColor,
                UIColor.black.withAlphaComponent(0.3).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.55, 1.0]) {
                cgCtx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: cx, y: cy),
                    startRadius: size * 0.3,
                    endCenter: CGPoint(x: cx, y: cy),
                    endRadius: size * 0.52,
                    options: .drawsAfterEndLocation
                )
            }
        }
    }

    // MARK: - Video Export

    func startExport() {
        guard let source = sourceImage else { return }
        exportCancelled = false
        exportState = .preparing

        let fps = 30
        let duration = exportDuration

        // Determine export dimensions
        let w: Int
        let h: Int
        switch exportAspect {
        case "9:16": w = 720; h = 1280
        case "16:9": w = 1280; h = 720
        default: w = 1080; h = 1080
        }

        let includeAudio = self.includeAudio && audioEngine.audioBuffer != nil
        let totalFrames = Int(duration) * fps

        // Analyze audio offline
        var audioSnapshots: [(bass: Float, mid: Float, high: Float)] = []
        if includeAudio {
            audioSnapshots = audioEngine.analyzeOffline(fps: fps, totalFrames: totalFrames)
        }

        Task {
            do {
                let url = try await VideoExporter.export(
                    config: VideoExporter.ExportConfig(
                        width: w, height: h, fps: fps,
                        duration: duration, includeAudio: includeAudio
                    ),
                    renderFrame: { [weak self] frame, time in
                        guard let self = self else { return nil }
                        let snapshot = frame < audioSnapshots.count ? audioSnapshots[frame] : nil
                        let params = self.animParamsAtTime(time, audioSnapshot: snapshot)

                        // Render at square size, crop for aspect
                        let squareSize = CGFloat(max(w, h))
                        let image = self.renderImage(source: source, size: squareSize, animParams: params)

                        if w == h { return image }

                        // Crop for non-square aspect
                        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
                        return renderer.image { ctx in
                            let sx = (squareSize - CGFloat(w)) / 2
                            let sy = (squareSize - CGFloat(h)) / 2
                            image.draw(at: CGPoint(x: -sx, y: -sy))
                        }
                    },
                    audioBuffer: includeAudio ? audioEngine.audioBuffer : nil,
                    progress: { [weak self] frame, total in
                        self?.exportState = .rendering(frame: frame, total: total)
                    },
                    cancelled: { [weak self] in
                        self?.exportCancelled ?? true
                    }
                )

                await MainActor.run {
                    exportState = .preview(url)
                }
            } catch VideoExporter.ExportError.cancelled {
                await MainActor.run {
                    exportState = .idle
                }
            } catch {
                await MainActor.run {
                    exportState = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelExport() {
        exportCancelled = true
        exportState = .idle
    }

    func resetExport() {
        exportState = .idle
    }
}
