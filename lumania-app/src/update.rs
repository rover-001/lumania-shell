use serde::Deserialize;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct Manifest {
    pub name: String,
    pub version: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum UpdateStatus {
    Idle,
    Checking,
    UpToDate,
    UpdateAvailable(usize),
    DirtyWorktree,
    Updating,
    Success(String),
    Failed(String),
}

#[derive(Debug, Clone)]
pub struct UpdateManager {
    pub project_dir: PathBuf,
    pub current_version: String,
    pub current_commit: String,
    pub commit_message: String,
    pub status: UpdateStatus,
    pub logs: Vec<String>,
}

impl UpdateManager {
    pub fn new() -> Self {
        let project_dir = Self::find_project_dir();
        let (version, _) = Self::read_manifest(&project_dir);
        let commit = Self::run_git(&project_dir, &["rev-parse", "--short", "HEAD"])
            .unwrap_or_else(|_| "unknown".into());
        let message = Self::run_git(&project_dir, &["log", "-1", "--pretty=%s"])
            .unwrap_or_else(|_| "Lumania Shell release".into());

        Self {
            project_dir,
            current_version: version,
            current_commit: commit,
            commit_message: message,
            status: UpdateStatus::Idle,
            logs: Vec::new(),
        }
    }

    pub fn find_project_dir() -> PathBuf {
        let home = env::var("HOME").unwrap_or_else(|_| "/home/rover".into());
        let candidates = [
            PathBuf::from("."),
            PathBuf::from(".."),
            PathBuf::from(format!("{}/Projects/lumania shell", home)),
            PathBuf::from(format!("{}/.config/omarchy/plugins/lumania.island", home)),
        ];

        for c in candidates {
            if c.join("manifest.json").exists() && c.join("DynamicIsland.qml").exists() {
                if let Ok(canon) = fs::canonicalize(&c) {
                    return canon;
                }
                return c;
            }
        }
        PathBuf::from(format!("{}/Projects/lumania shell", home))
    }

    pub fn read_manifest(dir: &PathBuf) -> (String, String) {
        let path = dir.join("manifest.json");
        if let Ok(content) = fs::read_to_string(path) {
            if let Ok(manifest) = serde_json::from_str::<Manifest>(&content) {
                return (manifest.version, manifest.name);
            }
        }
        ("0.1.1".into(), "Lumania Island".into())
    }

    pub fn check_for_updates(&mut self) {
        self.status = UpdateStatus::Checking;
        self.logs.push("Fetching latest updates from remote...".into());

        // Check if git directory exists
        if !self.project_dir.join(".git").exists() {
            self.status = UpdateStatus::Failed("Not a git checkout directory".into());
            return;
        }

        // Check dirty status
        if let Ok(status_out) = Self::run_git(&self.project_dir, &["status", "--porcelain"]) {
            if !status_out.trim().is_empty() {
                // If dirty, note it
                self.logs.push("Local modifications detected in workspace.".into());
            }
        }

        // Fetch origin
        match Self::run_git(&self.project_dir, &["fetch", "--quiet", "origin"]) {
            Ok(_) => {
                let behind_count = Self::run_git(&self.project_dir, &["rev-list", "--count", "HEAD..origin/main"])
                    .ok()
                    .and_then(|s| s.trim().parse::<usize>().ok())
                    .unwrap_or(0);

                if behind_count > 0 {
                    self.status = UpdateStatus::UpdateAvailable(behind_count);
                    self.logs.push(format!("Found {} new commit(s) on origin/main.", behind_count));
                } else {
                    self.status = UpdateStatus::UpToDate;
                    self.logs.push("Lumania Shell is up to date on origin/main.".into());
                }
            }
            Err(e) => {
                self.status = UpdateStatus::Failed(format!("Fetch failed: {}", e));
            }
        }
    }

    pub fn perform_update(&mut self) {
        self.status = UpdateStatus::Updating;
        self.logs.push("Starting Lumania Shell update...".into());

        // Step 1: Pull
        self.logs.push("Pulling latest commits from origin/main...".into());
        match Self::run_git(&self.project_dir, &["pull", "--ff-only", "origin", "main"]) {
            Ok(out) => {
                self.logs.push(format!("Git pull: {}", out.trim()));
            }
            Err(e) => {
                self.status = UpdateStatus::Failed(format!("Git pull failed: {}", e));
                return;
            }
        }

        // Step 2: Run build.sh
        self.logs.push("Rebuilding native helpers (visualizer, colors, status)...".into());
        let build_sh = self.project_dir.join("build.sh");
        if build_sh.exists() {
            match Command::new("bash").arg(build_sh).current_dir(&self.project_dir).output() {
                Ok(out) => {
                    if out.status.success() {
                        self.logs.push("Native helpers compiled successfully.".into());
                    } else {
                        let err = String::from_utf8_lossy(&out.stderr);
                        self.logs.push(format!("build.sh warning/error: {}", err.trim()));
                    }
                }
                Err(e) => {
                    self.logs.push(format!("Failed to run build.sh: {}", e));
                }
            }
        }

        // Step 3: Restart Omarchy Shell
        self.logs.push("Reloading Omarchy shell bar...".into());
        match Command::new("omarchy").args(["restart", "shell"]).output() {
            Ok(_) => {
                self.logs.push("Omarchy shell restarted successfully.".into());
            }
            Err(e) => {
                self.logs.push(format!("Note: omarchy restart shell returned: {}", e));
            }
        }

        // Update version and commit in state
        let (v, _) = Self::read_manifest(&self.project_dir);
        self.current_version = v;
        self.current_commit = Self::run_git(&self.project_dir, &["rev-parse", "--short", "HEAD"])
            .unwrap_or_else(|_| "unknown".into());

        self.status = UpdateStatus::Success("Update complete! Shell is running latest build.".into());
    }

    fn run_git(dir: &PathBuf, args: &[&str]) -> Result<String, String> {
        let output = Command::new("git")
            .args(args)
            .current_dir(dir)
            .output()
            .map_err(|e| format!("git error: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }
}
