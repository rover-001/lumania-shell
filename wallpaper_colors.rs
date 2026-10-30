use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[derive(Debug, Clone)]
struct ColorCand {
    count: u64,
    hex: String,
    r: f32,
    g: f32,
    b: f32,
    h: f32,
    s: f32,
    v: f32,
    lum: f32,
}

fn rgb_to_hsv(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;

    let h = if delta == 0.0 {
        0.0
    } else if max == r {
        (((g - b) / delta) % 6.0 + 6.0) % 6.0 / 6.0
    } else if max == g {
        (((b - r) / delta) + 2.0) / 6.0
    } else {
        (((r - g) / delta) + 4.0) / 6.0
    };

    let s = if max == 0.0 { 0.0 } else { delta / max };
    let v = max;
    (h, s, v)
}

fn hsv_to_rgb(h: f32, s: f32, v: f32) -> (f32, f32, f32) {
    let c = v * s;
    let x = c * (1.0 - ((h * 6.0) % 2.0 - 1.0).abs());
    let m = v - c;

    let (r_prime, g_prime, b_prime) = match (h * 6.0) as u32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };

    (r_prime + m, g_prime + m, b_prime + m)
}

fn find_wallpaper() -> Option<PathBuf> {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/rover".into());
    let primary = PathBuf::from(format!("{}/.local/state/omarchy/current/background", home));
    if primary.exists() {
        if let Ok(real) = fs::canonicalize(&primary) {
            if real.exists() {
                return Some(real);
            }
        }
        return Some(primary);
    }

    let bg_dir = PathBuf::from(format!("{}/.local/state/omarchy/current/theme/backgrounds", home));
    if bg_dir.is_dir() {
        if let Ok(entries) = fs::read_dir(bg_dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if let Some(ext) = p.extension() {
                    let s = ext.to_string_lossy().to_lowercase();
                    if s == "jpg" || s == "jpeg" || s == "png" || s == "webp" {
                        return Some(p);
                    }
                }
            }
        }
    }
    None
}

