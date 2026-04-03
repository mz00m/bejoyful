import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = KaleidoscopeViewModel()
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingShareSheet = false
    @State private var showingAudioPicker = false
    @State private var showingExportPopover = false

    var body: some View {
        ZStack {
            Color(hex: "0c0c0f").ignoresSafeArea()

            if viewModel.sourceImage == nil {
                UploadView(
                    onPickPhoto: { showingImagePicker = true },
                    onTakePhoto: { showingCamera = true }
                )
            } else {
                EditorView(
                    viewModel: viewModel,
                    onNewImage: { showingImagePicker = true },
                    onShare: { showingShareSheet = true },
                    onCamera: { showingCamera = true },
                    showingAudioPicker: $showingAudioPicker,
                    showingExportPopover: $showingExportPopover
                )
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            PhotoPicker(image: $viewModel.sourceImage)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $viewModel.sourceImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = viewModel.renderedImage {
                ShareSheet(items: [image])
            }
        }
        .sheet(isPresented: $showingAudioPicker) {
            AudioFilePicker { url in
                viewModel.audioEngine.loadFile(url: url)
                if !viewModel.isAnimating {
                    viewModel.startAnimation()
                }
            }
        }
    }
}

// MARK: - Upload View

struct UploadView: View {
    let onPickPhoto: () -> Void
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("\u{25C6}")
                    .font(.title)
                    .foregroundColor(Color(hex: "b8a9f0"))
                Text("KALEIDOSCOPE")
                    .font(.system(size: 13, weight: .regular))
                    .tracking(4)
                    .foregroundColor(Color(hex: "7f7f86"))
            }

            VStack(spacing: 14) {
                Button(action: onTakePhoto) {
                    HStack(spacing: 10) {
                        Image(systemName: "camera")
                            .font(.system(size: 18))
                        Text("Take a Photo")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: 260)
                    .padding(.vertical, 16)
                    .background(Color(hex: "b8a9f0"))
                    .foregroundColor(Color(hex: "111111"))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onPickPhoto) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18))
                        Text("Choose from Library")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: 260)
                    .padding(.vertical, 16)
                    .background(Color(hex: "16161a"))
                    .foregroundColor(Color(hex: "e8e6e3"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "2a2a30"), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Spacer()

            Text("Upload a photo to create\na kaleidoscope for Instagram")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "7f7f86").opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)
        }
    }
}

// MARK: - Editor View

struct EditorView: View {
    @ObservedObject var viewModel: KaleidoscopeViewModel
    let onNewImage: () -> Void
    let onShare: () -> Void
    let onCamera: () -> Void
    @Binding var showingAudioPicker: Bool
    @Binding var showingExportPopover: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\u{25C6} KALEIDOSCOPE")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(3)
                        .foregroundColor(Color(hex: "7f7f86"))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

                // Canvas with export overlay
                ZStack {
                    KaleidoscopeCanvasView(viewModel: viewModel)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Export overlay
                    ExportOverlayView(viewModel: viewModel)
                }
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .padding(.horizontal, 20)

