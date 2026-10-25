@echo off
copy /Y "%~dp0evpn_guard.ps1" "%TEMP%\evpn_guard.ps1" >nul
start "" msedge.exe --new-window "https://evpn.gbe.kr" "https://gbe.neis.go.kr"
powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%TEMP%\evpn_guard.ps1\"' -Verb RunAs"