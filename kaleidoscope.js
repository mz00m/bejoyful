// ============================================================================
// Kaleidoscope Maker — Animation, Audio Reactivity & Video Export
// ============================================================================

// --- DOM elements ---
const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');
const result = document.getElementById('result');
const canvas = document.getElementById('kaleidoscope');
const ctx = canvas.getContext('2d');
const crosshair = document.getElementById('crosshair');
const canvasWrap = document.getElementById('canvas-wrap');

const cxSlider = document.getElementById('cx');
const cySlider = document.getElementById('cy');
const segSlider = document.getElementById('segments');
const zoomSlider = document.getElementById('zoom');
const speedSlider = document.getElementById('speed');
const speedRow = document.getElementById('speed-row');
const sensitivitySlider = document.getElementById('sensitivity');

const btnPlay = document.getElementById('btn-play');
const moodSelect = document.getElementById('mood-select');

// --- Constants ---
const PREVIEW_SIZE = 500;
const EXPORT_SIZE = 1080;

// --- Canvas setup ---
canvas.width = PREVIEW_SIZE;
canvas.height = PREVIEW_SIZE;

const tmp = document.createElement('canvas');
const tmpCtx = tmp.getContext('2d');
tmp.width = PREVIEW_SIZE;
tmp.height = PREVIEW_SIZE;

// Separate tmp canvas for export (don't share with preview)
const exportTmp = document.createElement('canvas');
const exportTmpCtx = exportTmp.getContext('2d');

const exportCanvas = document.createElement('canvas');
const exportCtx = exportCanvas.getContext('2d');
exportCanvas.width = EXPORT_SIZE;
exportCanvas.height = EXPORT_SIZE;

let sourceImg = null;
let centerX = 0.5;
let centerY = 0.5;
let rafId = null;

// ============================================================================
// STEP 1: renderAt() with params override
// ============================================================================

function renderAt(targetCtx, size, params = {}) {
  if (!sourceImg) return;

  const numSegments = params.segments ?? parseInt(segSlider.value);
  const zoom = params.zoom ?? (parseInt(zoomSlider.value) / 100);
  const rotation = params.rotation ?? 0;
  const breathScale = params.breathScale ?? 1.0;
  const cx_override = params.centerX ?? centerX;
  const cy_override = params.centerY ?? centerY;

  targetCtx.clearRect(0, 0, size, size);

  const halfAngle = Math.PI / numSegments;
  const cx = size / 2;
  const cy = size / 2;
  const radius = size * 0.75;

  // Use export tmp canvas when rendering at export size, preview tmp otherwise
  const useTmp = size > PREVIEW_SIZE ? exportTmp : tmp;
  const useTmpCtx = size > PREVIEW_SIZE ? exportTmpCtx : tmpCtx;

  if (useTmp.width !== size) {
    useTmp.width = size;
    useTmp.height = size;
  } else {
    useTmpCtx.clearRect(0, 0, size, size);
  }

  const srcCx = sourceImg.width * cx_override;
  const srcCy = sourceImg.height * cy_override;
  const scale = (size / Math.min(sourceImg.width, sourceImg.height)) * zoom;
  const drawW = sourceImg.width * scale;
  const drawH = sourceImg.height * scale;
  const drawX = cx - srcCx * scale;
  const drawY = cy - srcCy * scale;

  useTmpCtx.drawImage(sourceImg, drawX, drawY, drawW, drawH);

  for (let i = 0; i < numSegments; i++) {
    const angle = (2 * Math.PI / numSegments) * i + rotation;
    const mirrored = i % 2 === 1;

    targetCtx.save();
    targetCtx.translate(cx, cy);
    targetCtx.rotate(angle);

    if (mirrored) {
      targetCtx.scale(1, -1);
    }

    // Apply breath scale
    if (breathScale !== 1.0) {
      targetCtx.scale(breathScale, breathScale);
    }

    targetCtx.beginPath();
    targetCtx.moveTo(0, 0);
    targetCtx.lineTo(radius * Math.cos(-halfAngle), radius * Math.sin(-halfAngle));
    targetCtx.arc(0, 0, radius, -halfAngle, halfAngle);
    targetCtx.closePath();
    targetCtx.clip();

    // Undo breath scale for the image draw so it maps correctly
    if (breathScale !== 1.0) {
      targetCtx.scale(1 / breathScale, 1 / breathScale);
    }

    targetCtx.drawImage(useTmp, -cx, -cy);
    targetCtx.restore();
  }

  // Vignette
  const grad = targetCtx.createRadialGradient(cx, cy, size * 0.3, cx, cy, size * 0.52);
  grad.addColorStop(0, 'rgba(0,0,0,0)');
  grad.addColorStop(1, 'rgba(0,0,0,0.25)');
  targetCtx.fillStyle = grad;
  targetCtx.fillRect(0, 0, size, size);

  if (!params._noUI) updateCrosshair();
}

function renderExport(params = {}) {
  renderAt(exportCtx, EXPORT_SIZE, { ...params, _noUI: true });
  return exportCanvas;
}

function scheduleRender() {
  if (anim.playing) return; // Animation loop handles rendering
  if (rafId) return;
  rafId = requestAnimationFrame(() => {
    rafId = null;
    renderAt(ctx, PREVIEW_SIZE);
  });
}

function updateCrosshair() {
  crosshair.style.left = (centerX * 100) + '%';
  crosshair.style.top = (centerY * 100) + '%';
}

// ============================================================================
// STEP 2: Animation Engine
// ============================================================================