                // Transport bar + Share/Export
                HStack(spacing: 12) {
                    TransportBar(viewModel: viewModel)

                    Spacer()

                    // Context-aware share/export button
                    Button(action: {
                        if viewModel.isAnimating {
                            showingExportPopover = true
                        } else {
                            onShare()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isAnimating ? "record.circle" : "square.and.arrow.up")
                                .font(.system(size: 14))
                            Text(viewModel.isAnimating ? "Export" : "Share")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(hex: "b8a9f0"))
                        .foregroundColor(Color(hex: "111111"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .popover(isPresented: $showingExportPopover) {
                        if #available(iOS 16.4, *) {
                            ExportPopover(viewModel: viewModel, isPresented: $showingExportPopover)
                                .presentationCompactAdaptation(.popover)
                        } else {
                            ExportPopover(viewModel: viewModel, isPresented: $showingExportPopover)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Speed slider (progressive disclosure)
                if viewModel.isAnimating {
                    SliderRow(label: "SPEED", value: $viewModel.speed, range: 0.1...2.0)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeOut(duration: 0.3), value: viewModel.isAnimating)
                }

                // Sliders
                VStack(spacing: 16) {
                    SliderRow(label: "CENTER X", value: $viewModel.centerX, range: 0...1)
                    SliderRow(label: "CENTER Y", value: $viewModel.centerY, range: 0...1)
                    SliderRow(label: "SEGMENTS", value: $viewModel.segmentsFloat, range: 2...12) {
                        viewModel.segments = max(4, Int(viewModel.segmentsFloat) * 2)
                    }
                    SliderRow(label: "ZOOM", value: $viewModel.zoom, range: 0.3...2.5)
                    SliderRow(label: "ROTATION", value: $viewModel.rotation, range: 0...(.pi * 2))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Audio section
                AudioSection(viewModel: viewModel, showingAudioPicker: $showingAudioPicker)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Buttons
                HStack(spacing: 10) {
                    IconButton(icon: "shuffle", label: "Shuffle") {
                        viewModel.shuffle()
                    }

                    IconButton(icon: "camera", label: "Camera") {
                        onCamera()
                    }

                    IconButton(icon: "photo.on.rectangle", label: "Library") {
                        onNewImage()
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Hint
                Text("Drag on the image to move the center")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "7f7f86").opacity(0.5))
                    .padding(.bottom, 40)
            }
        }
        .disabled(viewModel.exportState != .idle && viewModel.exportState != .error(""))
    }
}

// MARK: - Transport Bar

struct TransportBar: View {
    @ObservedObject var viewModel: KaleidoscopeViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { viewModel.toggleAnimation() }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isAnimating ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                    Text(viewModel.isAnimating ? "Pause" : "Play")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 12)
                .background(Color(hex: "16161a"))
                .foregroundColor(Color(hex: "e8e6e3"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "2a2a30"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Mood picker
            Menu {
                ForEach(Mood.allCases) { mood in
                    Button(action: { viewModel.mood = mood }) {
                        HStack {
                            Text(mood.rawValue)
                            if viewModel.mood == mood {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.mood.rawValue)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(hex: "16161a"))
                .foregroundColor(Color(hex: "e8e6e3"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "2a2a30"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Audio Section

struct AudioSection: View {
    @ObservedObject var viewModel: KaleidoscopeViewModel
    @Binding var showingAudioPicker: Bool

    var body: some View {
        VStack(spacing: 10) {
            if let fileName = viewModel.audioEngine.fileName {
                // Audio connected state
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(Color(hex: "b8a9f0"))
                        .font(.system(size: 12))
                    Text(fileName)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "e8e6e3"))
                        .lineLimit(1)
                    Spacer()
                    Button(action: {
                        viewModel.audioEngine.stop()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "7f7f86"))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "16161a"))
                            .clipShape(Circle())
                    }
                }

                // Sensitivity slider
                SliderRow(label: "SENSITIVITY", value: Binding(
                    get: { Double(viewModel.audioEngine.sensitivity) },
                    set: { viewModel.audioEngine.sensitivity = Float($0) }
                ), range: 0...1)

                // Waveform
                WaveformView(magnitudes: viewModel.audioEngine.magnitudes)
                    .frame(height: 24)
            } else {
                // Audio upload zone
                Button(action: { showingAudioPicker = true }) {
                    VStack(spacing: 4) {
                        Text("Tap to add audio")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "7f7f86"))
                        Text("MP3, WAV, AAC — max 20MB, 60s")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "7f7f86").opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "16161a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundColor(Color(hex: "2a2a30"))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if let error = viewModel.audioEngine.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }

            // Mic button
            if viewModel.audioEngine.fileName != "Microphone" {
                Button(action: {
                    if viewModel.audioEngine.isActive && viewModel.audioEngine.fileName == "Microphone" {
                        viewModel.audioEngine.stop()
                    } else {
                        viewModel.audioEngine.startMic()
                        if !viewModel.isAnimating {
                            viewModel.startAnimation()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                        Text("Use Mic")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color(hex: "16161a"))
                    .foregroundColor(Color(hex: "7f7f86"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "2a2a30"), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let magnitudes: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<magnitudes.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: "b8a9f0").opacity(0.7))
                    .frame(height: max(1, CGFloat(magnitudes[i]) * 24))
            }
        }
    }
}

// MARK: - Export Popover

struct ExportPopover: View {
    @ObservedObject var viewModel: KaleidoscopeViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DURATION")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundColor(Color(hex: "7f7f86"))

            HStack(spacing: 6) {
                ForEach([3.0, 6.0, 15.0], id: \.self) { dur in
                    PillButton(
                        label: "\(Int(dur))s",
                        isActive: viewModel.exportDuration == dur
                    ) {
                        viewModel.exportDuration = dur
                    }
                }
            }

            Text("ASPECT")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundColor(Color(hex: "7f7f86"))
                .padding(.top, 4)

            HStack(spacing: 6) {
                ForEach(["1:1", "9:16", "16:9"], id: \.self) { aspect in
                    PillButton(
                        label: aspect,
                        isActive: viewModel.exportAspect == aspect
                    ) {
                        viewModel.exportAspect = aspect
                    }
                }
            }

            if viewModel.audioEngine.audioBuffer != nil {
                Toggle(isOn: $viewModel.includeAudio) {
                    Text("Include audio")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "e8e6e3"))
                }
                .tint(Color(hex: "b8a9f0"))
                .padding(.top, 4)
            }

            Button(action: {
                isPresented = false
                viewModel.startExport()
            }) {
                Text("Export")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "b8a9f0"))
                    .foregroundColor(Color(hex: "111111"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 240)
        .background(Color(hex: "16161a"))
    }
}

// MARK: - Pill Button

struct PillButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color(hex: "b8a9f0") : Color.clear)
                .foregroundColor(isActive ? Color(hex: "111111") : Color(hex: "7f7f86"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color(hex: "b8a9f0") : Color(hex: "2a2a30"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Export Overlay

struct ExportOverlayView: View {
    @ObservedObject var viewModel: KaleidoscopeViewModel
    @State private var showShareSheet = false

    var body: some View {
        Group {
            switch viewModel.exportState {
            case .idle:
                EmptyView()

            case .preparing:
                overlayBackground {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color(hex: "b8a9f0"))
                        Text("Preparing export...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "7f7f86"))
                    }
                }

            case .rendering(let frame, let total):
                overlayBackground {
                    VStack(spacing: 8) {
                        // Progress ring
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "2a2a30"), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: CGFloat(frame) / CGFloat(total))
                                .stroke(Color(hex: "b8a9f0"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 64, height: 64)

                        Text("\(Int((Double(frame) / Double(total)) * 100))%")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(hex: "e8e6e3"))

                        Text("\(frame) / \(total) frames")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "7f7f86"))

                        Button("Cancel") {
                            viewModel.cancelExport()
                        }
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "7f7f86"))
                        .padding(.top, 8)
                    }
                }

