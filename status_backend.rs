use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

fn run_cmd(args: &[&str]) -> String {
    if args.is_empty() {
        return String::new();
    }
    match Command::new(args[0]).args(&args[1..]).output() {
        Ok(out) => String::from_utf8_lossy(&out.stdout).to_string(),
        Err(_) => String::new(),
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ => out.push(c),
        }
    }
    out
}

fn get_active_wifi_interface() -> String {
    let out = run_cmd(&["ip", "route", "show", "default"]);
    for part in out.split_whitespace().collect::<Vec<_>>().windows(2) {
        if part[0] == "dev" {
            return part[1].to_string();
        }
    }
    "wlo1".to_string()
}

struct WifiNetwork {
    ssid: String,
    signal: u32,
    security: String,
    active: bool,
}

struct WifiStatus {
    enabled: bool,
    connected: bool,
    ssid: String,
    ip: String,
    signal: u32,
    networks: Vec<WifiNetwork>,
}

fn get_wifi_status(iface: &str) -> WifiStatus {
    let radio_out = run_cmd(&["nmcli", "radio", "wifi"]);
    let enabled = radio_out.trim() == "enabled";

    if !enabled {
        return WifiStatus {
            enabled: false,
            connected: false,
            ssid: String::new(),
            ip: String::new(),
            signal: 0,
            networks: Vec::new(),
        };
    }

    let out = run_cmd(&[
        "nmcli", "-t", "-f", "in-use,ssid,signal,security",
        "dev", "wifi", "list"
    ]);

    let mut networks: Vec<WifiNetwork> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    let mut connected_ssid = String::new();
    let mut connected_signal = 0;

    for line in out.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let is_active = line.starts_with('*');
        let rest = if is_active {
            line.strip_prefix("*:").unwrap_or(line)
        } else {
            line.strip_prefix(":").unwrap_or(line)
        };

        let parts: Vec<&str> = rest.split(':').collect();
        if parts.len() >= 2 {
            let ssid = parts[0].replace("\\:", ":").trim().to_string();
            if ssid.is_empty() {
                continue;
            }
            let signal = parts[1].trim().parse::<u32>().unwrap_or(50);
            let sec = if parts.len() >= 3 { parts[2].trim().to_string() } else { String::new() };

            if is_active && connected_ssid.is_empty() {
                connected_ssid = ssid.clone();
                connected_signal = signal;
            }

            if !seen.contains(&ssid) {
                seen.insert(ssid.clone());
                networks.push(WifiNetwork {
                    ssid,
                    signal,
                    security: sec,
                    active: is_active,
                });
            }
        }
    }

    // Sort: active first, then highest signal
    networks.sort_by(|a, b| {
        b.active.cmp(&a.active).then_with(|| b.signal.cmp(&a.signal))
    });

    let mut connected_ip = String::new();
    if !connected_ssid.is_empty() {
        let ip_out = run_cmd(&["ip", "-4", "-o", "addr", "show", iface]);
        for token in ip_out.split_whitespace().collect::<Vec<_>>().windows(2) {
            if token[0] == "inet" {
                if let Some(ip) = token[1].split('/').next() {
                    connected_ip = ip.to_string();
                    break;
                }
            }
        }
    }

    let is_connected = !connected_ssid.is_empty();

    WifiStatus {
        enabled: true,
        connected: is_connected,
        ssid: connected_ssid,
        ip: connected_ip,
        signal: connected_signal,
        networks,
    }
}

struct BtDevice {
    mac: String,
    name: String,
    connected: bool,
    paired: bool,
    icon: String,
}

struct BtStatus {
    enabled: bool,
    connected_count: usize,
    devices: Vec<BtDevice>,
}

