import React, { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";

interface SystemStatus {
  internet_ok: boolean;
  neis_ok: boolean;
  evpn_connected: boolean;
  split_active: boolean;
  physical_gw: string;
  vpn_gw: string;
}

export default function App() {
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [log, setLog] = useState("시스템 준비 완료. 상태를 확인 중입니다...");

  const refreshStatus = async () => {
    try {
      const res = await invoke<SystemStatus>("get_status");
      setStatus(res);
    } catch (e: any) {
      setLog(`상태 조회 오류: ${e}`);
    }
  };

  useEffect(() => {
    refreshStatus();
    const timer = setInterval(refreshStatus, 3000);
    return () => clearInterval(timer);
  }, []);

  const handleApplySplit = async () => {
    setLoading(true);
    setLog("스마트 분할 라우팅 적용 중...");
    try {
      const msg = await invoke<string>("apply_split_routing");
      setLog(msg);
      await refreshStatus();
    } catch (e: any) {
      setLog(`적용 실패: ${e}`);
    } finally {
      setLoading(false);
    }
  };

  const handleRestore = async () => {
    setLoading(true);
    setLog("네트워크 라우팅 원상 복구 중...");
    try {
      const msg = await invoke<string>("restore_routing");
      setLog(msg);
      await refreshStatus();
    } catch (e: any) {
      setLog(`복구 실패: ${e}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="container">
      <header className="header">
        <div className="title-group">
          <h1>⚡ GBE EVPN 스마트 워크스페이스</h1>
          <p>EVPN 전용망과 일반 초고속 인터넷 동시 연결</p>
        </div>
        <div className="badge">Tauri v2 Native</div>
      </header>

      {/* 상태 표시 대시보드 */}
      <div className="status-grid">
        <div className="status-card">
          <span className="status-label">일반 인터넷</span>
          <div className="status-value">
            <span className={`indicator ${status?.internet_ok ? "green" : "red"}`} />
            {status?.internet_ok ? "정상 (유튜브 OK)" : "차단됨"}
          </div>
        </div>

        <div className="status-card">
          <span className="status-label">경북 EVPN</span>
          <div className="status-value">
            <span className={`indicator ${status?.evpn_connected ? "green" : "red"}`} />
            {status?.evpn_connected ? "연결됨" : "미연결"}
          </div>
        </div>

        <div className="status-card">
          <span className="status-label">나이스 (NEIS)</span>
          <div className="status-value">
            <span className={`indicator ${status?.neis_ok ? "green" : "red"}`} />
            {status?.neis_ok ? "접속 가능" : "대기 중"}
          </div>
        </div>
      </div>

      {/* 원클릭 메인 액션 카드 */}
      <div className="hero-action">
        <p className="hero-desc">
          EVPN에 로그인한 후 아래 버튼을 누르면, 일반 인터넷 경로를 살려<br />
          나이스 업무와 유튜브·카카오톡을 동시에 사용할 수 있습니다.
        </p>

        {!status?.split_active ? (
          <button
            className="btn-hero enable"
            onClick={handleApplySplit}
            disabled={loading}
          >
            {loading ? "적용 중..." : "⚡ 스마트 분할 모드 활성화 (딸깍)"}
          </button>
        ) : (
          <button
            className="btn-hero disable"
            onClick={handleRestore}
            disabled={loading}
          >
            {loading ? "복구 중..." : "🔄 라우팅 원상 복구"}
          </button>
        )}
      </div>

      {/* 업무 포털 바로가기 */}
      <div className="portal-section">
        <div className="section-title">업무 포털 바로가기</div>
        <div className="portal-grid">
          <button
            className="portal-btn"
            onClick={() => openUrl("https://evpn.gbe.kr")}
          >
            <span className="portal-icon">🛡️</span>
            EVPN 로그인
          </button>
          <button
            className="portal-btn"
            onClick={() => openUrl("https://gbe.neis.go.kr")}
          >
            <span className="portal-icon">🏫</span>
            나이스 (NEIS)
          </button>
          <button
            className="portal-btn"
            onClick={() => openUrl("https://edufine.gbe.kr")}
          >
            <span className="portal-icon">📊</span>
            K-에듀파인
          </button>
        </div>
      </div>

      {/* 시스템 메시지 로그 */}
      <div className="log-box">
        💡 {log}
      </div>
    </div>
  );
}
