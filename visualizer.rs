use std::io::{BufReader, Read, Write, stdout};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const CHUNK: usize = 512;
const RATE: u32 = 22050;
const NUM_BANDS: usize = 9;
const NUM_BARS: usize = 18;
const HALF: usize = NUM_BARS / 2;
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

// Traveling wave: voice energy enters at the center and ripples outward to both sides.
// A sine undulation rides on top so neighbouring bars form crests and troughs like a real wave,
// and a smooth taper keeps the center tallest with the endings lower but still alive.
fn push_ripple(ripple: &mut [f32; HALF], bars: &mut [f32; NUM_BARS], voice: f32, phase: &mut f32) {
    for k in (1..HALF).rev() {
        ripple[k] = ripple[k - 1] * 0.97;
    }
    ripple[0] = voice;
    *phase += 0.55;
    if *phase > std::f32::consts::TAU {
        *phase -= std::f32::consts::TAU;
    }
    for k in 0..HALF {
        let t = k as f32 / (HALF - 1) as f32;
        let taper = 0.45 + 0.55 * (t * std::f32::consts::FRAC_PI_2).cos();
        let undulate = 0.72 + 0.28 * (*phase - k as f32 * 0.85).sin();
        let v = (ripple[k] * taper * undulate).clamp(0.0, 1.0);
        bars[HALF - 1 - k] = v;
        bars[HALF + k] = v;
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
    let mut hanning = [0.0f32; CHUNK];
    for i in 0..CHUNK {
        hanning[i] =
            0.5 * (1.0 - (2.0 * std::f32::consts::PI * (i as f32) / ((CHUNK - 1) as f32)).cos());
    }

    // 9 frequency bands spanning 120 Hz to 6500 Hz
    let min_f = 120.0f32;
    let max_f = 6500.0f32;
    let freq_step = ((RATE as f32) / 2.0) / ((CHUNK / 2) as f32); // ~43.07 Hz

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

    let mut smoothed = [0.0f32; NUM_BARS];
    let mut level_peak = 0.05f32;
    let mut voice = 0.0f32;
    let mut ripple = [0.0f32; HALF];
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
    let min_interval = Duration::from_millis(30);

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
        let now = Instant::now();
        let should_emit = now.duration_since(last_emit) >= min_interval;

        // When audio is silent or paused, decay cleanly to baseline (2.0)
        if rms < 0.006 {
            voice *= 0.70;
            if should_emit {
                push_ripple(&mut ripple, &mut smoothed, voice, &mut phase);
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

        for i in 0..(CHUNK / 2) {
            mag[i] = (real[i] * real[i] + imag[i] * imag[i]).sqrt();
        }

        // Raw band energy; normalized against a shared peak so bands keep their relative shape
        let mut band_vals = [0.0f32; NUM_BANDS];
        let mut frame_max = 0.0f32;
        for b in 0..NUM_BANDS {
            let (b1, b2) = band_indices[b];
            let count = (b2 - b1).max(1);
            let mut sum = 0.0f32;
            for k in b1..b2 {
                sum += mag[k];
            }
            band_vals[b] = sum / (count as f32);
            frame_max = frame_max.max(band_vals[b]);
        }
        let mut band_norms = [0.0f32; NUM_BANDS];
        for b in 0..NUM_BANDS {
            band_norms[b] = (band_vals[b] / (frame_max + 1e-6)).sqrt();
        }

        // Slow loudness AGC: fast rise, slow fall, so level reflects dynamics of the voice
        if rms > level_peak {
            level_peak = level_peak * 0.80 + rms * 0.20;
        } else {
            level_peak = (level_peak * 0.993).max(0.02);
        }
        let level = (rms / level_peak).clamp(0.0, 1.0).powf(0.6);

        // Feed the current voice level into the center of the ripple
        let pulse = (level * (0.8 + 0.2 * band_norms[0].max(band_norms[1]))).clamp(0.0, 1.0);
        if pulse > voice {
            voice = voice * 0.35 + pulse * 0.65;
        } else {
            voice = voice * 0.88 + pulse * 0.12;
            voice = voice.max(0.18 * level.sqrt());
        }

        if should_emit {
            push_ripple(&mut ripple, &mut smoothed, voice, &mut phase);
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
