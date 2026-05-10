# Linux Dashboard TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zameniti trenutni dugi Linux `control-center.sh` meni preglednim dashboard TUI tokom sa manjim brojem opcija po ekranu i jasnijim status/result prikazom.

**Architecture:** Zadrzati postojeci Linux launcher backend i shared runtime engine, a iznad njih uvesti tanji TUI sloj podeljen na home, sekcijske ekrane i result prikaze. `control-center.sh` postaje tanak entrypoint, a novi TUI helper fajlovi preuzimaju render, navigaciju i akcioni feedback.

**Tech Stack:** Bash, postojece Linux launcher skripte, `python3` helper payload-i iz `scripts/local_qwen_runtime.py`, `unittest`, `bash -n`

---

## File structure

**Existing files to modify**
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center.sh`
  - sadasnji veliki meni; na kraju ostaje samo entrypoint i poziv novog TUI sloja
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\local_qwen_common.sh`
  - shared helperi za status, lifecycle, telemetry i model/download podatke
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\manage-models.sh`
  - modeli i download tokovi koje ce novi TUI da poziva
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\settings-tui.sh`
  - settings tok koji treba poravnati sa novim dashboard TUI iskustvom
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_installer_packaging.py`
  - postojece mesto za Linux launcher tekstualne i smoke regresije

**New files to create**
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-dashboard.sh`
  - screen router, home ekran, sekcijski meniji
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-actions.sh`
  - result ekran, wrapperi za duze akcije, status i error feedback
- `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_linux_control_center_tui.py`
  - fokusirani Linux TUI testovi umesto daljeg naduvavanja Windows packaging fajla

## Task 1: Uvesti dashboard TUI kostur

**Files:**
- Create: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-dashboard.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center.sh`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_linux_control_center_tui.py`

- [ ] **Step 1: Write the failing test for dashboard shell structure**

```python
def test_linux_dashboard_entry_uses_separate_dashboard_file():
    control_center = CONTROL_CENTER_PATH.read_text(encoding="utf-8")
    dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
    assert 'control-center-dashboard.sh' in control_center
    assert 'render_home_screen' in dashboard
    assert 'show_main_menu' in dashboard
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
```

Expected: FAIL because dashboard file and symbols do not exist yet.

- [ ] **Step 3: Create minimal dashboard entrypoint**

```bash
# control-center.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/control-center-dashboard.sh"
```

```bash
# control-center-dashboard.sh
#!/usr/bin/env bash
set -euo pipefail
render_home_screen() { :; }
show_main_menu() { :; }
render_home_screen
show_main_menu
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
```

Expected: PASS for dashboard structure test.

- [ ] **Step 5: Run shell syntax checks**

Run:
```bash
bash -n launcher/linux/control-center.sh
bash -n launcher/linux/control-center-dashboard.sh
```

Expected: no output, exit code `0`.

- [ ] **Step 6: Commit**

```bash
git add launcher/linux/control-center.sh launcher/linux/control-center-dashboard.sh tests/test_linux_control_center_tui.py
git commit -m "feat: add linux dashboard tui entrypoint"
```

## Task 2: Implement Home, Pokretanje i Tools ekrane

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-dashboard.sh`
- Create: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-actions.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\local_qwen_common.sh`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_linux_control_center_tui.py`

- [ ] **Step 1: Write failing tests for Home and menu grouping**

```python
def test_dashboard_home_menu_has_primary_sections():
    dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
    assert '1. Pokretanje' in dashboard
    assert '2. Modeli' in dashboard
    assert '3. Tools' in dashboard
    assert '4. Diagnostics' in dashboard
    assert '5. Settings' in dashboard
```

```python
def test_launch_screen_contains_only_primary_runtime_actions():
    dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
    assert 'Start llama.cpp server' in dashboard
    assert 'Run OpenCode' in dashboard
    assert 'Repair install' not in extract_launch_menu_block(dashboard)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
```

Expected: FAIL because menus are not implemented.

- [ ] **Step 3: Implement Home, Pokretanje and Tools screens**

Code requirements:
- add `render_status_header`
- add `render_home_screen`
- add `show_launch_menu`
- add `show_tools_menu`
- add `read_menu_choice`
- keep only primary runtime actions in `Pokretanje`
- move repairs and update tokove into `Tools`

- [ ] **Step 4: Add minimal action wrappers**

Code requirements in `control-center-actions.sh`:
- `run_action_with_result_screen`
- `show_info_screen`
- `show_warning_screen`
- `show_error_screen`

Each wrapper should:
- run the existing backend script
- capture top-level result text
- wait for `Enter` before returning

- [ ] **Step 5: Run tests and shell syntax**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
bash -n launcher/linux/control-center-dashboard.sh
bash -n launcher/linux/control-center-actions.sh
```

Expected: PASS and syntax clean.

- [ ] **Step 6: Commit**

```bash
git add launcher/linux/control-center-dashboard.sh launcher/linux/control-center-actions.sh launcher/linux/local_qwen_common.sh tests/test_linux_control_center_tui.py
git commit -m "feat: add linux home, launch and tools dashboard screens"
```

## Task 3: Implement Modeli ekran i download feedback

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-dashboard.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-actions.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\local_qwen_common.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\manage-models.sh`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_linux_control_center_tui.py`

- [ ] **Step 1: Write failing tests for model dashboard copy and labels**

```python
def test_models_screen_mentions_model_actions_and_status_labels():
    dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
    assert 'Pregled modela' in dashboard
    assert 'Dodaj lokalni GGUF' in dashboard
    assert 'Dodaj HF model' in dashboard
    assert '[AKTIVAN]' in dashboard
    assert '[SKINUT]' in dashboard
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
```

Expected: FAIL because model dashboard text and renderers are absent.

- [ ] **Step 3: Add model summary and model detail screens**

Code requirements:
- `show_models_menu`
- `render_model_summary`
- `render_model_list`
- `render_model_detail`

UI requirements:
- show active model
- show downloaded model count
- show current download state
- show tags `[AKTIVAN]`, `[SKINUT]`, `[NIJE SKINUT]`, `[HF]`, `[LOKALNI]`, `[PREPORUKA]`

- [ ] **Step 4: Add download progress/result wrapper**

Code requirements:
- `show_download_progress_screen`
- `run_model_download_flow`
- use existing download progress file/state from shared helpers
- show:
  - model
  - status
  - procenat
  - brzina
  - ETA

- [ ] **Step 5: Run tests and smoke syntax**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
bash -n launcher/linux/manage-models.sh
bash -n launcher/linux/control-center-dashboard.sh
```