fn get_bluetooth_status() -> BtStatus {
    let show_out = run_cmd(&["bluetoothctl", "show"]);
    let enabled = show_out.contains("Powered: yes");

    if !enabled {
        return BtStatus {
            enabled: false,
            connected_count: 0,
            devices: Vec::new(),
        };
    }

    let connected_out = run_cmd(&["bluetoothctl", "devices", "Connected"]);
    let mut connected_macs: HashSet<String> = HashSet::new();
    for line in connected_out.lines() {
        if line.starts_with("Device ") {
            let parts: Vec<&str> = line.splitn(3, ' ').collect();
            if parts.len() >= 2 {
                connected_macs.insert(parts[1].trim().to_uppercase());
            }
        }
    }

    let paired_out = run_cmd(&["bluetoothctl", "devices", "Paired"]);
    let all_devices_out = run_cmd(&["bluetoothctl", "devices"]);
    let mut devices: Vec<BtDevice> = Vec::new();
    let mut seen_macs: HashSet<String> = HashSet::new();

    let mut paired_macs: HashSet<String> = HashSet::new();
    for line in paired_out.lines() {
        if line.starts_with("Device ") {
            let parts: Vec<&str> = line.splitn(3, ' ').collect();
            if parts.len() >= 2 {
                paired_macs.insert(parts[1].trim().to_uppercase());
            }
        }
    }

    // Helper closure to process lines and append devices
    let mut process_lines = |lines: &str| {
        for line in lines.lines() {
            if line.starts_with("Device ") {
                let parts: Vec<&str> = line.splitn(3, ' ').collect();
                if parts.len() >= 3 {
                    let mac = parts[1].trim().to_string();
                    let mac_upper = mac.to_uppercase();
                    let name = parts[2].trim().to_string();
                    // Unnamed BLE beacons surface as their own MAC; skip the noise
                    let mac_dashed = mac_upper.replace(':', "-");
                    if name.is_empty() || name == mac_dashed || name == mac_upper {
                        continue;
                    }
                    if !seen_macs.contains(&mac_upper) {
                        seen_macs.insert(mac_upper.clone());
                        let conn = connected_macs.contains(&mac_upper);
                        let is_paired = paired_macs.contains(&mac_upper);
                        let lname = name.to_lowercase();
                        let icon = if lname.contains("buds") || lname.contains("headphone") || lname.contains("ear") || lname.contains("airpod") {
                            "headset"
                        } else if lname.contains("gamepad") || lname.contains("controller") || lname.contains("one s") {
                            "gamepad"
                        } else if lname.contains("phone") || lname.contains("realme") || lname.contains("iphone") || lname.contains("galaxy") {
                            "phone"
                        } else if lname.contains("mouse") {
                            "mouse"
                        } else if lname.contains("keyboard") {
                            "keyboard"
                        } else {
                            "headset"
                        };

                        devices.push(BtDevice {
                            mac,
                            name,
                            connected: conn,
                            paired: is_paired,
                            icon: icon.to_string(),
                        });
                    }
                }
            }
        }
    };

    // 1. First add connected devices (highest priority)
    process_lines(&connected_out);

    // 2. Add all paired devices
    process_lines(&paired_out);

    // 3. Add all other known / trusted / discovered devices
    process_lines(&all_devices_out);

    let connected_count = connected_macs.len();

    BtStatus {
        enabled: true,
        connected_count,
        devices,
    }
}

struct DnsStatus {
    current: String,
    preset: String,
    dot: bool,
}

struct BatteryStatus {
    present: bool,
    capacity: u32,
    charging: bool,
    plugged: bool,
}

