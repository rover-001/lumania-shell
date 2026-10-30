use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LumaniaSettings {
    #[serde(rename = "borderThickness")]
    pub border_thickness: u32,

    #[serde(rename = "dynamicWallpaperColor")]
    pub dynamic_wallpaper_color: bool,

    #[serde(rename = "wallpaperColorMode")]
    pub wallpaper_color_mode: String,

    #[serde(rename = "borderColor")]
    pub border_color: String,

    #[serde(rename = "cornerStyle")]
    pub corner_style: String,

    #[serde(rename = "cornerRadius")]
    pub corner_radius: u32,

    #[serde(rename = "islandBodyWidth")]
    pub island_body_width: u32,

    #[serde(rename = "wallpaperInstantSwitch")]
    pub wallpaper_instant_switch: bool,

    #[serde(rename = "wallpaperMaxVisibleThumbs")]
    pub wallpaper_max_visible_thumbs: u32,
}

impl Default for LumaniaSettings {
    fn default() -> Self {
        Self {
            border_thickness: 5,
            dynamic_wallpaper_color: true,
            wallpaper_color_mode: "accent".into(),
            border_color: "#ba5f58".into(),
            corner_style: "squircle".into(),
            corner_radius: 16,
            island_body_width: 206,
            wallpaper_instant_switch: false,
            wallpaper_max_visible_thumbs: 7,
        }
    }
}

impl LumaniaSettings {
    pub fn config_path() -> PathBuf {
        let home = env::var("HOME").unwrap_or_else(|_| "/home/rover".into());
        PathBuf::from(home).join(".config/omarchy/lumania.json")
    }

    pub fn load() -> Self {
        let path = Self::config_path();
        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(settings) = serde_json::from_str::<LumaniaSettings>(&content) {
                    return settings;
                }
            }
        }
        Self::default()
    }

    pub fn save(&self) -> Result<(), String> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| format!("Serialization error: {}", e))?;
        fs::write(&path, json).map_err(|e| format!("Failed to write config: {}", e))?;
        Ok(())
    }

    pub fn restart_shell() -> Result<String, String> {
        let output = Command::new("omarchy")
            .args(["restart", "shell"])
            .output()
            .map_err(|e| format!("Failed to run omarchy restart shell: {}", e))?;

        if output.status.success() {
            Ok("Lumania shell restarted successfully".into())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }
}