function lerp(a, b, t) {
  return a + (b - a) * t;
}

const MOOD_PRESETS = {
  meditative: {
    rotationSpeed: 5,
    zoomRange: [0.95, 1.05],
    zoomSpeed: 0.15,
    breathRange: [0.98, 1.02],
    breathSpeed: 0.3,
  },
  gentle: {
    rotationSpeed: 10,
    zoomRange: [0.9, 1.1],
    zoomSpeed: 0.25,
    breathRange: [0.97, 1.03],
    breathSpeed: 0.5,
  },
  dramatic: {
    rotationSpeed: 20,
    zoomRange: [0.8, 1.2],
    zoomSpeed: 0.4,
    breathRange: [0.95, 1.05],
    breathSpeed: 0.8,
  },
  psychedelic: {
    rotationSpeed: 45,
    zoomRange: [0.7, 1.3],
    zoomSpeed: 0.6,
    breathRange: [0.93, 1.07],
    breathSpeed: 1.2,
  },
};

const anim = {
  playing: false,
  rotation: 0,
  zoomPhase: 0,
  breathPhase: 0,
  lastTime: 0,
  // Ease-in progress (0 = just started, 1 = full speed)
  onsetProgress: 0,
  // Current mood params (set from preset)
  rotationSpeed: 10,
  zoomRange: [0.9, 1.1],
  zoomSpeed: 0.25,
  breathRange: [0.97, 1.03],
  breathSpeed: 0.5,
};

const ONSET_DURATION = 0.8; // 800ms gentle onset

function applyMoodPreset(name) {
  const preset = MOOD_PRESETS[name];
  if (!preset) return;
  anim.rotationSpeed = preset.rotationSpeed;
  anim.zoomRange = preset.zoomRange;
  anim.zoomSpeed = preset.zoomSpeed;
  anim.breathRange = preset.breathRange;
  anim.breathSpeed = preset.breathSpeed;
}

function getAnimParams(dt) {
  const speedMult = parseInt(speedSlider.value) / 100;

  // Ease-in: ramp from 0 to 1 over ONSET_DURATION
  if (anim.onsetProgress < 1) {
    anim.onsetProgress = Math.min(1, anim.onsetProgress + dt / ONSET_DURATION);
  }
  const ease = anim.onsetProgress * anim.onsetProgress * (3 - 2 * anim.onsetProgress); // smoothstep

  const rotSpeed = anim.rotationSpeed * speedMult * ease;
  anim.rotation += rotSpeed * dt;

  anim.zoomPhase += anim.zoomSpeed * speedMult * ease * dt * Math.PI * 2;
  anim.breathPhase += anim.breathSpeed * speedMult * ease * dt * Math.PI * 2;

  // Audio modulation
  let audioBreathMod = 0;
  let audioRotMod = 0;
  let audioZoomMod = 0;
  if (audio.analyser && audio.dataArray) {
    audio.analyser.getByteFrequencyData(audio.dataArray);
    const sens = parseInt(sensitivitySlider.value) / 100;
    const bands = getAudioBands(audio.dataArray);
    audioBreathMod = bands.bass * sens * 0.1;   // bass -> breath
    audioRotMod = bands.mid * sens * 0.5;        // mid -> rotation
    audioZoomMod = bands.high * sens * 0.15;     // high -> zoom
  }

  const zoomMult = lerp(anim.zoomRange[0], anim.zoomRange[1],
    (Math.sin(anim.zoomPhase) + 1) / 2) + audioZoomMod;
  const breathScale = lerp(anim.breathRange[0], anim.breathRange[1],
    (Math.sin(anim.breathPhase) + 1) / 2) + audioBreathMod;

  return {
    rotation: (anim.rotation + audioRotMod) * Math.PI / 180,
    zoom: (parseInt(zoomSlider.value) / 100) * zoomMult,
    breathScale: breathScale,
  };
}

// Compute animation state at a specific time offset (for offline export)
function getAnimParamsAtTime(t, speedMult, audioSnapshots, frameIdx) {
  const preset = MOOD_PRESETS[moodSelect.value] || MOOD_PRESETS.gentle;
  const ease = t < ONSET_DURATION
    ? (() => { const p = t / ONSET_DURATION; return p * p * (3 - 2 * p); })()
    : 1;

  const rotSpeed = preset.rotationSpeed * speedMult * ease;
  const rotation = rotSpeed * t;

  const zoomPhase = preset.zoomSpeed * speedMult * ease * t * Math.PI * 2;
  const breathPhase = preset.breathSpeed * speedMult * ease * t * Math.PI * 2;

  let audioBreathMod = 0;
  let audioZoomMod = 0;
  let audioRotMod = 0;

  if (audioSnapshots && audioSnapshots[frameIdx]) {
    const snap = audioSnapshots[frameIdx];
    const sens = parseInt(sensitivitySlider.value) / 100;
    audioBreathMod = snap.bass * sens * 0.1;
    audioRotMod = snap.mid * sens * 0.5;
    audioZoomMod = snap.high * sens * 0.15;
  }

  const zoomMult = lerp(preset.zoomRange[0], preset.zoomRange[1],
    (Math.sin(zoomPhase) + 1) / 2) + audioZoomMod;
  const breathScale = lerp(preset.breathRange[0], preset.breathRange[1],
    (Math.sin(breathPhase) + 1) / 2) + audioBreathMod;

  return {
    rotation: (rotation + audioRotMod) * Math.PI / 180,
    zoom: (parseInt(zoomSlider.value) / 100) * zoomMult,
    breathScale: breathScale,
  };
}

