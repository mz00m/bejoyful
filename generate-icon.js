const { createCanvas } = require('canvas');
const fs = require('fs');

const size = 1024;
const canvas = createCanvas(size, size);
const ctx = canvas.getContext('2d');

// Background
ctx.fillStyle = '#0c0c1a';
ctx.fillRect(0, 0, size, size);

const cx = size / 2;
const cy = size / 2;
const numSegments = 12;
const halfAngle = Math.PI / numSegments;
const radius = size * 0.52;

// Draw a single wedge with colorful shapes
function drawWedge(ctx) {
  // Gradient background for the wedge
  const grad = ctx.createLinearGradient(0, 0, radius, 0);
  grad.addColorStop(0, '#1a0a3e');
  grad.addColorStop(0.3, '#2d1b69');
  grad.addColorStop(0.6, '#0d8a8a');
  grad.addColorStop(0.85, '#3de8c5');
  grad.addColorStop(1, '#b8a9f0');

  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(radius * Math.cos(-halfAngle), radius * Math.sin(-halfAngle));
  ctx.arc(0, 0, radius, -halfAngle, halfAngle);
  ctx.closePath();
  ctx.fillStyle = grad;
  ctx.fill();

  // Decorative shapes within the wedge
  const shapes = [
    { x: 120, y: 0, r: 35, color: 'rgba(184, 169, 240, 0.7)' },
    { x: 200, y: 15, r: 20, color: 'rgba(61, 232, 197, 0.6)' },
    { x: 280, y: -10, r: 45, color: 'rgba(13, 138, 138, 0.5)' },
    { x: 350, y: 8, r: 25, color: 'rgba(255, 255, 255, 0.25)' },
    { x: 160, y: -20, r: 15, color: 'rgba(232, 167, 240, 0.5)' },
    { x: 420, y: -5, r: 55, color: 'rgba(45, 27, 105, 0.4)' },
    { x: 240, y: 25, r: 12, color: 'rgba(255, 255, 255, 0.35)' },
    { x: 80, y: 5, r: 22, color: 'rgba(61, 232, 197, 0.4)' },
    { x: 310, y: 20, r: 18, color: 'rgba(184, 169, 240, 0.45)' },
    { x: 380, y: -18, r: 30, color: 'rgba(13, 200, 180, 0.35)' },
    { x: 450, y: 12, r: 40, color: 'rgba(184, 169, 240, 0.2)' },
  ];

  for (const s of shapes) {
    ctx.beginPath();
    ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
    ctx.fillStyle = s.color;
    ctx.fill();
  }

  // Thin bright lines radiating outward
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
  ctx.lineWidth = 1;
  for (let d = 80; d < radius; d += 70) {
    ctx.beginPath();
    ctx.arc(0, 0, d, -halfAngle, halfAngle);
    ctx.stroke();
  }
}

// Draw all segments
for (let i = 0; i < numSegments; i++) {
  const angle = (2 * Math.PI / numSegments) * i;
  const mirrored = i % 2 === 1;

  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(angle);

  if (mirrored) {
    ctx.scale(1, -1);
  }

  // Clip to wedge
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(radius * Math.cos(-halfAngle), radius * Math.sin(-halfAngle));
  ctx.arc(0, 0, radius, -halfAngle, halfAngle);
  ctx.closePath();
  ctx.clip();

  drawWedge(ctx);

  ctx.restore();
}

// Center jewel
const jewelGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, 60);
jewelGrad.addColorStop(0, '#ffffff');
jewelGrad.addColorStop(0.2, '#e0d4ff');
jewelGrad.addColorStop(0.5, '#b8a9f0');
jewelGrad.addColorStop(0.8, '#5a3e9e');
jewelGrad.addColorStop(1, '#1a0a3e');
ctx.beginPath();
ctx.arc(cx, cy, 55, 0, Math.PI * 2);
ctx.fillStyle = jewelGrad;
ctx.fill();

// Inner bright dot
const dotGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, 18);
dotGrad.addColorStop(0, '#ffffff');
dotGrad.addColorStop(0.6, '#d4c8f5');
dotGrad.addColorStop(1, 'rgba(184, 169, 240, 0)');
ctx.beginPath();
ctx.arc(cx, cy, 18, 0, Math.PI * 2);
ctx.fillStyle = dotGrad;
ctx.fill();

// Outer vignette
const vigGrad = ctx.createRadialGradient(cx, cy, size * 0.32, cx, cy, size * 0.54);
vigGrad.addColorStop(0, 'rgba(0,0,0,0)');
vigGrad.addColorStop(1, 'rgba(12,12,26,0.85)');
ctx.fillStyle = vigGrad;
ctx.fillRect(0, 0, size, size);

// Rounded corners mask (iOS icon shape)
// iOS icons are displayed with rounded corners by the OS, so a square PNG is fine

const buffer = canvas.toBuffer('image/png');
fs.writeFileSync('/home/user/bejoyful/KaleidoscopeMaker/KaleidoscopeMaker/Assets.xcassets/AppIcon.appiconset/icon-1024.png', buffer);
console.log('App icon generated: 1024x1024 PNG');
