use gpui::Rgba;
use serde::Deserialize;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ExtractedColors {
    pub accent: String,
    pub complementary: String,
    pub muted: String,
    #[serde(rename = "textColor")]
    pub text_color: String,
    #[serde(default)]
    pub luminance: f32,
    #[serde(default)]
    pub wallpaper: String,
}

impl Default for ExtractedColors {
    fn default() -> Self {
        Self {
            accent: "#ba5f58".into(),
            complementary: "#58a8ba".into(),
            muted: "#7d4843".into(),
            text_color: "#ffffff".into(),
            luminance: 0.5,
            wallpaper: "default".into(),
        }
    }
}

pub fn hex_to_rgba(hex: &str, alpha: f32) -> Rgba {
    let clean = hex.trim().trim_start_matches('#');
    if clean.len() >= 6 {
        if let (Ok(r), Ok(g), Ok(b)) = (
            u8::from_str_radix(&clean[0..2], 16),
            u8::from_str_radix(&clean[2..4], 16),
            u8::from_str_radix(&clean[4..6], 16),
        ) {
            return Rgba {
                r: r as f32 / 255.0,
                g: g as f32 / 255.0,
                b: b as f32 / 255.0,
                a: alpha,
            };
        }
    }
    Rgba {
        r: 0.73,
        g: 0.37,
        b: 0.35,
        a: alpha,
    }
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct AppTheme {
    pub raw: ExtractedColors,
    pub accent: Rgba,
    pub complementary: Rgba,
    pub muted: Rgba,
    pub text_primary: Rgba,
    pub text_secondary: Rgba,
    pub text_muted: Rgba,
    pub window_bg: Rgba,
    pub card_bg: Rgba,
    pub card_hover_bg: Rgba,
    pub card_border: Rgba,
    pub active_tab_bg: Rgba,
}

impl AppTheme {
    pub fn load() -> Self {
        let raw = Self::extract_or_load_cached();
        let accent = hex_to_rgba(&raw.accent, 1.0);
        let complementary = hex_to_rgba(&raw.complementary, 1.0);
        let muted = hex_to_rgba(&raw.muted, 1.0);
        let text_primary = hex_to_rgba(&raw.text_color, 1.0);

        Self {
            raw,
            accent,
            complementary,
            muted,
            text_primary,
            text_secondary: Rgba {
                r: 0.85,
                g: 0.85,
                b: 0.88,
                a: 0.85,
            },
            text_muted: Rgba {
                r: 0.65,
                g: 0.65,
                b: 0.70,
                a: 0.60,
            },
            window_bg: Rgba {
                r: 0.07,
                g: 0.07,
                b: 0.09,
                a: 1.0,
            },
            card_bg: Rgba {
                r: 0.11,
                g: 0.11,
                b: 0.15,
                a: 0.95,
            },
            card_hover_bg: Rgba {
                r: 0.18,
                g: 0.18,
                b: 0.24,
                a: 0.70,
            },
            card_border: Rgba {
                r: 1.0,
                g: 1.0,
                b: 1.0,
                a: 0.08,
            },
            active_tab_bg: Rgba {
                r: 1.0,
                g: 1.0,
                b: 1.0,
                a: 0.12,
            },
        }
    }

    fn extract_or_load_cached() -> ExtractedColors {
        // Priority 1: Call native lumania-colors engine (sub-1ms cache check, auto-extracts on wallpaper change)
        let candidate_paths = [
            PathBuf::from("./lumania-colors"),
            PathBuf::from("../lumania-colors"),
            dirs_home().join(".config/omarchy/plugins/lumania.island/lumania-colors"),
            dirs_home().join("Projects/lumania shell/lumania-colors"),
            dirs_home().join(".local/bin/lumania-colors"),
        ];

        for bin in candidate_paths {
            if bin.exists() {
                if let Ok(output) = Command::new(&bin).output() {
                    if output.status.success() {
                        let stdout = String::from_utf8_lossy(&output.stdout);
                        if let Ok(parsed) = serde_json::from_str::<ExtractedColors>(stdout.trim()) {
                            return parsed;
                        }
                    }
                }
            }
        }

        // Priority 2: Direct cache fallback
        if let Some(runtime_dir) = env::var_os("XDG_RUNTIME_DIR") {
            let cache_file = PathBuf::from(runtime_dir).join("lumania_wallpaper_cache.json");
            if let Ok(content) = fs::read_to_string(cache_file) {
                if let Some((_, rest)) = content.split_once("||") {
                    if let Some((_, json_str)) = rest.split_once("||") {
                        if let Ok(parsed) = serde_json::from_str::<ExtractedColors>(json_str.trim()) {
                            return parsed;
                        }
                    }
                }
            }
        }

        ExtractedColors::default()
    }
}

fn dirs_home() -> PathBuf {
    env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/home/rover"))
}
