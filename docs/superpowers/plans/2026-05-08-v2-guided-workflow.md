# v2.0.0 Guided Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dodati guided onboarding, live diagnostics pregled i vodjeni repair tok na Windows i Linux strani.

**Architecture:** Shared status i next-action logika ostaje u `scripts/local_qwen_runtime.py`, dok Windows WinForms i Linux TUI samo renderuju isti payload na svoj nacin. Diagnostics export i UI pregled koriste iste state/log izvore da nema razlaza izmedju "sta se vidi" i "sta se zipuje".

**Tech Stack:** Python 3, PowerShell WinForms, Bash TUI, existing release automation.

---

### Task 1: Shared guided state payload

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\scripts\local_qwen_runtime.py`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_runtime_engine.py`

- [ ] Write failing tests for onboarding and next-step payload
- [ ] Run `python -m unittest .\tests\test_runtime_engine.py` and verify failure
- [ ] Implement minimal shared commands in `local_qwen_runtime.py`
- [ ] Run `python -m unittest .\tests\test_runtime_engine.py` and verify pass

### Task 2: Windows guided UI

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\local-qwen-common.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\control-center.ps1`

- [ ] Add shared onboarding/diagnostics access helpers
- [ ] Add richer onboarding and diagnostics sections in Control Center
- [ ] Run PowerShell parser checks

### Task 3: Linux guided TUI

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\local_qwen_common.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\export-diagnostics.sh`

- [ ] Surface the same shared status and next-action information in TUI
- [ ] Enrich diagnostics metadata with live status
- [ ] Run `bash -n` checks

### Task 4: Docs and release

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\README.md`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\docs\installers.md`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\release-notes.txt`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\version.json`

- [ ] Update docs and release notes
- [ ] Run tests and parser checks again
- [ ] Commit
- [ ] Run `powershell -ExecutionPolicy Bypass -File .\packaging\release-all.ps1 -Version 2.0.0`
