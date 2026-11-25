import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum DownloadQR {
    static func image(for value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let quietZone = code.extent.insetBy(dx: -4, dy: -4)
        let padded = code.composited(over: CIImage(color: .white).cropped(to: quietZone))
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(scaled, from: scaled.extent)
    }
}
