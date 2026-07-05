# 📱 MotionCam — แอพ iOS แบบ Native

แอพกล้องตรวจจับความเคลื่อนไหวสำหรับ iPhone เขียนด้วย Swift + SwiftUI + AVFoundation

## สิ่งที่ต้องมี

- Mac ที่ติดตั้ง **Xcode 16 ขึ้นไป**
- iPhone ที่ใช้ **iOS 17 ขึ้นไป**
- Apple Developer account (แบบฟรีก็ใช้ทดสอบบนเครื่องตัวเองได้ แบบเสียเงิน $99/ปี ถึงจะส่งขึ้น App Store ได้)

## วิธีติดตั้งลง iPhone

1. เปิด `ios/MotionCam.xcodeproj` ด้วย Xcode
2. คลิกที่โปรเจกต์ **MotionCam** → แท็บ **Signing & Capabilities**
   - เลือก **Team** เป็น Apple Developer account ของคุณ
   - ถ้า Bundle Identifier (`com.chitipat.motioncam`) ซ้ำกับคนอื่น ให้เปลี่ยนเป็นชื่อของตัวเอง เช่น `com.yourname.motioncam`
3. เสียบ iPhone เข้ากับ Mac แล้วเลือกเครื่องจากแถบด้านบน
4. บน iPhone: เปิด **Settings → Privacy & Security → Developer Mode** (iOS 16+) แล้วรีสตาร์ทเครื่อง
5. กด **Run (⌘R)** ใน Xcode
6. ครั้งแรกที่เปิดแอพ iPhone จะขึ้นว่าไม่เชื่อถือนักพัฒนา → ไปที่ **Settings → General → VPN & Device Management** แล้วกด Trust

> ⚠️ ถ้าใช้ Apple Developer แบบฟรี แอพจะหมดอายุใน 7 วัน ต้อง Run จาก Xcode ใหม่ (แบบเสียเงินอยู่ได้ 1 ปี)

## ฟีเจอร์

- 👀 ตรวจจับความเคลื่อนไหวเรียลไทม์ (frame differencing บน Y-plane ของภาพ YUV — เบามาก ไม่กินแบต)
- 🟥 กรอบสีแดงล้อมบริเวณที่ขยับ
- 🔔 เสียงเตือน + สั่นเมื่อพบความเคลื่อนไหว
- 📸 ถ่ายภาพอัตโนมัติ พร้อมแกลเลอรีในแอพ (กดค้างที่รูปเพื่อบันทึกลงแอพรูปภาพ)
- 🎚️ ปรับความไวได้
- 🔄 สลับกล้องหน้า/หลัง
- 📵 หน้าจอไม่ดับขณะเฝ้าดู

## โครงสร้างโค้ด

| ไฟล์ | หน้าที่ |
|---|---|
| `MotionCamApp.swift` | จุดเริ่มต้นของแอพ |
| `ContentView.swift` | หน้าจอหลักทั้งหมด (SwiftUI) |
| `CameraManager.swift` | จัดการกล้อง + อัลกอริทึมตรวจจับความเคลื่อนไหว |
| `CameraPreviewView.swift` | แสดงภาพสดจากกล้อง |

## ไอเดียต่อยอด

- อัดวิดีโอเมื่อพบความเคลื่อนไหว (`AVAssetWriter`)
- ส่ง Push Notification / แจ้งเตือนเข้า LINE
- แยกแยะคน/สัตว์/รถ ด้วย Vision framework (`VNDetectHumanRectanglesRequest`)
- ดูภาพสดจากมือถืออีกเครื่องผ่านอินเทอร์เน็ต
