import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A faint film grain over a whole screen.
/// The noise is made once and tiled, so it costs one small image and no work per frame.
struct GrainOverlay: View {
    @Environment(\.palette) private var palette

    var body: some View {
        if let image = Self.noise {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
                .blendMode(palette.appearance == .dark ? .screen : .multiply)
                .opacity(palette.grainOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private static let noise: UIImage? = {
        let tile = CGRect(x: 0, y: 0, width: 256, height: 256)
        guard let random = CIFilter.randomGenerator().outputImage?.cropped(to: tile) else { return nil }
        let opaque = random.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let grey = opaque.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let cgImage = CIContext().createCGImage(grey, from: tile) else { return nil }
        return UIImage(cgImage: cgImage, scale: 2, orientation: .up)
    }()
}
