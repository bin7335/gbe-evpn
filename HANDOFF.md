# EVPN 프로젝트 인수인계 문서 (HANDOFF)

- **최종 갱신**: 2026-10-25 23:02 (KST)
- **대상 프로젝트 경로**: `dev/EVPN/`
- **GitHub 저장소**: `https://github.com/bin7335/gbe-evpn` (Public)

---

## 1. 완료된 핵심 기능 (범용 원클릭 런처 & 실시간 라우팅 가드)

1. **`EVPN_Edge_Launcher.cmd` & `evpn_guard.ps1` (즉시 사용 가능)**:
   - 어떤 PC(유선 LAN / Wi-Fi 무관)에서든 실행 시 현재 물리 인터넷 어댑터와 게이트웨이를 자동 탐지하여 고정.
   - 엣지(Edge) 새 창으로 `evpn.gbe.kr` 및 `gbe.neis.go.kr`을 전용 실행.
   - 백그라운드 가드가 2초 주기로 AXGATE 가상 랜카드(`TAP-Windows Adapter V9`) 연결 및 라우팅 가로채기(`0.0.0.0/0`, `0.0.0.0/1`, `128.0.0.0/1`)를 감지해 즉시 물리 인터넷 경로(Metric 1)를 복구하고, 교육청/나이스 대역(`10.0.0.0/8`, `103.138.0.0/16`, `203.190.0.0/16`)은 AXGATE로 유지.
   - `%TEMP%\evpn_guard.ps1` 경유 방식으로 한글/공백 폴더 경로에서도 인코딩 오류 없이 작동.
2. **`Install_Desktop_Shortcut.cmd`**:
   - 다른 컴퓨터에 클론 후 실행 시 바탕화면에 `EVPN Dedicated Edge` 바로가기 아이콘 자동 생성.
3. **Tauri v2 (Rust + React) 데스크톱 UI 프로토타입 (`src/`, `src-tauri/`)**:
   - GUI 앱 형태로 확장할 수 있는 Tauri v2 스캐폴딩 포함.
