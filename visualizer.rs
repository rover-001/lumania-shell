use std::io::{BufReader, Read, Write, stdout};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const CHUNK: usize = 512;
const RATE: u32 = 22050;
const NUM_BARS: usize = 22;
const MIN_HEIGHT: f32 = 2.0;
const MAX_HEIGHT: f32 = 18.0;

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
    // Precompute Hanning window
    let mut hanning = [0.0f32; CHUNK];
    for i in 0..CHUNK {
        hanning[i] =
            0.5 * (1.0 - (2.0 * std::f32::consts::PI * (i as f32) / ((CHUNK - 1) as f32)).cos());
    }

    // Frequency bands from 60 Hz to 8000 Hz (logarithmic distribution)
    let min_f = 60.0f32;
    let max_f = 8000.0f32;
    let freq_step = ((RATE as f32) / 2.0) / ((CHUNK / 2) as f32); // ~43.07 Hz

    let mut band_indices = [(0usize, 1usize); NUM_BARS];
    let mut band_boost = [1.0f32; NUM_BARS];
    for i in 0..NUM_BARS {
        let f1 = min_f * (max_f / min_f).powf((i as f32) / (NUM_BARS as f32));
        let f2 = min_f * (max_f / min_f).powf(((i + 1) as f32) / (NUM_BARS as f32));
        let mut b1 = (f1 / freq_step).floor() as usize;
        let mut b2 = (f2 / freq_step).ceil() as usize;
        if b1 == 0 {
            b1 = 1;
        } // Skip DC offset
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

        // Compensate for natural pink-noise rolloff in higher frequencies
        let progress = (i as f32) / ((NUM_BARS - 1) as f32);
        band_boost[i] = 1.0 + 1.8 * progress.powf(1.15);
    }

    let mut smoothed = [0.0f32; NUM_BARS];
    let mut peak_history = 0.20f32;

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
    let min_interval = Duration::from_millis(30); // Clean 33 FPS cadence for QML

    loop {
        if reader.read_exact(&mut raw_buf).is_err() {
            // If pw-record terminated, wait briefly and try to restart
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
        let now = Instant::now();
        let should_emit = now.duration_since(last_emit) >= min_interval;

        // When audio is silent or paused, decay gently to baseline
        if rms < 0.006 {
            for i in 0..NUM_BARS {
                smoothed[i] *= 0.72;
            }
            if should_emit {
                last_emit = now;
                out_str.clear();
                for i in 0..NUM_BARS {
                    let h = MIN_HEIGHT + smoothed[i] * (MAX_HEIGHT - MIN_HEIGHT);
                    out_str.push_str(&format!("{:.1}", h));
                    if i < NUM_BARS - 1 {
                        out_str.push(' ');
                    }
                }
                out_str.push('\n');
                let _ = out_handle.write_all(out_str.as_bytes());
                let _ = out_handle.flush();
            }
            continue;
        }

        fft(&mut real, &mut imag);

        let mut frame_peak = 0.001f32;
        for i in 0..(CHUNK / 2) {
            let m = (real[i] * real[i] + imag[i] * imag[i]).sqrt();
            mag[i] = m;
            if m > frame_peak {
                frame_peak = m;
            }
        }

        // Automatic Gain Control with fast rise and slow decay
        if frame_peak > peak_history {
            peak_history = peak_history * 0.75 + frame_peak * 0.25;
        } else {
            peak_history = (peak_history * 0.985).max(0.10);
        }

        for i in 0..NUM_BARS {
            let (b1, b2) = band_indices[i];
            let count = (b2 - b1).max(1);
            let mut sum = 0.0f32;
            for b in b1..b2 {
                sum += mag[b];
            }
            let band_val = (sum / (count as f32)) * band_boost[i];

            // Calibrated dynamic range: prevents max-clipping across all bars
            let mut norm = (band_val / (peak_history * 0.95 + 1e-4)).clamp(0.0, 1.0);
            norm = norm.powf(0.82); // Perceptual loudness expansion

            // Snappy attack, silky release
            if norm > smoothed[i] {
                smoothed[i] = smoothed[i] * 0.30 + norm * 0.70;
            } else {
                smoothed[i] = smoothed[i] * 0.75 + norm * 0.25;
            }
        }

        if should_emit {
            last_emit = now;
            out_str.clear();
            for i in 0..NUM_BARS {
                let h = MIN_HEIGHT + smoothed[i] * (MAX_HEIGHT - MIN_HEIGHT);
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