Expected: PASS and no syntax errors.

- [ ] **Step 6: Commit**

```bash
git add launcher/linux/control-center-dashboard.sh launcher/linux/control-center-actions.sh launcher/linux/local_qwen_common.sh launcher/linux/manage-models.sh tests/test_linux_control_center_tui.py
git commit -m "feat: add linux models dashboard and download feedback"
```

## Task 4: Implement Diagnostics i Settings ekrane

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center-dashboard.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\settings-tui.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\local_qwen_common.sh`
- Test: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_linux_control_center_tui.py`

- [ ] **Step 1: Write failing tests for Diagnostics and Settings menus**

```python
def test_diagnostics_screen_contains_logs_export_and_benchmark_entries():
    dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
    assert 'Health details' in dashboard
    assert 'View logs' in dashboard
    assert 'Export diagnostics' in dashboard
    assert 'Benchmark pregled' in dashboard
```

```python
def test_settings_screen_contains_profile_context_output_and_presets():
    dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
    assert 'Promeni profil' in dashboard
    assert 'Promeni context' in dashboard
    assert 'Promeni output' in dashboard
    assert 'Quick presets' in dashboard
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
```

Expected: FAIL because these screens are not implemented.

- [ ] **Step 3: Implement Diagnostics screen**

Code requirements:
- `show_diagnostics_menu`
- `render_diagnostics_summary`
- `render_benchmark_summary`
- keep diagnostics concise on first screen
- move long details behind sub-actions

- [ ] **Step 4: Integrate Settings menu**

Code requirements:
- `show_settings_menu`
- thin wrappers around `settings-tui.sh`
- keep one action per setting group
- preserve existing settings backend format

- [ ] **Step 5: Run tests and shell syntax**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
bash -n launcher/linux/settings-tui.sh
bash -n launcher/linux/control-center-dashboard.sh
```

Expected: PASS and clean syntax.

- [ ] **Step 6: Commit**

```bash
git add launcher/linux/control-center-dashboard.sh launcher/linux/settings-tui.sh launcher/linux/local_qwen_common.sh tests/test_linux_control_center_tui.py
git commit -m "feat: add linux diagnostics and settings dashboard screens"
```

## Task 5: Replace old flow, add scripted smoke coverage, and polish UX

**Files:**
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\launcher\linux\control-center.sh`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_windows_installer_packaging.py`
- Modify: `C:\Users\AzdahaI9\Documents\Local Qwen 3.635Ba3B on home computer\tests\test_linux_control_center_tui.py`
- Test: Linux launcher smoke commands

- [ ] **Step 1: Write failing smoke test for dashboard navigation**

```python
def test_dashboard_smoke_can_render_home_and_exit():
    result = subprocess.run(
        ["bash", "-lc", "printf '6\\n' | bash launcher/linux/control-center-dashboard.sh"],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
        timeout=30,
    )
    assert result.returncode == 0
    assert "Local Qwen Control Center" in result.stdout
```

- [ ] **Step 2: Run tests to verify failure or missing behavior**

Run:
```bash
python -m unittest tests.test_linux_control_center_tui -v
```

Expected: FAIL until dashboard flow is fully wired.

- [ ] **Step 3: Finalize old-to-new entrypoint swap**

Code requirements:
- ensure `control-center.sh` always routes into dashboard flow
- remove obsolete giant inline menu logic
- keep compatibility for desktop launcher `Exec`

- [ ] **Step 4: Run full regression**

Run:
```bash
python -m unittest tests\\test_windows_installer_packaging.py tests\\test_runtime_engine.py tests\\test_windows_control_center_layout.py tests\\test_linux_control_center_tui.py
bash -n launcher/linux/control-center.sh
bash -n launcher/linux/control-center-dashboard.sh
bash -n launcher/linux/control-center-actions.sh
bash -n launcher/linux/manage-models.sh
bash -n launcher/linux/settings-tui.sh
```

Expected: all tests PASS, all syntax checks clean.

- [ ] **Step 5: Run Linux dashboard smoke on actual installed copy**

Run:
```bash
printf '6\n' | ~/local-qwen-home/launchers/control-center.sh
printf '1\n7\n6\n' | ~/local-qwen-home/launchers/control-center.sh
```

Expected:
- home renders
- `Pokretanje` renders
- exit paths work without hanging

- [ ] **Step 6: Commit**

```bash
git add launcher/linux/control-center.sh launcher/linux/control-center-dashboard.sh launcher/linux/control-center-actions.sh tests/test_windows_installer_packaging.py tests/test_linux_control_center_tui.py
git commit -m "feat: ship linux dashboard tui control center"
```
