# PS GUI Framework

**PS GUI Framework** is a reusable PowerShell WinForms framework for building modern, borderless Windows desktop tools.  
It provides a stable layout, dark/light theming, async runspaces, logging, and status feedback without UI blocking or DPI issues.

---

## Features

- Borderless window with custom title bar
- Dark / Light theme toggle
- Responsive layout (no clipping on resize or DPI scaling)
- Async tasks using runspaces
- Centralized logging (UI + file)
- Status bar with progress indicator
- Optional notifications (BurntToast or tray fallback)

---

## Requirements

- Windows
- PowerShell 5.1 or PowerShell 7+

---

## Run

`irm https://raw.githubusercontent.com/likeBloodMoon/ps-gui-framework/refs/heads/main/ps-gui-framework.ps1 | iex`
