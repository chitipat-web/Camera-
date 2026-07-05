// กล้องตรวจจับความเคลื่อนไหว — ใช้เทคนิค frame differencing
// เปรียบเทียบเฟรมปัจจุบันกับเฟรมก่อนหน้า ถ้าพิกเซลต่างกันเกินเกณฑ์ = มีความเคลื่อนไหว

const video = document.getElementById('video');
const overlay = document.getElementById('overlay');
const overlayCtx = overlay.getContext('2d');
const workCanvas = document.getElementById('work-canvas');
const workCtx = workCanvas.getContext('2d', { willReadFrequently: true });
const statusEl = document.getElementById('status');
const flashEl = document.getElementById('motion-flash');
const gallery = document.getElementById('gallery');

const btnStart = document.getElementById('btn-start');
const btnStop = document.getElementById('btn-stop');
const btnSwitch = document.getElementById('btn-switch');
const btnClear = document.getElementById('btn-clear');
const sensitivityInput = document.getElementById('sensitivity');
const sensValueEl = document.getElementById('sens-value');
const soundAlertInput = document.getElementById('sound-alert');
const autoCaptureInput = document.getElementById('auto-capture');

// ลดขนาดภาพที่ใช้วิเคราะห์เพื่อประหยัด CPU บนมือถือ
const DETECT_WIDTH = 96;
const DETECT_HEIGHT = 72;
const PIXEL_DIFF_THRESHOLD = 40;   // ค่าความต่างของความสว่างต่อพิกเซล (0-255)
const CAPTURE_COOLDOWN_MS = 3000;  // เว้นระยะระหว่างการถ่ายภาพอัตโนมัติ
const MOTION_HOLD_MS = 800;       // แสดงสถานะ "พบความเคลื่อนไหว" ค้างไว้นานแค่ไหน

let stream = null;
let prevFrame = null;
let running = false;
let facingMode = 'environment'; // เริ่มด้วยกล้องหลัง
let lastCaptureTime = 0;
let motionTimeout = null;
let audioCtx = null;

function setStatus(text, cls) {
  statusEl.textContent = text;
  statusEl.className = `status ${cls}`;
}

async function startCamera() {
  stopCamera();
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode, width: { ideal: 640 }, height: { ideal: 480 } },
      audio: false,
    });
  } catch (err) {
    setStatus('เข้าถึงกล้องไม่ได้', 'idle');
    alert('ไม่สามารถเข้าถึงกล้องได้: ' + err.message + '\n\nกรุณาอนุญาตการใช้กล้อง และเปิดผ่าน https:// หรือ localhost เท่านั้น');
    throw err;
  }
  video.srcObject = stream;
  await video.play();
  overlay.width = video.videoWidth;
  overlay.height = video.videoHeight;
  workCanvas.width = DETECT_WIDTH;
  workCanvas.height = DETECT_HEIGHT;
  prevFrame = null;
}

function stopCamera() {
  if (stream) {
    stream.getTracks().forEach((t) => t.stop());
    stream = null;
  }
  video.srcObject = null;
}

// แปลงเฟรมเป็นค่าความสว่าง (grayscale) ขนาดเล็ก
function grabFrame() {
  workCtx.drawImage(video, 0, 0, DETECT_WIDTH, DETECT_HEIGHT);
  const { data } = workCtx.getImageData(0, 0, DETECT_WIDTH, DETECT_HEIGHT);
  const gray = new Uint8ClampedArray(DETECT_WIDTH * DETECT_HEIGHT);
  for (let i = 0; i < gray.length; i++) {
    const o = i * 4;
    gray[i] = (data[o] * 0.299 + data[o + 1] * 0.587 + data[o + 2] * 0.114) | 0;
  }
  return gray;
}