function animate(timestamp) {
  if (!anim.playing) return;

  if (anim.lastTime === 0) anim.lastTime = timestamp;
  const dt = Math.min((timestamp - anim.lastTime) / 1000, 0.1); // cap at 100ms
  anim.lastTime = timestamp;

  const params = getAnimParams(dt);
  renderAt(ctx, PREVIEW_SIZE, params);

  // Update waveform visualization
  if (audio.analyser && audio.dataArray) {
    updateWaveformDisplay();
  }

  requestAnimationFrame(animate);
}

function startAnimation() {
  if (anim.playing) return;
  anim.playing = true;
  anim.lastTime = 0;
  anim.onsetProgress = 0;
  applyMoodPreset(moodSelect.value);

  btnPlay.innerHTML = '<svg viewBox="0 0 24 24"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg> Pause';
  btnPlay.setAttribute('aria-label', 'Pause animation');
  speedRow.classList.add('visible');

  requestAnimationFrame(animate);
}

function stopAnimation() {
  anim.playing = false;
  btnPlay.innerHTML = '<svg viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3"/></svg> Play';
  btnPlay.setAttribute('aria-label', 'Play animation');
  speedRow.classList.remove('visible');
}

btnPlay.addEventListener('click', () => {
  if (anim.playing) stopAnimation();
  else startAnimation();
});

moodSelect.addEventListener('change', () => {
  applyMoodPreset(moodSelect.value);
});

speedSlider.addEventListener('input', () => {
  speedSlider.setAttribute('aria-valuetext', speedSlider.value + '%');
});

// ============================================================================
// STEP 4: Audio Reactivity
// ============================================================================

const audio = {
  ctx: null,
  analyser: null,
  source: null,
  dataArray: null,
  audioBuffer: null,
  audioElement: null,
  micStream: null,
  fileName: null,
};

const audioDropZone = document.getElementById('audio-drop-zone');
const audioFileInput = document.getElementById('audio-file-input');
const audioInfo = document.getElementById('audio-info');
const audioFilename = document.getElementById('audio-filename');
const audioStatus = document.getElementById('audio-status');
const btnRemoveAudio = document.getElementById('btn-remove-audio');
const btnMic = document.getElementById('btn-mic');
const waveformEl = document.getElementById('waveform');
const includeAudioCheck = document.getElementById('include-audio-check');

// Create waveform bars
const WAVEFORM_BARS = 32;
for (let i = 0; i < WAVEFORM_BARS; i++) {
  const bar = document.createElement('div');
  bar.className = 'waveform-bar';
  bar.style.height = '1px';
  waveformEl.appendChild(bar);
}

function getAudioBands(dataArray) {
  if (!dataArray || dataArray.length === 0) return { bass: 0, mid: 0, high: 0 };

  let bass = 0, mid = 0, high = 0;
  let bassCount = 0, midCount = 0, highCount = 0;

  // Bins: fftSize=2048, sampleRate=44100 -> each bin ~21.5Hz
  // Bass: bins 1-12 (~20-250Hz)
  // Mid: bins 12-186 (~250-4000Hz)
  // High: bins 186+ (~4000Hz+)
  const binCount = dataArray.length;
  for (let i = 1; i < binCount; i++) {
    const val = dataArray[i] / 255;
    if (i <= 12) { bass += val; bassCount++; }
    else if (i <= 186) { mid += val; midCount++; }
    else { high += val; highCount++; }
  }

  return {
    bass: bassCount > 0 ? bass / bassCount : 0,
    mid: midCount > 0 ? mid / midCount : 0,
    high: highCount > 0 ? high / highCount : 0,
  };
}

function updateWaveformDisplay() {
  if (!audio.dataArray) return;
  const bars = waveformEl.children;
  const step = Math.floor(audio.dataArray.length / WAVEFORM_BARS);
  for (let i = 0; i < WAVEFORM_BARS; i++) {
    const val = audio.dataArray[i * step] / 255;
    bars[i].style.height = Math.max(1, val * 24) + 'px';
  }
}

function ensureAudioContext() {
  if (!audio.ctx) {
    audio.ctx = new (window.AudioContext || window.webkitAudioContext)();
  }
  if (audio.ctx.state === 'suspended') {
    audio.ctx.resume();
  }
  return audio.ctx;
}

function setupAnalyser() {
  const actx = ensureAudioContext();
  if (!audio.analyser) {
    audio.analyser = actx.createAnalyser();
    audio.analyser.fftSize = 2048;
    audio.dataArray = new Uint8Array(audio.analyser.frequencyBinCount);
  }
  return audio.analyser;
}

function disconnectAudioSource() {
  if (audio.source) {
    try { audio.source.disconnect(); } catch {}
    audio.source = null;
  }
  if (audio.audioElement) {
    audio.audioElement.pause();
    audio.audioElement.src = '';
    audio.audioElement = null;
  }
  if (audio.micStream) {
    audio.micStream.getTracks().forEach(t => t.stop());
    audio.micStream = null;
  }
}

function removeAudio() {
  disconnectAudioSource();
  audio.audioBuffer = null;
  audio.fileName = null;
  audio.dataArray = null;
  if (audio.analyser) {
    try { audio.analyser.disconnect(); } catch {}
    audio.analyser = null;
  }
  audioInfo.classList.remove('visible');
  audioDropZone.classList.remove('hidden');
  includeAudioCheck.classList.remove('visible');
  btnMic.classList.remove('active');
  // Reset waveform bars
  for (const bar of waveformEl.children) {
    bar.style.height = '1px';
  }
}

