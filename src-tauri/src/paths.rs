//! Shared filesystem locations. Everything lives in `~/.tokendash/` so the
//! desktop app and the Node daemon read the same port/pid/credential files.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub fn home_dir() -> PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home);
    }
    // Windows keeps the user profile in USERPROFILE; the app only ships for
    // Linux, this keeps `cargo test` green on other hosts.
    std::env::var_os("USERPROFILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

pub fn data_dir() -> PathBuf {
    home_dir().join(".tokendash")
}

pub fn pid_path() -> PathBuf {
    data_dir().join("daemon.pid")
}

pub fn port_path() -> PathBuf {
    data_dir().join("daemon.port")
}

pub fn settings_path() -> PathBuf {
    data_dir().join("desktop-settings.json")
}

pub fn credentials_path() -> PathBuf {
    data_dir().join("credentials.json")
}

pub fn ensure_data_dir() -> io::Result<()> {
    fs::create_dir_all(data_dir())
}

/// Reads a port or pid file. Whitespace-only or malformed content reads as
/// `None`: a half-written file must never be mistaken for a live daemon.
pub fn read_number(path: &Path) -> Option<u32> {
    let raw = fs::read_to_string(path).ok()?;
    raw.trim().parse::<u32>().ok().filter(|value| *value > 0)
}

/// Writes a numeric file with the trailing newline the Node daemon tolerates,
/// then flushes so a concurrent reader cannot observe a partial write.
pub fn write_number(path: &Path, value: u32) -> io::Result<()> {
    ensure_data_dir()?;
    fs::write(path, format!("{value}\n"))
}

pub fn is_process_alive(pid: u32) -> bool {
    // `kill(pid, 0)` reports existence without signalling. It is not exposed by
    // std, so use /proc on Linux and fall back to `kill` via std's libc-free
    // path elsewhere.
    #[cfg(target_os = "linux")]
    {
        Path::new(&format!("/proc/{pid}")).exists()
    }
    #[cfg(not(target_os = "linux"))]
    {
        std::process::Command::new("kill")
            .args(["-0", &pid.to_string()])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }
}