fn get_dns_status(iface: &str) -> DnsStatus {
    let mut current_dns = String::new();
    let dns_out = run_cmd(&["resolvectl", "dns", iface]);
    if let Some(pos) = dns_out.find(':') {
        current_dns = dns_out[pos + 1..].trim().to_string();
    }

    if current_dns.is_empty() {
        let status_out = run_cmd(&["resolvectl", "status"]);
        for line in status_out.lines() {
            if line.contains("Current DNS Server:") {
                if let Some(pos) = line.find("Current DNS Server:") {
                    current_dns = line[pos + 19..].trim().to_string();
                    break;
                }
            }
        }
    }

    if current_dns.is_empty() {
        current_dns = "8.8.8.8".to_string();
    }

    let preset = if current_dns.contains("1.1.1.1") || current_dns.contains("1.0.0.1") {
        "cloudflare"
    } else if current_dns.contains("8.8.8.8") || current_dns.contains("8.8.4.4") {
        "google"
    } else if current_dns.contains("9.9.9.9") {
        "quad9"
    } else if current_dns.contains("94.140.14.14") {
        "adguard"
    } else if current_dns.starts_with("10.") || current_dns.starts_with("192.168.") {
        "dhcp"
    } else {
        "custom"
    };

    DnsStatus {
        current: current_dns,
        preset: preset.to_string(),
        dot: true,
    }
}

