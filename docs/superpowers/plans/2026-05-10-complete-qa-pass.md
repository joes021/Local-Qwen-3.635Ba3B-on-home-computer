# Complete QA Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilizovati Local Qwen Home Computer tako da installer, update, repair, uninstall, Windows launcheri i Control Center rade konzistentno, a Linux ostane neoštećen.

**Architecture:** Rad ide u četiri QA talasa. Prvo se zatvaraju installer i lifecycle tokovi koji odlučuju koji fajlovi uopšte završavaju u `LocalQwenHome`, zatim se prolazi kroz Windows UI i launchere akciju po akciju, potom se proveravaju Linux regresije posle svakog većeg Windows fixa, i tek na kraju se pravi jedan čist release kandidat za ručni UX test.

**Tech Stack:** PowerShell, WinForms, Python unittest, Inno Setup, bash parse checks, GitHub release automation.

---

### Task 1: Installer / update / repair / uninstall baseline

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\install\windows\install.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\local-qwen-common.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\repair-install.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\uninstall.ps1`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_installer_packaging.py`

- [ ] Napisati/pojačati failing testove za slučajeve kada novi installer ne pregazi stare `launchers`, `release-notes.txt` i `version.json`.
- [ ] Pokrenuti `python -m unittest tests\test_windows_installer_packaging.py` i potvrditi da novi testovi padaju pre fixa.
- [ ] Implementirati agresivno osvežavanje Windows launchera/support fajlova pri install/update/repair toku.
- [ ] Proveriti `uninstall` parser i režime brisanja da više nema `param` i `switch` parse grešaka.
- [ ] Ponovo pokrenuti `python -m unittest tests\test_windows_installer_packaging.py` i potvrditi da prolazi.

### Task 2: TurboQuant dependency and report cleanup

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\install\windows\install.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\build-turboquant.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\local-qwen-common.ps1`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_installer_packaging.py`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_runtime_engine.py`

- [ ] Napisati test za `ninja` fallback i za sanitizaciju warning-a kada je stanje zapravo zdravo.
- [ ] Potvrditi da test pada pre popravke ili na starom report payload-u.
- [ ] Popraviti `TurboQuant` dependency put kroz portable fallback i uskladiti `install-report` / warning semantiku.
- [ ] Regenerisati `install-report` u lokalnoj instalaciji i proveriti da više ne prijavljuje zastarele warning-e kada nisu aktivni.
- [ ] Pokrenuti `python -m unittest tests\test_runtime_engine.py tests\test_windows_installer_packaging.py`.

### Task 3: Windows launcher and OpenCode reliability

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\control-center.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\local-qwen-common.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\start-opencode.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\manage-models.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\verify-install.ps1`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_control_center_layout.py`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_installer_packaging.py`

- [ ] Proći launcher po launcher i zabeležiti koje akcije rade u foreground-u, koje u background-u i gde korisnik ne vidi status.
- [ ] Napisati/pojačati testove za background worker, OpenCode resolver i UI layout očekivanja.
- [ ] Implementirati popravke za `OpenCode`, `About`, `Model browser`, `Test throughput`, update i uninstall pozive.
- [ ] Uvesti ili dovršiti `dump-ui-text.ps1` kao pomoćnu dijagnostiku za ručni test.
- [ ] Pokrenuti `python -m unittest tests\test_windows_control_center_layout.py tests\test_windows_installer_packaging.py`.

### Task 4: Windows model download UX

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\control-center.ps1`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\windows\local-qwen-common.ps1`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_control_center_layout.py`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_runtime_engine.py`

- [ ] Definisati šta korisnik mora da vidi tokom downloada: izvor, veličina, procenat, brzina, ETA, poruka završetka/neuspeha.
- [ ] Napisati ili proširiti test koji proverava prisustvo progress hook-ova i UI prikaznih elemenata.
- [ ] Implementirati jasniji `Download status` prikaz u `Control Center`-u.
- [ ] Lokalno isprobati download tok sa live progress payload-om.
- [ ] Ponovo pokrenuti संबंधित testove i potvrditi da su zeleni.

### Task 5: Linux regression protection

**Files:**
- Verify only unless Linux fix becomes strictly necessary:
  - `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center.sh`
  - `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\local_qwen_common.sh`
  - `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\install\linux\install.sh`

- [ ] Posle svakog većeg Windows fixa pokrenuti `bash -n` nad Linux launcherima i installerom.
- [ ] Ne dirati Linux fajlove osim ako Windows shared change zahteva eksplicitno usklađivanje.
- [ ] Ako Linux mora da se menja, ograničiti izmenu na shared/version/release posledice i odmah proveriti parse.

### Task 6: Final verification and release candidate

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\version.json`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\release-notes.txt`
- Verify/build:
  - `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\packaging\release-all.ps1`

- [ ] Pokrenuti puni test paket: `python -m unittest tests\test_runtime_engine.py tests\test_windows_installer_packaging.py tests\test_windows_control_center_layout.py`.
- [ ] Pokrenuti PowerShell parse proveru za izmenjene Windows skripte.
- [ ] Pokrenuti Linux `bash -n` proveru.
- [ ] Lokalno osvežiti `LocalQwenHome` instalaciju i proveriti `verify-install.ps1`.
- [ ] Podignuti novu verziju, ažurirati `release-notes.txt`, napraviti build/release kandidat i tek onda dati korisniku jednu verziju za ručni UX test.