fn extract_colors_from_wallpaper(wp_path: &Path) -> Result<String, String> {
    // Ultra-fast path: return cached JSON if wallpaper path and mtime are unchanged (<1ms)
    // Per-user runtime dir (0700): a fixed /tmp path could be pre-created or symlinked
    // by another local account. No runtime dir means no cache.
    let cache_file = env::var_os("XDG_RUNTIME_DIR")
        .filter(|d| !d.is_empty())
        .map(|d| PathBuf::from(d).join("lumania_wallpaper_cache.json"));
    if let Ok(meta) = fs::symlink_metadata("/tmp/lumania_wallpaper_cache.json") {
        if !meta.file_type().is_symlink() {
            let _ = fs::remove_file("/tmp/lumania_wallpaper_cache.json");
        }
    }
    let current_mtime_secs = fs::metadata(wp_path)
        .and_then(|m| m.modified())
        .map(|t| t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs())
        .unwrap_or(0);

    let wp_str = wp_path.to_string_lossy();
    if current_mtime_secs > 0 {
        if let Some(Ok(cache_content)) = cache_file.as_ref().map(fs::read_to_string) {
            if let Some((cached_path, rest)) = cache_content.split_once("||") {
                if let Some((cached_mtime, json)) = rest.split_once("||") {
                    if cached_path == wp_str && cached_mtime == current_mtime_secs.to_string() {
                        return Ok(json.trim().to_string());
                    }
                }
            }
        }
    }

    // High-performance hardware-scaled downsampling (sub-70ms)
    let output = Command::new("magick")
        .args([
            "-define",
            "jpeg:size=64x64",
            wp_path.to_str().unwrap(),
            "-sample",
            "32x32!",
            "-colors",
            "8",
            "-format",
            "%c\n",
            "histogram:info:",
        ])
        .output()
        .map_err(|e| format!("Failed to execute magick: {}", e))?;

    if !output.status.success() {
        return Err("magick command failed".into());
    }

    let raw = String::from_utf8_lossy(&output.stdout);
    let mut candidates = Vec::new();

    for line in raw.lines() {
        let line = line.trim();
        if line.is_empty() || !line.contains('#') {
            continue;
        }

        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() < 2 {
            continue;
        }
        let count: u64 = parts[0].trim().parse().unwrap_or(0);

        let hex_part = line.split('#').nth(1).unwrap_or("");
        let hex_code: String = hex_part
            .split_whitespace()
            .next()
            .unwrap_or("")
            .chars()
            .take(6)
            .collect();

        if hex_code.len() == 6 {
            if let (Ok(r_val), Ok(g_val), Ok(b_val)) = (
                u8::from_str_radix(&hex_code[0..2], 16),
                u8::from_str_radix(&hex_code[2..4], 16),
                u8::from_str_radix(&hex_code[4..6], 16),
            ) {
                let r = r_val as f32 / 255.0;
                let g = g_val as f32 / 255.0;
                let b = b_val as f32 / 255.0;
                let (h, s, v) = rgb_to_hsv(r, g, b);
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

                candidates.push(ColorCand {
                    count,
                    hex: format!("#{}", hex_code.to_lowercase()),
                    r,
                    g,
                    b,
                    h,
                    s,
                    v,
                    lum,
                });
            }
        }
    }

    if candidates.is_empty() {
        return Ok(r##"{"accent":"#ba5f58","complementary":"#58a8ba","muted":"#7d4843","textColor":"#ffffff","sliderFill":"#ffffff","sliderIconFilled":"#ba5f58","sliderIconUnfilled":"#ffffff"}"##.into());
    }

    // Aesthetic Scoring: prefer vibrant, rich UI tones
    // Penalize pure black/grey and overly blown out white
    candidates.sort_by(|a, b| {
        let score_a = score_candidate(a);
        let score_b = score_candidate(b);
        score_b.partial_cmp(&score_a).unwrap_or(std::cmp::Ordering::Equal)
    });

    let best = &candidates[0];
    let accent_hex = best.hex.clone();

    // Contrast text calculation
    let text_color = if best.lum > 0.58 { "#111111" } else { "#ffffff" };

    // Muted tone (same hue, lower saturation/value)
    let (mr, mg, mb) = hsv_to_rgb(best.h, (best.s * 0.55).max(0.18), (best.v * 0.70).max(0.25));
    let muted_hex = format!("#{:02x}{:02x}{:02x}", (mr * 255.0) as u8, (mg * 255.0) as u8, (mb * 255.0) as u8);

    // Complementary accent (180 deg opposite hue)
    let comp_h = (best.h + 0.5) % 1.0;
    let (cr, cg, cb) = hsv_to_rgb(comp_h, best.s.clamp(0.35, 0.75), best.v.clamp(0.55, 0.90));
    let comp_hex = format!("#{:02x}{:02x}{:02x}", (cr * 255.0) as u8, (cg * 255.0) as u8, (cb * 255.0) as u8);

    let wp_filename = wp_path.file_name().and_then(|f| f.to_str()).unwrap_or("unknown");

    let json = format!(
        r##"{{"accent":"{}","complementary":"{}","muted":"{}","textColor":"{}","sliderFill":"#ffffff","sliderIconFilled":"{}","sliderIconUnfilled":"#ffffff","luminance":{:.3},"wallpaper":"{}"}}"##,
        accent_hex, comp_hex, muted_hex, text_color, accent_hex, best.lum, wp_filename
    );

    // Save to cache
    if current_mtime_secs > 0 {
        if let Some(cache_file) = cache_file.as_ref() {
            let _ = fs::write(cache_file, format!("{}||{}||{}", wp_str, current_mtime_secs, json));
        }
    }

    Ok(json)
}

fn score_candidate(c: &ColorCand) -> f32 {
    if c.v < 0.18 || (c.s < 0.10 && c.v > 0.88) {
        return 0.01;
    }
    let s_factor = (c.s / 0.55).min(1.2);
    let v_dist = (c.v - 0.62).abs();
    let v_factor = (1.0 - (v_dist * 1.4)).max(0.15);
    let pop = (c.count as f32).powf(0.32);
    s_factor * v_factor * pop
}

fn write_json_output(json: &str) {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/rover".into());
    let out_dir = PathBuf::from(format!("{}/.local/state/omarchy/current", home));
    let _ = fs::create_dir_all(&out_dir);
    let out_file = out_dir.join("lumania-colors.json");
    let _ = fs::write(out_file, json);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let daemon_mode = args.iter().any(|a| a == "--daemon" || a == "-d" || a == "--watch");

    if !daemon_mode {
        if let Some(wp) = find_wallpaper() {
            match extract_colors_from_wallpaper(&wp) {
                Ok(json) => {
                    println!("{}", json);
                    write_json_output(&json);
                }
                Err(err) => {
                    eprintln!("Error: {}", err);
                    println!(r##"{{"accent":"#ba5f58","complementary":"#58a8ba","muted":"#7d4843","textColor":"#ffffff","sliderFill":"#ffffff","sliderIconFilled":"#ba5f58","sliderIconUnfilled":"#ffffff"}}"##);
                }
            }
        } else {
            println!(r##"{{"accent":"#ba5f58","complementary":"#58a8ba","muted":"#7d4843","textColor":"#ffffff","sliderFill":"#ffffff","sliderIconFilled":"#ba5f58","sliderIconUnfilled":"#ffffff"}}"##);
        }
        return;
    }

    // Daemon mode: periodically checks if wallpaper path or timestamp changed
    let mut last_path = String::new();
    let mut last_mtime = None;

    loop {
        if let Some(wp) = find_wallpaper() {
            let path_str = wp.to_string_lossy().to_string();
            let mtime = fs::metadata(&wp).and_then(|m| m.modified()).ok();

            if path_str != last_path || mtime != last_mtime {
                last_path = path_str;
                last_mtime = mtime;

                if let Ok(json) = extract_colors_from_wallpaper(&wp) {
                    write_json_output(&json);
                    println!("{}", json);
                }
            }
        }
        thread::sleep(Duration::from_millis(1500));
    }
}
