use std::io::{BufReader, Read, Write, stdout};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const CHUNK: usize = 512;
const RATE: u32 = 22050;
const NUM_BANDS: usize = 9;
const NUM_BARS: usize = 18;
const MIN_HEIGHT: f32 = 2.0;
const MAX_HEIGHT: f32 = 18.0;
const SILENCE_RMS: f32 = 0.006;

// Cooley-Tukey Radix-2 in-place FFT
fn fft(real: &mut [f32; CHUNK], imag: &mut [f32; CHUNK]) {
    let mut j = 0;
    let n2 = CHUNK / 2;
    for i in 1..(CHUNK - 1) {
        let mut n1 = n2;
        while j >= n1 {
            j -= n1;
            n1 /= 2;
        }
        j += n1;
        if i < j {
            real.swap(i, j);
            imag.swap(i, j);
        }
    }

    let mut n2 = 1;
    for _ in 0..9 {
        let n1 = n2;
        n2 += n2;
        for k in 0..n1 {
            let angle = -std::f32::consts::PI * (k as f32) / (n1 as f32);
            let c = angle.cos();
            let s = angle.sin();
            let mut idx = k;
            while idx < CHUNK {
                let t1 = c * real[idx + n1] - s * imag[idx + n1];
                let t2 = s * real[idx + n1] + c * imag[idx + n1];
                real[idx + n1] = real[idx] - t1;
                imag[idx + n1] = imag[idx] - t2;
                real[idx] += t1;
                imag[idx] += t2;
                idx += n2;
            }
        }
    }
}

// Cheap per-bar randomness in [0, 1)
fn xorshift(state: &mut u32) -> f32 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    (x as f32) / (u32::MAX as f32)
}

// Bars are mirrored around the center: center = lowest band (bass), edges = highest (treble)
fn band_for_bar(i: usize) -> usize {
    let d = (i as f32 - (NUM_BARS as f32 - 1.0) / 2.0).abs(); // 0.5 .. 8.5
    (d as usize).min(NUM_BANDS - 1)
}