// ===========================================================================
// Battery Status (native sysfs telemetry, no external binaries)
// ===========================================================================
fn get_battery_status() -> BatteryStatus {
    let mut battery = BatteryStatus {
        present: false,
        capacity: 0,
        charging: false,
        plugged: false,
    };

    let base = Path::new("/sys/class/power_supply");
    let entries = match fs::read_dir(base) {
        Ok(e) => e,
        Err(_) => return battery,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        let kind = fs::read_to_string(path.join("type")).unwrap_or_default();
        let is_battery =
            kind.trim().eq_ignore_ascii_case("battery") || name.to_uppercase().starts_with("BAT");

        if !is_battery {
            continue;
        }

        if let Ok(cap) = fs::read_to_string(path.join("capacity")) {
            if let Ok(value) = cap.trim().parse::<u32>() {
                battery.present = true;
                battery.capacity = value.min(100);
            }
        }

        let state = fs::read_to_string(path.join("status")).unwrap_or_default();
        let state = state.trim();
        battery.charging = state == "Charging" || state == "Full";
        battery.plugged = battery.charging || state == "Not charging";

        if battery.present {
            break;
        }
    }

    battery
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let iface = get_active_wifi_interface();

    if args.len() > 1 {
        let cmd = &args[1];
        match cmd.as_str() {
            "--toggle-wifi" => {
                let target = if args.len() > 2 {
                    if args[2] == "on" || args[2] == "true" { "on" } else { "off" }
                } else {
                    let cur = run_cmd(&["nmcli", "radio", "wifi"]);
                    if cur.trim() == "enabled" { "off" } else { "on" }
                };
                let _ = Command::new("nmcli").args(["radio", "wifi", target]).status();
                return;
            }
            "--connect-wifi" => {
                if args.len() > 2 {
                    let _ = Command::new("nmcli").args(["dev", "wifi", "connect", &args[2]]).status();
                }
                return;
            }
            "--disconnect-wifi" => {
                if args.len() > 2 && !args[2].is_empty() {
                    let _ = Command::new("nmcli").args(["con", "down", "id", &args[2]]).status();
                } else {
                    let _ = Command::new("nmcli").args(["dev", "disconnect", &iface]).status();
                }
                return;
            }
            "--rescan-wifi" => {
                let _ = Command::new("nmcli").args(["dev", "wifi", "rescan"]).status();
                return;
            }
            "--toggle-bt" => {
                let target = if args.len() > 2 {
                    if args[2] == "on" || args[2] == "true" { "on" } else { "off" }
                } else {
                    let show = run_cmd(&["bluetoothctl", "show"]);
                    if show.contains("Powered: yes") { "off" } else { "on" }
                };
                let _ = Command::new("bluetoothctl").args(["power", target]).status();
                return;
            }
            "--connect-bt" => {
                if args.len() > 2 {
                    let _ = Command::new("bluetoothctl").args(["connect", &args[2]]).status();
                }
                return;
            }
            "--disconnect-bt" => {
                if args.len() > 2 {
                    let _ = Command::new("bluetoothctl").args(["disconnect", &args[2]]).status();
                }
                return;
            }
            "--scan-bt" => {
                // Active discovery so nearby, not-yet-paired devices surface too.
                let _ = Command::new("bluetoothctl")
                    .args(["--timeout", "6", "scan", "on"])
                    .status();
                return;
            }
            "--set-dns" => {
                if args.len() > 2 {
                    let preset = &args[2];
                    match preset.as_str() {
                        "cloudflare" => {
                            let _ = Command::new("resolvectl").args(["dns", &iface, "1.1.1.1", "1.0.0.1"]).status();
                        }
                        "google" => {
                            let _ = Command::new("resolvectl").args(["dns", &iface, "8.8.8.8", "8.8.4.4"]).status();
                        }
                        "quad9" => {
                            let _ = Command::new("resolvectl").args(["dns", &iface, "9.9.9.9", "149.112.112.112"]).status();
                        }
                        "adguard" => {
                            let _ = Command::new("resolvectl").args(["dns", &iface, "94.140.14.14", "94.140.15.15"]).status();
                        }
                        "dhcp" => {
                            let _ = Command::new("resolvectl").args(["revert", &iface]).status();
                        }
                        custom => {
                            let _ = Command::new("resolvectl").args(["dns", &iface, custom]).status();
                        }
                    }
                }
                return;
            }
            _ => {}
        }
    }

    // Default: output JSON telemetry
    let wifi = get_wifi_status(&iface);
    let bt = get_bluetooth_status();
    let dns = get_dns_status(&iface);
    let battery = get_battery_status();

    let mut json = String::with_capacity(2048);
    json.push('{');

    // Wifi
    json.push_str("\"wifi\":{");
    json.push_str(&format!("\"enabled\":{},", wifi.enabled));
    json.push_str(&format!("\"connected\":{},", wifi.connected));
    json.push_str(&format!("\"ssid\":\"{}\",", json_escape(&wifi.ssid)));
    json.push_str(&format!("\"ip\":\"{}\",", json_escape(&wifi.ip)));
    json.push_str(&format!("\"signal\":{},", wifi.signal));
    json.push_str("\"networks\":[");
    for (i, net) in wifi.networks.iter().take(12).enumerate() {
        if i > 0 { json.push(','); }
        json.push_str(&format!(
            "{{\"ssid\":\"{}\",\"signal\":{},\"security\":\"{}\",\"active\":{}}}",
            json_escape(&net.ssid),
            net.signal,
            json_escape(&net.security),
            net.active
        ));
    }
    json.push_str("]},");

    // Bluetooth
    json.push_str("\"bluetooth\":{");
    json.push_str(&format!("\"enabled\":{},", bt.enabled));
    json.push_str(&format!("\"connectedCount\":{},", bt.connected_count));
    json.push_str("\"devices\":[");
    for (i, dev) in bt.devices.iter().take(10).enumerate() {
        if i > 0 { json.push(','); }
        json.push_str(&format!(
            "{{\"mac\":\"{}\",\"name\":\"{}\",\"connected\":{},\"paired\":{},\"icon\":\"{}\"}}",
            json_escape(&dev.mac),
            json_escape(&dev.name),
            dev.connected,
            dev.paired,
            json_escape(&dev.icon)
        ));
    }
    json.push_str("]},");

    // DNS
    json.push_str("\"dns\":{");
    json.push_str(&format!("\"current\":\"{}\",", json_escape(&dns.current)));
    json.push_str(&format!("\"preset\":\"{}\",", json_escape(&dns.preset)));
    json.push_str(&format!("\"dot\":{}", dns.dot));
    json.push_str("},");

    // Battery
    json.push_str("\"battery\":{");
    json.push_str(&format!("\"present\":{},", battery.present));
    json.push_str(&format!("\"capacity\":{},", battery.capacity));
    json.push_str(&format!("\"charging\":{},", battery.charging));
    json.push_str(&format!("\"plugged\":{}", battery.plugged));
    json.push_str("}}");

    println!("{}", json);
}
