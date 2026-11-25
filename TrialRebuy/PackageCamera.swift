import AVFoundation
import SwiftUI
import UIKit
import Vision

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let callback: (Data?) -> Void

    init(callback: @escaping (Data?) -> Void) { self.callback = callback }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        callback(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

final class PackageCamera: ObservableObject, @unchecked Sendable {
    enum Failure: Error { case unavailable, photo }
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "trialrebuy.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var delegate: PhotoDelegate?

    func setRunning(_ active: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                if !active {
                    if self.session.isRunning { self.session.stopRunning() }
                    continuation.resume(returning: false)
                    return
                }
                if !self.configured { self.configure() }
                if self.configured && !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.session.isRunning)
            }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            return
        }
        session.addOutput(output)
        configured = true
    }

    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.delegate == nil,
                      let connection = self.output.connection(with: .video), connection.isActive else {
                    continuation.resume(throwing: Failure.unavailable)
                    return
                }
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                let settings = AVCapturePhotoSettings()
                if self.output.supportedFlashModes.contains(.off) { settings.flashMode = .off }
                let delegate = PhotoDelegate { data in
                    self.queue.async {
                        self.delegate = nil
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: Failure.photo) }
                    }
                }
                self.delegate = delegate
                self.output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.videoLayer.videoGravity = .resizeAspectFill
        view.videoLayer.session = session
        if let connection = view.videoLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        if let connection = view.videoLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

enum PackageOCR {
    static func read(_ jpeg: Data) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let preferred = ["zh-Hans", "zh-Hant", "en-US"]
            if let supported = try? request.supportedRecognitionLanguages() {
                let available = preferred.filter { supported.contains($0) }
                if !available.isEmpty { request.recognitionLanguages = available }
            }
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(data: jpeg, orientation: .up)
            do {
                try handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return String(lines.joined(separator: "\n").prefix(4_000))
            } catch {
                return ""
            }
        }.value
    }
}
