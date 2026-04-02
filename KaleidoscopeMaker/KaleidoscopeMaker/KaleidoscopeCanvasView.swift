import SwiftUI

struct KaleidoscopeCanvasView: View {
    @ObservedObject var viewModel: KaleidoscopeViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = viewModel.renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    Color(hex: "16161a")
                }

                // Crosshair indicator
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Group {
                            Rectangle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: 1, height: 10)
                            Rectangle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: 10, height: 1)
                        }
                    )
                    .position(
                        x: geo.size.width * viewModel.centerX,
                        y: geo.size.height * viewModel.centerY
                    )
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = max(0, min(1, value.location.x / geo.size.width))
                        let y = max(0, min(1, value.location.y / geo.size.height))
                        viewModel.centerX = x
                        viewModel.centerY = y
                    }
            )
        }
    }
}
