# PS GUI Framework

A modern, high-performance PowerShell GUI framework for building **real desktop applications**, not one-off scripts.

Designed as an application shell with async execution, centralized state, theming, logging, and extensibility — while keeping the UI responsive and clean.

---

## What It Provides

- Non-blocking async tasks using runspaces  
- Thread-safe UI updates  
- Centralized shared state  
- UI + file logging  
- Dynamic theming  
- Layout-safe WinForms composition  

---

## Visual Layout Designer (Experimental)

Includes an interactive layout designer that allows:

- Toggling design mode at runtime  
- Dragging and resizing controls  
- Exporting layouts to JSON  
- Reloading saved layouts  

Enables fast UI prototyping without rewriting layout code.

---

## Usage

```powershell
irm https://raw.githubusercontent.com/likeBloodMoon/ps-gui-framework/main/ps-gui-framework.ps1 | iex
```

For production use, download and review the script locally.

---

## Status

Active development. APIs may change.

## License

MIT License