// เปรียบเทียบสองเฟรม คืนค่า { ratio, boxes } — สัดส่วนพิกเซลที่เปลี่ยน และกรอบบริเวณที่ขยับ
function detectMotion(curr, prev) {
  let changed = 0;
  let minX = DETECT_WIDTH, minY = DETECT_HEIGHT, maxX = 0, maxY = 0;
  for (let y = 0; y < DETECT_HEIGHT; y++) {
    for (let x = 0; x < DETECT_WIDTH; x++) {
      const i = y * DETECT_WIDTH + x;
      if (Math.abs(curr[i] - prev[i]) > PIXEL_DIFF_THRESHOLD) {
        changed++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  const ratio = changed / (DETECT_WIDTH * DETECT_HEIGHT);
  const box = changed > 0 ? { minX, minY, maxX, maxY } : null;
  return { ratio, box };
}

function drawMotionBox(box) {
  overlayCtx.clearRect(0, 0, overlay.width, overlay.height);
  if (!box) return;
  const sx = overlay.width / DETECT_WIDTH;
  const sy = overlay.height / DETECT_HEIGHT;
  overlayCtx.strokeStyle = '#ef4444';
  overlayCtx.lineWidth = 3;
  overlayCtx.strokeRect(
    box.minX * sx,
    box.minY * sy,
    (box.maxX - box.minX + 1) * sx,
    (box.maxY - box.minY + 1) * sy
  );
}

function beep() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();
  osc.frequency.value = 880;
  gain.gain.setValueAtTime(0.3, audioCtx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.3);
  osc.connect(gain).connect(audioCtx.destination);
  osc.start();
  osc.stop(audioCtx.currentTime + 0.3);
}

function captureSnapshot() {
  const snap = document.createElement('canvas');
  snap.width = video.videoWidth;
  snap.height = video.videoHeight;
  snap.getContext('2d').drawImage(video, 0, 0);

  const fig = document.createElement('figure');
  const img = document.createElement('img');
  img.src = snap.toDataURL('image/jpeg', 0.8);
  const cap = document.createElement('figcaption');
  cap.textContent = new Date().toLocaleTimeString('th-TH');
  fig.append(img, cap);
  gallery.prepend(fig);

  // เก็บไว้แค่ 30 ภาพล่าสุด กันหน่วยความจำเต็ม
  while (gallery.children.length > 30) gallery.lastChild.remove();
}

function onMotionDetected(box) {
  setStatus('🚨 พบความเคลื่อนไหว!', 'motion');
  flashEl.classList.add('active');
  drawMotionBox(box);

  if (soundAlertInput.checked) beep();

  const now = Date.now();
  if (autoCaptureInput.checked && now - lastCaptureTime > CAPTURE_COOLDOWN_MS) {
    lastCaptureTime = now;
    captureSnapshot();
  }

  clearTimeout(motionTimeout);
  motionTimeout = setTimeout(() => {
    if (running) setStatus('👀 กำลังเฝ้าดู...', 'watching');
    flashEl.classList.remove('active');
    overlayCtx.clearRect(0, 0, overlay.width, overlay.height);
  }, MOTION_HOLD_MS);
}

function loop() {
  if (!running) return;
  if (video.readyState >= 2) {
    const curr = grabFrame();
    if (prevFrame) {
      const { ratio, box } = detectMotion(curr, prevFrame);
      // sensitivity สูง = เกณฑ์ต่ำ = ตรวจจับง่ายขึ้น
      const threshold = (81 - Number(sensitivityInput.value)) / 1000;
      if (ratio > threshold) onMotionDetected(box);
    }
    prevFrame = curr;
  }
  requestAnimationFrame(loop);
}

btnStart.addEventListener('click', async () => {
  await startCamera();
  running = true;
  btnStart.hidden = true;
  btnStop.hidden = false;
  setStatus('👀 กำลังเฝ้าดู...', 'watching');
  loop();
});

btnStop.addEventListener('click', () => {
  running = false;
  stopCamera();
  clearTimeout(motionTimeout);
  flashEl.classList.remove('active');
  overlayCtx.clearRect(0, 0, overlay.width, overlay.height);
  btnStart.hidden = false;
  btnStop.hidden = true;
  setStatus('พร้อมใช้งาน', 'idle');
});

btnSwitch.addEventListener('click', async () => {
  facingMode = facingMode === 'environment' ? 'user' : 'environment';
  if (running) {
    await startCamera();
  }
});

btnClear.addEventListener('click', () => {
  gallery.innerHTML = '';
});

sensitivityInput.addEventListener('input', () => {
  sensValueEl.textContent = sensitivityInput.value;
});

// ลงทะเบียน service worker เพื่อให้ติดตั้งเป็นแอพบนหน้าจอโฮมได้ (PWA)
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
