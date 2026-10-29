@echo off
chcp 65001 >nul
title EVPN Dedicated Edge Launcher
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0evpn_guard.ps1"