async function loadAudioFile(file) {
  if (!file.type.startsWith('audio/') && !file.name.match(/\.(mp3|wav|aac|m4a|ogg)$/i)) {
    showAudioError('Format not supported. Try MP3, WAV, or AAC.');
    return;
  }
  if (file.size > 20 * 1024 * 1024) {
    showAudioError('File too large (max 20MB).');
    return;
  }

  disconnectAudioSource();
  audioDropZone.classList.add('hidden');
  audioInfo.classList.add('visible');
  audioFilename.textContent = '\u266b ' + file.name;
  audioStatus.textContent = 'Decoding...';
  audio.fileName = file.name;

  try {
    const actx = ensureAudioContext();
    const arrayBuffer = await file.arrayBuffer();
    const audioBuffer = await actx.decodeAudioData(arrayBuffer);

    if (audioBuffer.duration > 60) {
      showAudioError('Max 60 seconds. This file is ' + Math.round(audioBuffer.duration) + 's.');
      removeAudio();
      return;
    }

    audio.audioBuffer = audioBuffer;

    // Create an audio element for playback
    const blob = new Blob([arrayBuffer], { type: file.type });
    const url = URL.createObjectURL(blob);
    audio.audioElement = new Audio(url);
    audio.audioElement.loop = true;

    // Connect to analyser
    const analyser = setupAnalyser();
    audio.source = actx.createMediaElementSource(audio.audioElement);
    audio.source.connect(analyser);
    analyser.connect(actx.destination);

    audio.audioElement.play();

    audioStatus.textContent = Math.round(audioBuffer.duration) + 's';
    includeAudioCheck.classList.add('visible');

    // Auto-start animation if not playing
    if (!anim.playing) startAnimation();
  } catch (err) {
    showAudioError('Could not decode audio file.');
    removeAudio();
  }
}

function showAudioError(msg) {
  audioInfo.classList.add('visible');
  audioDropZone.classList.add('hidden');
  audioFilename.textContent = '';
  audioStatus.textContent = msg;
  audioStatus.style.color = '#f08080';
  setTimeout(() => {
    audioStatus.style.color = '';
    removeAudio();
  }, 3000);
}

// Audio file upload
audioDropZone.addEventListener('click', () => audioFileInput.click());
audioDropZone.addEventListener('dragover', e => {
  e.preventDefault();
  audioDropZone.classList.add('drag-over');
});
audioDropZone.addEventListener('dragleave', () => {
  audioDropZone.classList.remove('drag-over');
});
audioDropZone.addEventListener('drop', e => {
  e.preventDefault();
  audioDropZone.classList.remove('drag-over');
  if (e.dataTransfer.files.length) loadAudioFile(e.dataTransfer.files[0]);
});
audioFileInput.addEventListener('change', () => {
  if (audioFileInput.files.length) loadAudioFile(audioFileInput.files[0]);
});
btnRemoveAudio.addEventListener('click', removeAudio);

// Mic input
btnMic.addEventListener('click', async () => {
  if (audio.micStream) {
    // Stop mic
    removeAudio();
    return;
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    disconnectAudioSource();
    audio.micStream = stream;

    const actx = ensureAudioContext();
    const analyser = setupAnalyser();
    audio.source = actx.createMediaStreamSource(stream);
    audio.source.connect(analyser);
    // Don't connect to destination (would cause echo)

    audioDropZone.classList.add('hidden');
    audioInfo.classList.add('visible');
    audioFilename.textContent = 'Microphone';
    audioStatus.textContent = 'Listening...';
    btnMic.classList.add('active');
    includeAudioCheck.classList.remove('visible');

    if (!anim.playing) startAnimation();
  } catch {
    btnMic.style.display = 'none';
    const label = document.createElement('span');
    label.className = 'audio-status';
    label.textContent = 'Mic not available';
    btnMic.parentElement.appendChild(label);
  }
});

// ============================================================================
// STEP 3: Video Export
// ============================================================================

const exportOverlay = document.getElementById('export-overlay');
const exportPercent = exportOverlay.querySelector('.export-percent');
const exportFrames = exportOverlay.querySelector('.export-frames');
const exportEta = exportOverlay.querySelector('.export-eta');
const exportStatus = exportOverlay.querySelector('.export-status');
const ringFg = exportOverlay.querySelector('.ring-fg');
const btnCancelExport = document.getElementById('btn-cancel-export');
const btnDownloadVideo = document.getElementById('btn-download-video');
const btnNewExport = document.getElementById('btn-new-export');
const exportPreview = document.getElementById('export-preview');
const exportPopover = document.getElementById('export-popover');
const btnStartExport = document.getElementById('btn-start-export');
const btnDownload = document.getElementById('btn-download');

let exportCancelled = false;
let ffmpegInstance = null;
let lastExportBlob = null;

// Pill toggle behavior
document.querySelectorAll('.pill-group').forEach(group => {
  group.addEventListener('click', e => {
    const pill = e.target.closest('.pill');
    if (!pill) return;
    group.querySelectorAll('.pill').forEach(p => p.classList.remove('active'));
    pill.classList.add('active');
  });
});

// Context-aware download
btnDownload.addEventListener('click', (e) => {
  if (anim.playing) {
    // Show export popover
    e.stopPropagation();
    exportPopover.classList.toggle('visible');
  } else {
    // Static PNG download
    const exp = renderExport();
    const link = document.createElement('a');
    link.download = 'kaleidoscope-1080x1080.png';
    link.href = exp.toDataURL('image/png');
    link.click();
  }
});

