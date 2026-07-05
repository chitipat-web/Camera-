import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    private let bg = Color(red: 0.06, green: 0.09, blue: 0.16)
    private let panel = Color(red: 0.12, green: 0.16, blue: 0.23)

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                preview
                controls
                settings
                gallery
            }
            .padding(12)
        }
        .background(bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert("เข้าถึงกล้องไม่ได้", isPresented: $camera.permissionDenied) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text("กรุณาอนุญาตการใช้กล้องใน การตั้งค่า > MotionCam")
        }
    }

    private var header: some View {
        HStack {
            Text("📹 กล้องตรวจจับความเคลื่อนไหว")
                .font(.headline)
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Text(camera.motionDetected ? "🚨 พบความเคลื่อนไหว!"
             : camera.isRunning ? "👀 กำลังเฝ้าดู..."
             : "พร้อมใช้งาน")
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(camera.motionDetected ? Color.red
                        : camera.isRunning ? Color.green.opacity(0.6)
                        : Color.gray.opacity(0.4))
            .clipShape(Capsule())
    }

    private var preview: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
            GeometryReader { geo in
                if let box = camera.motionBox {
                    Rectangle()
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: box.width * geo.size.width,
                               height: box.height * geo.size.height)
                        .position(x: (box.midX) * geo.size.width,
                                  y: (box.midY) * geo.size.height)
                }
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(camera.motionDetected ? Color.red : Color.clear, lineWidth: 4)
        )
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if camera.isRunning {
                Button {
                    camera.stop()
                } label: {
                    Label("หยุด", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    camera.start()
                } label: {
                    Label("เริ่มตรวจจับ", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                camera.switchCamera()
            } label: {
                Label("สลับกล้อง", systemImage: "arrow.triangle.2.circlepath.camera")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .foregroundColor(.white)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ความไว (Sensitivity): \(Int(camera.sensitivity))")
                    .font(.subheadline)
                Slider(value: $camera.sensitivity, in: 5...80, step: 1)
            }
            Toggle("🔔 เสียงเตือนเมื่อพบความเคลื่อนไหว", isOn: $camera.soundAlertEnabled)
                .font(.subheadline)
            Toggle("📸 ถ่ายภาพอัตโนมัติเมื่อพบความเคลื่อนไหว", isOn: $camera.autoCaptureEnabled)
                .font(.subheadline)
        }
        .padding(14)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ภาพที่บันทึกไว้")
                    .font(.subheadline.bold())
                Spacer()
                if !camera.snapshots.isEmpty {
                    Button("ล้างทั้งหมด") { camera.clearSnapshots() }
                        .font(.caption)
                }
            }
            if camera.snapshots.isEmpty {
                Text("ยังไม่มีภาพ — ภาพจะถูกถ่ายอัตโนมัติเมื่อพบความเคลื่อนไหว")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(camera.snapshots) { snap in
                        VStack(spacing: 2) {
                            Image(uiImage: snap.image)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0)
                                .aspectRatio(3 / 4, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(snap.date, style: .time)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .contextMenu {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(snap.image, nil, nil, nil)
                            } label: {
                                Label("บันทึกลงแอพรูปภาพ", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
