use serde::{Deserialize, Serialize};
use std::net::{SocketAddr, TcpStream};
use std::os::windows::process::CommandExt;
use std::process::Command;
use std::time::Duration;

const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct RawNetInfo {
    pub physical_gateway: String,
    pub physical_if: u32,
    pub vpn_gateway: Option<String>,
    pub vpn_if: Option<u32>,
    pub evpn_connected: bool,
    pub split_active: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SystemStatus {
    pub internet_ok: bool,
    pub neis_ok: bool,
    pub evpn_connected: bool,
    pub split_active: bool,
    pub physical_gw: String,
    pub vpn_gw: String,
}

fn test_tcp(addr: &str, timeout_ms: u64) -> bool {
    if let Ok(socket_addr) = addr.parse::<SocketAddr>() {
        TcpStream::connect_timeout(&socket_addr, Duration::from_millis(timeout_ms)).is_ok()
    } else {
        false
    }
}

#[tauri::command]
async fn get_status() -> Result<SystemStatus, String> {
    // 1. Fast TCP connectivity checks
    let internet_ok = test_tcp("1.1.1.1:53", 1000) || test_tcp("8.8.8.8:53", 1000);
    let neis_ok = test_tcp("103.138.229.194:443", 1000);

    // 2. PowerShell network inspection
    let ps_script = r#"
        $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Where-Object { $_.NextHop -ne '0.0.0.0' }
        $phy = $routes | Where-Object { $_.InterfaceAlias -notmatch 'TAP|VPN|PPP|Secuway|AXGATE' -and $_.NextHop -notmatch '^10\.' } | Sort-Object RouteMetric | Select-Object -First 1
        $vpn = $routes | Where-Object { $_.InterfaceAlias -match 'TAP|VPN|PPP|Secuway|AXGATE' -or $_.NextHop -match '^10\.' } | Select-Object -First 1
        $hasSplitRoute = [bool](Get-NetRoute -DestinationPrefix '103.138.0.0/16' -ErrorAction SilentlyContinue)

        [PSCustomObject]@{
            physical_gateway = if ($phy) { $phy.NextHop } else { "" }
            physical_if = if ($phy) { $phy.InterfaceIndex } else { 0 }
            vpn_gateway = if ($vpn) { $vpn.NextHop } else { $null }
            vpn_if = if ($vpn) { $vpn.InterfaceIndex } else { $null }
            evpn_connected = ($null -ne $vpn)
            split_active = $hasSplitRoute
        } | ConvertTo-Json -Compress
    "#;

    let output = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", ps_script])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|e| format!("PowerShell 실행 실패: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let info: RawNetInfo = serde_json::from_str(stdout.trim())
        .map_err(|e| format!("JSON 파싱 실패 ({}): {}", stdout, e))?;

    Ok(SystemStatus {
        internet_ok,
        neis_ok,
        evpn_connected: info.evpn_connected,
        split_active: info.split_active,
        physical_gw: info.physical_gateway,
        vpn_gw: info.vpn_gateway.unwrap_or_else(|| "미감지".to_string()),
    })
}

#[tauri::command]
async fn apply_split_routing() -> Result<String, String> {
    let script = r#"
        $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Where-Object { $_.NextHop -ne '0.0.0.0' }
        $phy = $routes | Where-Object { $_.InterfaceAlias -notmatch 'TAP|VPN|PPP|Secuway|AXGATE' -and $_.NextHop -notmatch '^10\.' } | Sort-Object RouteMetric | Select-Object -First 1
        $vpn = $routes | Where-Object { $_.InterfaceAlias -match 'TAP|VPN|PPP|Secuway|AXGATE' -or $_.NextHop -match '^10\.' } | Select-Object -First 1

        if (-not $phy) {
            throw "물리 게이트웨이를 찾을 수 없습니다."
        }

        $phyGw = $phy.NextHop
        $phyIf = $phy.InterfaceIndex

        # 0.0.0.0/0 물리 게이트웨이 복원
        route change 0.0.0.0 mask 0.0.0.0 $phyGw metric 1 if $phyIf

        # 교육청 및 나이스 대역 보존
        $targetGw = if ($vpn) { $vpn.NextHop } else { $phyGw }
        $targetIf = if ($vpn) { $vpn.InterfaceIndex } else { $phyIf }

        route add 10.0.0.0 mask 255.0.0.0 $targetGw metric 10 if $targetIf 2>$null
        route add 103.138.0.0 mask 255.255.0.0 $targetGw metric 10 if $targetIf 2>$null
        route add 203.190.0.0 mask 255.255.0.0 $targetGw metric 10 if $targetIf 2>$null

        Write-Output "스마트 라우팅 적용 완료"
    "#;

    let output = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|e| format!("적용 실패: {}", e))?;

    if output.status.success() {
        Ok("스마트 분할 라우팅이 성공적으로 적용되었습니다.".to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

#[tauri::command]
async fn restore_routing() -> Result<String, String> {
    let script = r#"
        route delete 10.0.0.0 mask 255.0.0.0 2>$null
        route delete 103.138.0.0 mask 255.255.0.0 2>$null
        route delete 203.190.0.0 mask 255.255.0.0 2>$null
        Write-Output "복원 완료"
    "#;

    let _ = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .creation_flags(CREATE_NO_WINDOW)
        .output();

    Ok("네트워크 라우팅이 원래대로 복원되었습니다.".to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_status,
            apply_split_routing,
            restore_routing
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