// Close popover on outside click
document.addEventListener('click', (e) => {
  if (!e.target.closest('.download-wrap')) {
    exportPopover.classList.remove('visible');
  }
});

// Start export
btnStartExport.addEventListener('click', () => {
  exportPopover.classList.remove('visible');

  const durationPill = document.querySelector('#duration-pills .pill.active');
  const aspectPill = document.querySelector('#aspect-pills .pill.active');
  const duration = parseInt(durationPill.dataset.val);
  const aspect = aspectPill.dataset.val;
  const includeAudio = document.getElementById('include-audio').checked && audio.audioBuffer;

  startExport(duration, aspect, includeAudio);
});

btnCancelExport.addEventListener('click', () => {
  exportCancelled = true;
});

btnNewExport.addEventListener('click', () => {
  exportOverlay.classList.remove('visible', 'preview-mode');
  exportPreview.src = '';
  if (lastExportBlob) {
    URL.revokeObjectURL(lastExportBlob);
    lastExportBlob = null;
  }
  enableControls(true);
});

btnDownloadVideo.addEventListener('click', () => {
  if (!lastExportBlob) return;
  const link = document.createElement('a');
  link.download = 'kaleidoscope.mp4';
  link.href = lastExportBlob;
  link.click();
});

function enableControls(enabled) {
  const btns = document.querySelectorAll('.controls button, .transport button, .sliders input, #mood-select');
  btns.forEach(el => el.disabled = !enabled);
}

function updateExportProgress(frame, total, startTime) {
  const pct = Math.round((frame / total) * 100);
  const elapsed = (performance.now() - startTime) / 1000;
  const rate = frame / elapsed;
  const remaining = rate > 0 ? Math.round((total - frame) / rate) : 0;

  exportPercent.textContent = pct + '%';
  exportFrames.textContent = frame + ' / ' + total + ' frames';
  exportEta.textContent = remaining > 0 ? '~' + remaining + 's remaining' : '';

  const circumference = 2 * Math.PI * 28;
  ringFg.style.strokeDashoffset = circumference * (1 - frame / total);
}

async function analyzeAudioOffline(audioBuffer, fps, totalFrames) {
  try {
    const offlineCtx = new OfflineAudioContext(
      audioBuffer.numberOfChannels,
      audioBuffer.length,
      audioBuffer.sampleRate
    );

    const source = offlineCtx.createBufferSource();
    source.buffer = audioBuffer;

    const analyser = offlineCtx.createAnalyser();
    analyser.fftSize = 2048;
    source.connect(analyser);
    analyser.connect(offlineCtx.destination);
    source.start(0);

    // Try suspend/resume approach
    const snapshots = [];
    const frameDuration = 1 / fps;

    for (let i = 0; i < totalFrames; i++) {
      const t = i * frameDuration;
      if (t < audioBuffer.duration) {
        try {
          offlineCtx.suspend(t).then(() => {
            const data = new Uint8Array(analyser.frequencyBinCount);
            analyser.getByteFrequencyData(data);
            snapshots.push(getAudioBands(data));
            offlineCtx.resume();
          });
        } catch {
          break;
        }
      } else {
        snapshots.push({ bass: 0, mid: 0, high: 0 });
      }
    }

    await offlineCtx.startRendering();

    // Check if we got valid data
    if (snapshots.length > 0 && snapshots.some(s => s.bass > 0 || s.mid > 0 || s.high > 0)) {
      return snapshots;
    }

    // Fallback: manual FFT from raw samples
    return manualFFTAnalysis(audioBuffer, fps, totalFrames);
  } catch {
    return manualFFTAnalysis(audioBuffer, fps, totalFrames);
  }
}

function manualFFTAnalysis(audioBuffer, fps, totalFrames) {
  const channelData = audioBuffer.getChannelData(0);
  const sampleRate = audioBuffer.sampleRate;
  const windowSize = 2048;
  const snapshots = [];

  for (let i = 0; i < totalFrames; i++) {
    const t = i / fps;
    const sampleOffset = Math.floor(t * sampleRate);

    if (sampleOffset + windowSize > channelData.length) {
      snapshots.push({ bass: 0, mid: 0, high: 0 });
      continue;
    }

    // Simple energy-based analysis (not full FFT, but fast and sufficient)
    let bass = 0, mid = 0, high = 0;
    const chunk = channelData.subarray(sampleOffset, sampleOffset + windowSize);

    // Low-pass approximation: average of absolute values in overlapping windows
    for (let j = 0; j < windowSize; j++) {
      const val = Math.abs(chunk[j]);
      // Rough frequency band estimation by sample position patterns
      if (j % 8 < 2) bass += val;
      if (j % 8 >= 2 && j % 8 < 6) mid += val;
      if (j % 8 >= 6) high += val;
    }

    const norm = windowSize / 8;
    snapshots.push({
      bass: Math.min(1, (bass / norm) * 4),
      mid: Math.min(1, (mid / norm) * 4),
      high: Math.min(1, (high / norm) * 4),
    });
  }

  return snapshots;
}

