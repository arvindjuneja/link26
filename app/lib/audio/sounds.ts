const volume = 0.15;
let audioCtx: AudioContext | null = null;

function ensureAudio() {
  if (typeof window === "undefined") return null;
  if (!audioCtx) {
    audioCtx = new AudioContext();
  }
  return audioCtx;
}

function playTone(frequency: number, duration: number, type: OscillatorType = "sine", volumeMultiplier = 1) {
  const ctx = ensureAudio();
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = type;
  osc.frequency.value = frequency;
  gain.gain.value = volume * volumeMultiplier;
  gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + duration);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
  osc.stop(ctx.currentTime + duration);
}

function playChord(frequencies: number[], duration: number, type: OscillatorType = "sine") {
  const ctx = ensureAudio();
  if (!ctx) return;
  frequencies.forEach((freq, index) => {
    setTimeout(() => playTone(freq, duration, type, 0.6), index * 30);
  });
}

export function playClick() {
  playTone(1200, 0.04, "square");
}

export function playBeep() {
  playTone(800, 0.12, "triangle");
}

export function playAlert() {
  playChord([400, 300, 200], 0.25, "sawtooth");
}

export function playScan() {
  // Rising scan sound
  const ctx = ensureAudio();
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = "sawtooth";
  osc.frequency.setValueAtTime(300, ctx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(1200, ctx.currentTime + 0.3);
  gain.gain.value = volume * 0.8;
  gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.3);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
  osc.stop(ctx.currentTime + 0.3);
}

export function playConnect() {
  // Connection established - satisfying beep
  playChord([600, 800, 1000], 0.15, "sine");
}

export function playSuccess() {
  // Victory fanfare
  playChord([523, 659, 784, 1047], 0.4, "triangle");
}

export function playRouteAdd() {
  // Quick blip for route addition
  playTone(1000, 0.08, "square", 0.7);
}

export function playFileOp() {
  // Subtle file operation sound
  playTone(600, 0.1, "sine", 0.5);
}

export function playTraceRise() {
  // Warning tone for trace increase
  const ctx = ensureAudio();
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = "sawtooth";
  osc.frequency.setValueAtTime(200, ctx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(400, ctx.currentTime + 0.15);
  gain.gain.value = volume * 0.5;
  gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.2);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
  osc.stop(ctx.currentTime + 0.2);
}

export function playTraceWarning() {
  // Urgent warning for high trace
  const ctx = ensureAudio();
  if (!ctx) return;
  for (let i = 0; i < 2; i++) {
    setTimeout(() => {
      playChord([300, 200], 0.12, "sawtooth");
    }, i * 150);
  }
}

export function playTyping() {
  // Subtle typing click
  playTone(1800, 0.02, "square", 0.3);
}

// The Exposure Board heartbeat — a soft lub-dub. Driven at BPM by the worst
// channel's status; silence at CALM is the reward, a hammering pulse the dread.
export function playHeartbeat(intensity = 1) {
  const ctx = ensureAudio();
  if (!ctx) return;
  const thump = (freq: number, at: number, vol: number) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = "sine";
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, ctx.currentTime + at);
    gain.gain.exponentialRampToValueAtTime(volume * vol, ctx.currentTime + at + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + at + 0.14);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(ctx.currentTime + at);
    osc.stop(ctx.currentTime + at + 0.16);
  };
  thump(70, 0, 0.9 * intensity); // lub
  thump(52, 0.14, 0.6 * intensity); // dub
}
