import AVFoundation
import AudioToolbox
import Combine
import CoreImage
import UIKit

struct Snapshot: Identifiable {
    let id = UUID()
    let image: UIImage
    let date: Date
}

/// จัดการกล้องและตรวจจับความเคลื่อนไหวด้วยเทคนิค frame differencing
/// (เทคนิคเดียวกับเวอร์ชันเว็บ: ย่อภาพเป็นตารางเล็ก ๆ แล้วเทียบความสว่างกับเฟรมก่อนหน้า)
final class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var motionDetected = false
    @Published var motionBox: CGRect?          // พิกัดกรอบแบบ normalized (0-1)
    @Published var snapshots: [Snapshot] = []
    @Published var permissionDenied = false

    // ตั้งค่าจากหน้าจอ
    @Published var sensitivity: Double = 25    // 5-80 สูง = ไวขึ้น
    @Published var soundAlertEnabled = true
    @Published var autoCaptureEnabled = true

    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "motioncam.session")
    private var position: AVCaptureDevice.Position = .back
    private var isConfigured = false

    // ตรวจจับบนตารางขนาดเล็กเพื่อประหยัด CPU และแบตเตอรี่
    private let gridW = 64
    private let gridH = 48
    private let pixelDiffThreshold = 40        // ความต่างของความสว่างต่อจุด (0-255)
    private var previousFrame: [Int]?
    private var lastCapture = Date.distantPast
    private let captureCooldown: TimeInterval = 3
    private var clearMotionWork: DispatchWorkItem?
    private let ciContext = CIContext()

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.permissionDenied = true }
                return
            }
            self.sessionQueue.async {
                self.configureSessionIfNeeded()
                self.previousFrame = nil
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                    // กันหน้าจอดับระหว่างเฝ้าดู
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.motionDetected = false
                self.motionBox = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    func switchCamera() {
        position = (position == .back) ? .front : .back
        sessionQueue.async {
            guard self.isConfigured else { return }
            self.configureInput()
            self.previousFrame = nil
        }
    }

    func clearSnapshots() {
        snapshots.removeAll()
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        configureInput()

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "motioncam.frames"))
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
        updateRotation()
    }

    private func configureInput() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        updateRotation()
    }

    private func updateRotation() {
        // หมุนเฟรมให้เป็นแนวตั้งเสมอ เพื่อให้ตำแหน่งกรอบตรงกับพรีวิว
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func reportMotion(box: CGRect, snapshot: UIImage?) {
        motionDetected = true
        motionBox = box

        if soundAlertEnabled {
            AudioServicesPlaySystemSound(SystemSoundID(1005))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        if let snapshot {
            snapshots.insert(Snapshot(image: snapshot, date: Date()), at: 0)
            // เก็บไว้แค่ 30 ภาพล่าสุด กันหน่วยความจำเต็ม
            if snapshots.count > 30 { snapshots.removeLast() }
        }

        clearMotionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.motionDetected = false
            self?.motionBox = nil
        }
        clearMotionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // อ่านเฉพาะ plane ความสว่าง (Y) ของภาพ YUV — ไม่ต้องแปลงสีเลย
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 0, height > 0 else { return }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // ย่อภาพเป็นตาราง gridW x gridH
        var frame = [Int](repeating: 0, count: gridW * gridH)
        for gy in 0..<gridH {
            let sy = gy * height / gridH
            for gx in 0..<gridW {
                let sx = gx * width / gridW
                frame[gy * gridW + gx] = Int(ptr[sy * stride + sx])
            }
        }

        defer { previousFrame = frame }
        guard let prev = previousFrame, prev.count == frame.count else { return }

        var changed = 0
        var minX = gridW, minY = gridH, maxX = -1, maxY = -1
        for gy in 0..<gridH {
            for gx in 0..<gridW {
                let i = gy * gridW + gx
                if abs(frame[i] - prev[i]) > pixelDiffThreshold {
                    changed += 1
                    minX = min(minX, gx); maxX = max(maxX, gx)
                    minY = min(minY, gy); maxY = max(maxY, gy)
                }
            }
        }

        let ratio = Double(changed) / Double(gridW * gridH)
        // ความไวสูง = เกณฑ์ต่ำ = ตรวจจับง่ายขึ้น (สูตรเดียวกับเวอร์ชันเว็บ)
        let threshold = (81 - sensitivity) / 1000
        guard ratio > threshold, maxX >= 0 else { return }

        let box = CGRect(x: CGFloat(minX) / CGFloat(gridW),
                         y: CGFloat(minY) / CGFloat(gridH),
                         width: CGFloat(maxX - minX + 1) / CGFloat(gridW),
                         height: CGFloat(maxY - minY + 1) / CGFloat(gridH))

        var snapshotImage: UIImage?
        if autoCaptureEnabled, Date().timeIntervalSince(lastCapture) > captureCooldown {
            lastCapture = Date()
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            if let cg = ciContext.createCGImage(ci, from: ci.extent) {
                snapshotImage = UIImage(cgImage: cg)
            }
        }

        DispatchQueue.main.async {
            self.reportMotion(box: box, snapshot: snapshotImage)
        }
    }
}