async function startExport(duration, aspect, includeAudio) {
  exportCancelled = false;
  enableControls(false);
  exportOverlay.classList.add('visible');
  exportOverlay.classList.remove('preview-mode');

  const fps = 30;
  const totalFrames = duration * fps;
  const speedMult = parseInt(speedSlider.value) / 100;
  const isMobile = navigator.maxTouchPoints > 0 && window.innerWidth < 768;

  // Determine export size based on aspect ratio
  let exportW, exportH;
  if (aspect === '9:16') {
    exportW = isMobile ? 720 : 720;
    exportH = isMobile ? 1280 : 1280;
  } else if (aspect === '16:9') {
    exportW = isMobile ? 1280 : 1280;
    exportH = isMobile ? 720 : 720;
  } else {
    exportW = isMobile ? 720 : 1080;
    exportH = isMobile ? 720 : 1080;
  }

  // Mobile: cap duration at 6s
  const effectiveDuration = isMobile ? Math.min(duration, 6) : duration;
  const effectiveFrames = effectiveDuration * fps;

  // Analyze audio offline if needed
  let audioSnapshots = null;
  if (includeAudio && audio.audioBuffer) {
    exportStatus.textContent = 'Analyzing audio...';
    audioSnapshots = await analyzeAudioOffline(audio.audioBuffer, fps, effectiveFrames);
  }

  // Try desktop path: ffmpeg.wasm (offline rendering)
  // Try mobile path: MediaRecorder (real-time capture)
  const useMediaRecorder = isMobile || typeof SharedArrayBuffer === 'undefined';

  if (useMediaRecorder) {
    await exportWithMediaRecorder(effectiveDuration, exportW, exportH, effectiveFrames, speedMult, audioSnapshots);
  } else {
    await exportWithFFmpeg(effectiveDuration, exportW, exportH, effectiveFrames, fps, speedMult, audioSnapshots, includeAudio);
  }
}

async function exportWithMediaRecorder(duration, w, h, totalFrames, speedMult, audioSnapshots) {
  exportStatus.textContent = 'Recording...';

  // Create a temp canvas at export size
  const recCanvas = document.createElement('canvas');
  recCanvas.width = w;
  recCanvas.height = h;
  const recCtx = recCanvas.getContext('2d');

  const stream = recCanvas.captureStream(30);
  const recorder = new MediaRecorder(stream, {
    mimeType: MediaRecorder.isTypeSupported('video/mp4') ? 'video/mp4'
      : MediaRecorder.isTypeSupported('video/webm;codecs=vp9') ? 'video/webm;codecs=vp9'
      : 'video/webm',
  });

  const chunks = [];
  recorder.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };

  const startTime = performance.now();

  return new Promise((resolve) => {
    recorder.onstop = () => {
      const mimeType = recorder.mimeType;
      const ext = mimeType.includes('mp4') ? 'mp4' : 'webm';
      const blob = new Blob(chunks, { type: mimeType });
      showExportPreview(blob, ext);
      resolve();
    };

    recorder.start();
    let frame = 0;
    const fps = 30;

    function renderFrame() {
      if (exportCancelled || frame >= totalFrames) {
        recorder.stop();
        if (exportCancelled) {
          exportOverlay.classList.remove('visible');
          enableControls(true);
        }
        return;
      }

      const t = frame / fps;
      const params = getAnimParamsAtTime(t, speedMult, audioSnapshots, frame);

      // Render at square size, then crop for aspect ratio
      const squareSize = Math.max(w, h);
      const tempCanvas = document.createElement('canvas');
      tempCanvas.width = squareSize;
      tempCanvas.height = squareSize;
      const tempCtx = tempCanvas.getContext('2d');

      renderAt(tempCtx, squareSize, { ...params, _noUI: true });

      // Crop center
      const sx = (squareSize - w) / 2;
      const sy = (squareSize - h) / 2;
      recCtx.drawImage(tempCanvas, sx, sy, w, h, 0, 0, w, h);

      updateExportProgress(frame, totalFrames, startTime);
      frame++;
      requestAnimationFrame(renderFrame);
    }

    renderFrame();
  });
}

