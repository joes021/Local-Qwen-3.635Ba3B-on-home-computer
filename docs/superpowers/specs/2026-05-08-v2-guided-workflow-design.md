# v2.0.0 Guided Workflow Design

## Goal

Pretvoriti postojece servisne launchere i tabove u vodjeniji first-run i repair tok, tako da korisnik ne mora da pogadja sledeci korak nakon instalacije ili delimičnog kvara.

## Scope

`v2.0.0` uvodi tri stvari:

1. Guided onboarding/status snapshot koji postoji i na Windows i na Linux strani.
2. Rich diagnostics pregled iz samog interfejsa, ne samo export arhive.
3. Guided repair tok koji za korisnika prevodi "sta fali" u "sta sada klikni/pokreni".

## Design

### Shared engine

Postojeci `scripts/local_qwen_runtime.py` ostaje centar shared odluka i dobija jos jedan sloj:

- `onboarding-checklist`
- `agent-audit`
- `next-action`

Na taj nacin Windows i Linux vise ne drze odvojene heuristike za onboarding i repair tekst, nego dele isti payload.

### Windows

`control-center.ps1` dobija:

- `Onboarding` tab sa checklistom i sledecim preporucenim korakom
- `Diagnostics` tab koji prikazuje:
  - latest release status
  - health status
  - onboarding ready/not ready
  - model/runtime/config summary
- guided repair dugme koje ne pokrece samo repair skriptu, nego prethodno objasnjava sta ce popraviti

### Linux

`control-center.sh` dobija isti koncept u TUI formi:

- status snapshot
- onboarding readiness
- next recommended action
- diagnostics summary pre nego sto korisnik mora da otvara export bundle

### Diagnostics

Diagnostics export ostaje, ali pored toga prikaz u UI/TUI mora da bude dovoljan za:

- brzo razumevanje stanja
- basic self-service
- pripremu za debug bez ručnog kopanja po fajlovima

## Success criteria

- nov korisnik moze da vidi da li je sistem spreman bez otvaranja log fajlova
- polovicna instalacija daje jasan "next action"
- Windows i Linux prikazuju isti shared status signal, iako su UI slojevi razliciti
