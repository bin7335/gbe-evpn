# 관리자 권한 확인 (미보유 시 관리자 권한으로 자동 승격 실행)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 콘솔 한글 인코딩 UTF-8 설정
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 엣지(Edge) EVPN 및 나이스 전용 창 자동 실행
Start-Process "msedge.exe" -ArgumentList '--new-window "https://evpn.gbe.kr" "https://gbe.neis.go.kr"' -ErrorAction SilentlyContinue

$Host.UI.RawUI.WindowTitle = "[켜두세요] EVPN 인터넷 동시접속 자동 가드 (크롬=일반인터넷 / 엣지=EVPN)"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  [EVPN 인터넷 동시접속 자동 가드 실행 중]" -ForegroundColor Cyan
Write-Host "  - 엣지(Edge)  : 경북 EVPN / 나이스 / 에듀파인 전용" -ForegroundColor Green
Write-Host "  - 크롬(Chrome): 일반 인터넷 (유튜브 / 카톡 / 검색) 전용" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# 어떤 컴퓨터에서든 실제 물리 인터넷(유선 LAN 또는 Wi-Fi) 어댑터와 게이트웨이를 자동 탐지
$phyCandidate = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Where-Object { $_.NextHop -ne '0.0.0.0' } |
    ForEach-Object {
        $adapter = Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapter -and $adapter.Status -eq 'Up' -and $adapter.InterfaceDescription -notmatch 'TAP-Windows|AXGATE|VPN|Secuway|SSL|Virtual|Hyper-V|Loopback') {
            $ipInterface = Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $totalMetric = $_.RouteMetric + $(if ($ipInterface) { $ipInterface.InterfaceMetric } else { 0 })
            [PSCustomObject]@{
                NextHop = $_.NextHop
                IfIndex = $_.InterfaceIndex
                Name    = $adapter.Name
                Desc    = $adapter.InterfaceDescription
                Metric  = $totalMetric
            }
        }
    } | Sort-Object Metric | Select-Object -First 1

if (-not $phyCandidate) {
    Write-Host "[오류] 현재 연결된 일반 인터넷(LAN/Wi-Fi) 게이트웨이를 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "EVPN 로그인 전에 이 프로그램을 먼저 실행하거나 인터넷 연결을 확인해 주세요." -ForegroundColor Yellow
    Read-Host "종료하려면 엔터를 누르세요"
    exit 1
}

$lanGw = $phyCandidate.NextHop
$lanIf = $phyCandidate.IfIndex
$lanName = "$($phyCandidate.Name) ($($phyCandidate.Desc))"

Write-Host "[확인] 이 PC의 기본 인터넷 통로 확보 완료!" -ForegroundColor Yellow
Write-Host "       - 랜카드: $lanName (인터페이스 #$lanIf)" -ForegroundColor Gray
Write-Host "       - 게이트웨이: $lanGw" -ForegroundColor Gray
Write-Host ""
Write-Host "[대기] 열린 엣지 창에서 EVPN에 로그인해 주세요. AXGATE 연결 시 자동으로 인터넷 차단을 해제합니다..." -ForegroundColor White
Write-Host ""

$wasConnected = $false

while ($true) {
    $tapAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'TAP-Windows|AXGATE|VPN' -or $_.Name -match '이더넷 2' } | Select-Object -First 1

    if ($tapAdapter -and $tapAdapter.Status -eq 'Up') {
        $vpnIf = $tapAdapter.ifIndex
        $vpnIpObj = Get-NetIPAddress -InterfaceIndex $vpnIf -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1

        $vpnRoutes = Get-NetRoute -InterfaceIndex $vpnIf -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne '0.0.0.0' }
        $vpnGw = if ($vpnRoutes) { ($vpnRoutes | Select-Object -First 1).NextHop } elseif ($vpnIpObj) {
            $parts = $vpnIpObj.IPAddress.Split('.')
            "$($parts[0]).$($parts[1]).$($parts[2]).1"
        } else { $null }

        $hijack0 = Get-NetRoute -InterfaceIndex $vpnIf -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
        $hijack1 = Get-NetRoute -InterfaceIndex $vpnIf -DestinationPrefix '0.0.0.0/1' -ErrorAction SilentlyContinue
        $hijack2 = Get-NetRoute -InterfaceIndex $vpnIf -DestinationPrefix '128.0.0.0/1' -ErrorAction SilentlyContinue

        if (-not $wasConnected -or $hijack0 -or $hijack1 -or $hijack2) {
            if ($vpnGw) {
                # 교육청/나이스 내부망 대역은 AXGATE 가상 랜카드로 고정
                route add 10.0.0.0 mask 255.0.0.0 $vpnGw metric 5 if $vpnIf 2>$null | Out-Null
                route add 103.138.0.0 mask 255.255.0.0 $vpnGw metric 5 if $vpnIf 2>$null | Out-Null
                route add 203.190.0.0 mask 255.255.0.0 $vpnGw metric 5 if $vpnIf 2>$null | Out-Null
            }

            # AXGATE의 전체 인터넷 가로채기 경로 제거
            if ($hijack0) { route delete 0.0.0.0 mask 0.0.0.0 $hijack0.NextHop 2>$null | Out-Null }
            if ($hijack1) { route delete 0.0.0.0 mask 128.0.0.0 2>$null | Out-Null }
            if ($hijack2) { route delete 128.0.0.0 mask 128.0.0.0 2>$null | Out-Null }

            # 일반 인터넷(0.0.0.0/0)을 원래 물리 랜카드로 최우선 복구
            route change 0.0.0.0 mask 0.0.0.0 $lanGw metric 1 if $lanIf 2>$null | Out-Null
            route add 0.0.0.0 mask 0.0.0.0 $lanGw metric 1 if $lanIf 2>$null | Out-Null
            Set-NetIPInterface -InterfaceIndex $lanIf -InterfaceMetric 1 -ErrorAction SilentlyContinue

            $timeStr = (Get-Date).ToString('HH:mm:ss')
            Write-Host "[$timeStr] [완료] AXGATE 인터넷 차단 자동 해제! (나이스 -> EVPN / 일반인터넷 -> $lanGw)" -ForegroundColor Green
            $wasConnected = $true
        }
    } else {
        if ($wasConnected) {
            $timeStr = (Get-Date).ToString('HH:mm:ss')
            Write-Host "[$timeStr] [안내] EVPN 연결이 종료되었습니다. 기본 인터넷 상태로 유지합니다." -ForegroundColor Yellow
            $wasConnected = $false
        }
    }
    Start-Sleep -Seconds 2
}