async function exportWithFFmpeg(duration, w, h, totalFrames, fps, speedMult, audioSnapshots, includeAudio) {
  exportStatus.textContent = 'Loading encoder...';

  try {
    if (!ffmpegInstance) {
      const { FFmpeg } = await import('https://unpkg.com/@ffmpeg/ffmpeg@0.12.10/dist/esm/index.js');
      const { toBlobURL } = await import('https://unpkg.com/@ffmpeg/util@0.12.1/dist/esm/index.js');

      ffmpegInstance = new FFmpeg();
      const baseURL = 'https://unpkg.com/@ffmpeg/core@0.12.6/dist/esm';
      await ffmpegInstance.load({
        coreURL: await toBlobURL(baseURL + '/ffmpeg-core.js', 'text/javascript'),
        wasmURL: await toBlobURL(baseURL + '/ffmpeg-core.wasm', 'application/wasm'),
      });
    }

    const ffmpeg = ffmpegInstance;
    const startTime = performance.now();
    exportStatus.textContent = 'Rendering frames...';

    // Render frames
    const squareSize = Math.max(w, h);
    const frameCanvas = document.createElement('canvas');
    frameCanvas.width = w;
    frameCanvas.height = h;
    const frameCtx = frameCanvas.getContext('2d');

    const renderCanvas = document.createElement('canvas');
    renderCanvas.width = squareSize;
    renderCanvas.height = squareSize;
    const renderCtx = renderCanvas.getContext('2d');

    for (let i = 0; i < totalFrames; i++) {
      if (exportCancelled) {
        exportOverlay.classList.remove('visible');
        enableControls(true);
        return;
      }

      const t = i / fps;
      const params = getAnimParamsAtTime(t, speedMult, audioSnapshots, i);
      renderAt(renderCtx, squareSize, { ...params, _noUI: true });

      // Crop for aspect ratio
      const sx = (squareSize - w) / 2;
      const sy = (squareSize - h) / 2;
      frameCtx.drawImage(renderCanvas, sx, sy, w, h, 0, 0, w, h);

      const blob = await new Promise(resolve => frameCanvas.toBlob(resolve, 'image/png'));
      const data = new Uint8Array(await blob.arrayBuffer());
      const name = 'frame' + String(i).padStart(5, '0') + '.png';
      await ffmpeg.writeFile(name, data);

      updateExportProgress(i + 1, totalFrames, startTime);

      // Yield to main thread
      if (i % 5 === 0) await new Promise(r => setTimeout(r, 0));
    }

    exportStatus.textContent = 'Encoding video...';

    // Write audio if needed
    if (includeAudio && audio.audioBuffer) {
      const audioBlob = await audioBufferToWav(audio.audioBuffer, duration);
      const audioData = new Uint8Array(await audioBlob.arrayBuffer());
      await ffmpeg.writeFile('audio.wav', audioData);

      await ffmpeg.exec([
        '-framerate', String(fps),
        '-i', 'frame%05d.png',
        '-i', 'audio.wav',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-shortest',
        '-y', 'output.mp4'
      ]);
    } else {
      await ffmpeg.exec([
        '-framerate', String(fps),
        '-i', 'frame%05d.png',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-y', 'output.mp4'
      ]);
    }

    const outputData = await ffmpeg.readFile('output.mp4');
    const outputBlob = new Blob([outputData], { type: 'video/mp4' });
    showExportPreview(outputBlob, 'mp4');

    // Cleanup
    for (let i = 0; i < totalFrames; i++) {
      const name = 'frame' + String(i).padStart(5, '0') + '.png';
      try { await ffmpeg.deleteFile(name); } catch {}
    }
    try { await ffmpeg.deleteFile('output.mp4'); } catch {}
    try { await ffmpeg.deleteFile('audio.wav'); } catch {}

  } catch (err) {
    console.error('FFmpeg export failed:', err);
    // Fallback to MediaRecorder
    exportStatus.textContent = 'Falling back to real-time capture...';
    await exportWithMediaRecorder(duration, w, h, totalFrames, speedMult, audioSnapshots);
  }
}

function audioBufferToWav(audioBuffer, maxDuration) {
  const numChannels = audioBuffer.numberOfChannels;
  const sampleRate = audioBuffer.sampleRate;
  const duration = Math.min(audioBuffer.duration, maxDuration);
  const numSamples = Math.floor(duration * sampleRate);
  const buffer = new ArrayBuffer(44 + numSamples * numChannels * 2);
  const view = new DataView(buffer);

  function writeString(offset, str) {
    for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
  }

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + numSamples * numChannels * 2, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * numChannels * 2, true);
  view.setUint16(32, numChannels * 2, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, numSamples * numChannels * 2, true);

  let offset = 44;
  for (let i = 0; i < numSamples; i++) {
    for (let ch = 0; ch < numChannels; ch++) {
      const sample = audioBuffer.getChannelData(ch)[i];
      const clamped = Math.max(-1, Math.min(1, sample));
      view.setInt16(offset, clamped * 0x7FFF, true);
      offset += 2;
    }
  }

  return new Blob([buffer], { type: 'audio/wav' });
}

function showExportPreview(blob, ext) {
  if (lastExportBlob) URL.revokeObjectURL(lastExportBlob);
  lastExportBlob = URL.createObjectURL(blob);

  exportPreview.src = lastExportBlob;
  exportPreview.play();
  exportOverlay.classList.add('preview-mode');

  btnDownloadVideo.textContent = ext === 'mp4' ? 'Download MP4' : 'Download ' + ext.toUpperCase();
  btnDownloadVideo.onclick = () => {
    const link = document.createElement('a');
    link.download = 'kaleidoscope.' + ext;
    link.href = lastExportBlob;
    link.click();
  };

  // Gentle pulse on download button
  btnDownloadVideo.classList.add('pulse');
  setTimeout(() => btnDownloadVideo.classList.remove('pulse'), 2000);
}

// ============================================================================
// File handling (image)
// ============================================================================

dropZone.addEventListener('click', () => fileInput.click());

dropZone.addEventListener('dragover', e => {
  e.preventDefault();
  dropZone.classList.add('drag-over');
});

dropZone.addEventListener('dragleave', () => {
  dropZone.classList.remove('drag-over');
});

dropZone.addEventListener('drop', e => {
  e.preventDefault();
  dropZone.classList.remove('drag-over');
  if (e.dataTransfer.files.length) loadFile(e.dataTransfer.files[0]);
});

fileInput.addEventListener('change', () => {
  if (fileInput.files.length) loadFile(fileInput.files[0]);
});

function loadFile(file) {
  if (!file.type.startsWith('image/')) return;
  const reader = new FileReader();
  reader.onload = e => {
    const img = new Image();
    img.onload = () => {
      sourceImg = img;
      centerX = 0.5;
      centerY = 0.5;
      cxSlider.value = 50;
      cySlider.value = 50;
      scheduleRender();
      dropZone.classList.add('hidden');
      result.classList.add('visible');
    };
    img.src = e.target.result;
  };
  reader.readAsDataURL(file);
}

// --- Slider events ---

cxSlider.addEventListener('input', () => {
  centerX = cxSlider.value / 100;
  scheduleRender();
});

cySlider.addEventListener('input', () => {
  centerY = cySlider.value / 100;
  scheduleRender();
});

segSlider.addEventListener('input', () => scheduleRender());
zoomSlider.addEventListener('input', () => scheduleRender());

