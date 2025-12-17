# PS GUI Framework

A high‑performance PowerShell GUI framework for building modern, extensible desktop tools that **do not feel like PowerShell**.

This project is designed as an **application shell**, not a one‑off script UI. It provides async execution, centralized state, theming, logging, and an extensible architecture suitable for real tools and platforms.

---

## What This Is

PS GUI Framework is a foundation for:

- Diagnostic and monitoring tools  
- System utilities and dashboards  
- Plugin‑driven PowerShell applications  
- Long‑running GUI tools with background workers  
- Developer‑grade internal tooling  

It focuses on **responsiveness, structure, and reuse**.

---

## Core Capabilities

- Non‑blocking async task execution using runspaces  
- Thread‑safe UI updates from background workers  
- Centralized shared state store  
- Structured logging (UI + file)  
- Dynamic theming system  
- Layout‑safe WinForms composition  
- Graceful shutdown and cleanup  

---

## New: Visual Layout Designer (Experimental)

This release introduces an **interactive layout designer** built directly into PowerShell.

The designer allows UI layouts to be visually arranged at runtime and exported for reuse.

Capabilities include:

- Design mode toggle  
- Drag and resize panels and controls  
- Live layout preview  
- Export layout to JSON  
- Load saved layouts at startup  

This enables rapid UI prototyping without rewriting layout code.

> The layout designer is experimental and intended for advanced users and internal tools.

---

## Architecture Philosophy

- UI thread stays clean and responsive  
- All heavy work runs in managed runspaces  
- State is explicit and observable  
- Framework code is separated from app logic  
- Everything is inspectable and debuggable  

This is **not** a drag‑and‑drop toy framework. It is built for people who care about correctness and control.

---

## Usage

Download the framework script and run it directly, or integrate it into your own tooling.

```powershell
irm https://raw.githubusercontent.com/likeBloodMoon/ps-gui-framework/main/ps-gui-framework.ps1 | iex
```

For production usage, downloading and reviewing the script locally is recommended.

---

## Intended Audience

- PowerShell developers building real GUI tools  
- Sysadmins who need long‑running interactive utilities  
- Developers prototyping internal Windows tools  
- Anyone pushing PowerShell beyond “scripts”  

---

## Status

Active development.  
APIs may evolve.  
Breaking changes are possible while major features are added.

---

## License

MIT License
