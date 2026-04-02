import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = KaleidoscopeViewModel()
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingShareSheet = false
    @State private var showingExportOptions = false

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
                    onNewImage: {
                        showingImagePicker = true
                    },
                    onShare: {
                        showingShareSheet = true
                    },
                    onCamera: {
                        showingCamera = true
                    }
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

                // Canvas
                KaleidoscopeCanvasView(viewModel: viewModel)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                    .padding(.horizontal, 20)

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
                .padding(.top, 24)

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

                    Button(action: onShare) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                            Text("Share")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(hex: "b8a9f0"))
                        .foregroundColor(Color(hex: "111111"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                .frame(width: 75, alignment: .leading)

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