// --- Drag on canvas to move center ---

let dragging = false;

canvasWrap.addEventListener('pointerdown', e => {
  if (e.target.closest('#export-overlay')) return;
  dragging = true;
  updateCenter(e);
  canvasWrap.setPointerCapture(e.pointerId);
});

canvasWrap.addEventListener('pointermove', e => {
  if (!dragging) return;
  updateCenter(e);
});

canvasWrap.addEventListener('pointerup', () => { dragging = false; });

function updateCenter(e) {
  const rect = canvasWrap.getBoundingClientRect();
  centerX = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
  centerY = Math.max(0, Math.min(1, (e.clientY - rect.top) / rect.height));
  cxSlider.value = centerX * 100;
  cySlider.value = centerY * 100;
  if (!anim.playing) scheduleRender();
}

// --- Buttons ---

document.getElementById('btn-shuffle').addEventListener('click', () => {
  centerX = 0.15 + Math.random() * 0.7;
  centerY = 0.15 + Math.random() * 0.7;
  cxSlider.value = centerX * 100;
  cySlider.value = centerY * 100;
  segSlider.value = [6, 8, 10, 12, 16, 20][Math.floor(Math.random() * 6)];
  zoomSlider.value = 60 + Math.random() * 100;
  if (!anim.playing) scheduleRender();
});

document.getElementById('btn-new').addEventListener('click', () => {
  stopAnimation();
  removeAudio();
  sourceImg = null;
  result.classList.remove('visible');
  dropZone.classList.remove('hidden');
  fileInput.value = '';
});

// --- Share buttons ---

const shareText = 'Check out this kaleidoscope I made!';
const shareUrl = window.location.href;

document.getElementById('share-instagram').addEventListener('click', () => {
  const exp = renderExport();
  const link = document.createElement('a');
  link.download = 'kaleidoscope-instagram-1080x1080.png';
  link.href = exp.toDataURL('image/png');
  link.click();
  const btn = document.getElementById('share-instagram');
  btn.textContent = 'Saved!';
  setTimeout(() => { btn.innerHTML = '<svg viewBox="0 0 24 24"><rect x="2" y="2" width="20" height="20" rx="5" ry="5"/><circle cx="12" cy="12" r="5"/><circle cx="17.5" cy="6.5" r="1.5"/></svg> Instagram'; }, 2000);
});

document.getElementById('share-x').addEventListener('click', () => {
  window.open(
    'https://x.com/intent/tweet?text=' + encodeURIComponent(shareText + ' ' + shareUrl),
    '_blank', 'width=550,height=420'
  );
});

document.getElementById('share-facebook').addEventListener('click', () => {
  window.open(
    'https://www.facebook.com/sharer/sharer.php?u=' + encodeURIComponent(shareUrl),
    '_blank', 'width=550,height=420'
  );
});

document.getElementById('share-pinterest').addEventListener('click', () => {
  const exp = renderExport();
  const imgData = exp.toDataURL('image/png');
  window.open(
    'https://pinterest.com/pin/create/button/?url=' + encodeURIComponent(shareUrl) + '&description=' + encodeURIComponent(shareText) + '&media=' + encodeURIComponent(imgData),
    '_blank', 'width=550,height=520'
  );
});

document.getElementById('share-copy').addEventListener('click', async () => {
  try {
    const exp = renderExport();
    const blob = await new Promise(resolve => exp.toBlob(resolve, 'image/png'));
    await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
    const btn = document.getElementById('share-copy');
    btn.classList.add('copied');
    btn.innerHTML = '<svg viewBox="0 0 24 24"><polyline points="20 6 9 17 4 12"/></svg> Copied!';
    setTimeout(() => {
      btn.classList.remove('copied');
      btn.innerHTML = '<svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg> Copy';
    }, 2000);
  } catch {
    alert('Could not copy \u2014 try downloading instead.');
  }
});

if (navigator.share && navigator.canShare) {
  const nativeBtn = document.createElement('button');
  nativeBtn.className = 'share-btn';
  nativeBtn.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg> More';
  nativeBtn.addEventListener('click', async () => {
    try {
      const exp = renderExport();
      const blob = await new Promise(resolve => exp.toBlob(resolve, 'image/png'));
      const file = new File([blob], 'kaleidoscope.png', { type: 'image/png' });
      await navigator.share({ title: 'My Kaleidoscope', text: shareText, files: [file] });
    } catch {}
  });
  document.querySelector('.share-bar').appendChild(nativeBtn);
}

// ============================================================================
// Keyboard shortcuts
// ============================================================================

document.addEventListener('keydown', e => {
  if (!sourceImg) return;
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;

  switch (e.code) {
    case 'Space':
      e.preventDefault();
      if (anim.playing) stopAnimation();
      else startAnimation();
      break;
    case 'KeyR':
      if (anim.playing && !exportOverlay.classList.contains('visible')) {
        exportPopover.classList.toggle('visible');
      }
      break;
    case 'Escape':
      if (exportOverlay.classList.contains('visible')) {
        exportCancelled = true;
      }
      exportPopover.classList.remove('visible');
      break;
    case 'Digit1': moodSelect.value = 'meditative'; applyMoodPreset('meditative'); break;
    case 'Digit2': moodSelect.value = 'gentle'; applyMoodPreset('gentle'); break;
    case 'Digit3': moodSelect.value = 'dramatic'; applyMoodPreset('dramatic'); break;
    case 'Digit4': moodSelect.value = 'psychedelic'; applyMoodPreset('psychedelic'); break;
  }
});