            case .encoding:
                overlayBackground {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color(hex: "b8a9f0"))
                        Text("Encoding video...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "7f7f86"))
                    }
                }

            case .preview(let url):
                overlayBackground {
                    VStack(spacing: 12) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onAppear {
                                let player = AVPlayer(url: url)
                                player.play()
                            }

                        Button(action: {
                            showShareSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 14))
                                Text("Save Video")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(hex: "b8a9f0"))
                            .foregroundColor(Color(hex: "111111"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button("New Export") {
                            viewModel.resetExport()
                        }
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "7f7f86"))

                        Text("Add audio in Instagram or TikTok.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "7f7f86").opacity(0.6))
                    }
                    .padding(12)
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [url])
                }

            case .error(let msg):
                overlayBackground {
                    VStack(spacing: 12) {
                        Text("Export failed")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "e8e6e3"))
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "7f7f86"))
                            .multilineTextAlignment(.center)
                        Button("OK") {
                            viewModel.resetExport()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "b8a9f0"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func overlayBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color(hex: "0c0c0f").opacity(0.85)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Audio File Picker

struct AudioFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.audio, .mp3, .wav, .aiff, UTType("public.aac-audio") ?? .audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            // Copy to temp directory for persistent access
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.copyItem(at: url, to: tempURL)
            onPick(tempURL)
        }
    }
}

// MARK: - Slider Row

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onChanged: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundColor(Color(hex: "7f7f86"))
                .frame(width: 85, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(Color(hex: "b8a9f0"))
                .onChange(of: value) { _ in
                    onChanged?()
                }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 60, height: 50)
            .background(Color(hex: "16161a"))
            .foregroundColor(Color(hex: "e8e6e3"))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "2a2a30"), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

#Preview {
    ContentView()
}