fn spawn_capture() -> Option<Child> {
    Command::new("pw-record")
        .args(&[
            "--target",
            "@DEFAULT_AUDIO_SINK@",
            "-P",
            "{ stream.capture.sink = true }",
            "--format",
            "s16",
            "--rate",
            "22050",
            "--channels",
            "1",
            "-",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()
}

fn main() {
    let mut hanning = [0.0f32; CHUNK];
    for i in 0..CHUNK {
        hanning[i] =
            0.5 * (1.0 - (2.0 * std::f32::consts::PI * (i as f32) / ((CHUNK - 1) as f32)).cos());
    }

    // 9 log-spaced frequency bands spanning 120 Hz to 6500 Hz
    let min_f = 120.0f32;
    let max_f = 6500.0f32;
    let freq_step = ((RATE as f32) / 2.0) / ((CHUNK / 2) as f32); // ~21.5 Hz

    let mut band_indices = [(0usize, 1usize); NUM_BANDS];
    for i in 0..NUM_BANDS {
        let f1 = min_f * (max_f / min_f).powf((i as f32) / (NUM_BANDS as f32));
        let f2 = min_f * (max_f / min_f).powf(((i + 1) as f32) / (NUM_BANDS as f32));
        let mut b1 = (f1 / freq_step).floor() as usize;
        let mut b2 = (f2 / freq_step).ceil() as usize;
        if b1 == 0 {
            b1 = 1;
        }
        if b2 <= b1 {
            b2 = b1 + 1;
        }
        if b2 > CHUNK / 2 {
            b2 = CHUNK / 2;
        }
        if b1 >= b2 {
            b1 = b2.saturating_sub(1);
        }
        band_indices[i] = (b1, b2);
    }

    let mut bar_band = [0usize; NUM_BARS];
    let mut bar_taper = [1.0f32; NUM_BARS];
    for i in 0..NUM_BARS {
        bar_band[i] = band_for_bar(i);
        let d = (i as f32 - (NUM_BARS as f32 - 1.0) / 2.0).abs() / ((NUM_BARS as f32 - 1.0) / 2.0);
        bar_taper[i] = 1.0 - 0.2 * d; // gentle falloff toward the wings
    }

    // Per-band state: adaptive peak (AGC) and envelope (instant attack, quick release = spikes)
    let mut band_peak = [0.05f32; NUM_BANDS];
    let mut env = [0.0f32; NUM_BANDS];
    let mut bars = [0.0f32; NUM_BARS];
    let mut rng: u32 = 0x9E37_79B9;
    let mut phase = 0.0f32;

    let mut child = match spawn_capture() {
        Some(c) => c,
        None => {
            eprintln!("Failed to spawn pw-record");
            std::process::exit(1);
        }
    };

    let stdout_pipe = child.stdout.take().expect("Failed to get stdout pipe");
    let mut reader = BufReader::with_capacity(CHUNK * 4, stdout_pipe);
    let mut raw_buf = [0u8; CHUNK * 2];
    let mut real = [0.0f32; CHUNK];
    let mut imag = [0.0f32; CHUNK];
    let mut mag = [0.0f32; CHUNK / 2];

    let mut out_str = String::with_capacity(128);
    let mut out_handle = stdout().lock();
    let mut last_emit = Instant::now();
    let min_interval = Duration::from_millis(12);

    loop {
        if reader.read_exact(&mut raw_buf).is_err() {
            let _ = child.kill();
            std::thread::sleep(Duration::from_millis(200));
            if let Some(mut new_child) = spawn_capture() {
                if let Some(new_stdout) = new_child.stdout.take() {
                    reader = BufReader::with_capacity(CHUNK * 4, new_stdout);
                    child = new_child;
                    continue;
                }
            }
            break;
        }

        let mut sum_sq = 0.0f32;
        for i in 0..CHUNK {
            let s = i16::from_le_bytes([raw_buf[i * 2], raw_buf[i * 2 + 1]]) as f32 / 32768.0;
            sum_sq += s * s;
            real[i] = s * hanning[i];
            imag[i] = 0.0;
        }
        let rms = (sum_sq / (CHUNK as f32)).sqrt();
        let silent = rms < SILENCE_RMS;

        let mut norm = [0.0f32; NUM_BANDS];
        if !silent {
            fft(&mut real, &mut imag);
            for i in 0..(CHUNK / 2) {
                mag[i] = (real[i] * real[i] + imag[i] * imag[i]).sqrt();
            }

            for b in 0..NUM_BANDS {
                let (b1, b2) = band_indices[b];
                let count = (b2 - b1).max(1);
                let mut sum = 0.0f32;
                for k in b1..b2 {
                    sum += mag[k];
                }
                let v = sum / (count as f32);

                // Per-band AGC: each band is normalised to its own recent peak,
                // so bands move independently instead of sharing one global shape
                band_peak[b] = if v > band_peak[b] {
                    band_peak[b] * 0.6 + v * 0.4
                } else {
                    (band_peak[b] * 0.995).max(1e-5)
                };
                norm[b] = (v / (band_peak[b] + 1e-6)).clamp(0.0, 1.0).powf(0.8);
            }
        }

        // Envelope: jump up instantly on a hit, fall back quickly -> spiky, responsive
        for b in 0..NUM_BANDS {
            env[b] = if norm[b] > env[b] { norm[b] } else { env[b] * 0.82 };
        }

        // Traveling undulation plus per-bar jitter so no two bars move in lockstep
        phase += 0.35;
        if phase > std::f32::consts::TAU {
            phase -= std::f32::consts::TAU;
        }
        for i in 0..NUM_BARS {
            let jitter = 0.85 + 0.30 * xorshift(&mut rng);
            let wave = 0.92 + 0.08 * (phase - i as f32 * 0.7).sin();
            let raw = env[bar_band[i]] * jitter * bar_taper[i] * wave;
            bars[i] = raw.clamp(0.0, 1.0);
        }

        let now = Instant::now();
        if now.duration_since(last_emit) >= min_interval {
            last_emit = now;
            out_str.clear();
            for i in 0..NUM_BARS {
                let h = MIN_HEIGHT + bars[i] * (MAX_HEIGHT - MIN_HEIGHT);
                out_str.push_str(&format!("{:.1}", h));
                if i < NUM_BARS - 1 {
                    out_str.push(' ');
                }
            }
            out_str.push('\n');
            let _ = out_handle.write_all(out_str.as_bytes());
            let _ = out_handle.flush();
        }
    }

    let _ = child.kill();
}
