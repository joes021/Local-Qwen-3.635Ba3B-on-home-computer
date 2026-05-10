# Linux Dashboard TUI Design

## Goal

Zameniti postojeci dugi numericki meni u `control-center.sh` preglednijim Linux dashboard TUI slojem, tako da korisnik brze razume stanje sistema i lakse dolazi do glavnih akcija bez osecanja da "lista svega" treba da se pamti.

## Scope

Ovaj rad uvodi novi TUI raspored za Linux `Control Center`, bez menjanja osnovnih backend skripti za start, repair, diagnostics, modele i settings.

U scope ulazi:

1. novi `Home` ekran sa status headerom i malim brojem glavnih sekcija
2. izdvojeni ekrani za `Pokretanje`, `Modeli`, `Tools`, `Diagnostics`, `Settings`
3. rezultat ekrani za duze akcije i jasniji feedback
4. zadrzavanje postojece logike i launchera gde god je to moguce

Van scope-a za prvu iteraciju:

- puni `ncurses`/strelice/fokus UI
- novi Linux GUI `Control Center`
- menjanje shared runtime engine payload formata osim gde je bas potrebno za TUI prikaz

## Approaches

### 1. Minimalni facelift

Zadrzati jedan meni i samo prepakovati tekst.

Plus:
- najmanji rizik
- najbrza izmena

Minus:
- i dalje deluje kao dugi servisni meni
- ne resava stvarno "previše stavki odjednom" problem

### 2. Dashboard TUI

Uvesti pocetni dashboard i manje podmenije po oblasti.

Plus:
- najbolji balans UX-a i rizika
- radi stabilno na Linux desktop i server okruzenjima
- backend ostaje uglavnom isti

Minus:
- malo vise rada na navigaciji i status porukama

### 3. Wizard-first TUI

Sistem vodi korisnika kroz unapred definisane tokove umesto kroz sekcije.

Plus:
- lako za nove korisnike

Minus:
- sporije za naprednije korisnike
- losije za servisne i debug tokove

### Recommendation

Preporucen je pristup `2`, dashboard TUI.

## Design

### Architecture

Postojeci `launcher/linux/control-center.sh` postaje TUI orchestrator sa vise ekrana, a ne jedan veliki meni. Shared helperi iz `launcher/linux/local_qwen_common.sh` i shared engine iz `scripts/local_qwen_runtime.py` ostaju izvor statusa, health-a, repair plana i telemetry podataka.

To znaci:

- backend akcije ostaju postojece skripte
- TUI samo organizuje prikaz, navigaciju i rezultat poruke
- Linux i dalje deli health/recommendation logiku sa Windows stranom

### Home screen

`Home` je ulazna tacka i prikazuje samo najvaznije:

- naslov `Local Qwen Control Center`
- verziju
- `Server`
- `Health`
- `Model`
- `Profil`

Ispod toga ide kratak summary:

- `Next action`
- `Last warning`
- `Last activity`

Zatim glavni meni:

1. `Pokretanje`
2. `Modeli`
3. `Tools`
4. `Diagnostics`
5. `Settings`
6. `Exit`

### Launch screen

`Pokretanje` sadrzi samo glavne dnevne akcije:

1. `Start llama.cpp server`
2. `Stop llama.cpp server`
3. `Run OpenCode`
4. `Run llama.cpp web`
5. `Test prompt`
6. `Test throughput`
7. `Nazad`

Ovaj ekran ne prikazuje duboke diagnostics detalje, samo kratku orijentaciju i akcije.

### Models screen

`Modeli` se deli na:

- summary status:
  - aktivni model
  - broj skinutih modela
  - download state
- akcije:
  1. `Pregled modela`
  2. `Aktiviraj model`
  3. `Preuzmi model`
  4. `Dodaj lokalni GGUF`
  5. `Dodaj HF model`
  6. `Nazad`

`Pregled modela` prikazuje listu sa oznakama:

- `[AKTIVAN]`
- `[SKINUT]`
- `[NIJE SKINUT]`
- `[HF]`
- `[LOKALNI]`
- `[PREPORUKA]`

Detalji modela se otvaraju tek po izboru konkretnog modela i sadrze:

- status
- opis
- potreban disk
- slobodan disk
- procenu brzine kada je poznata
- izvor modela
- dostupne akcije

### Tools screen

`Tools` okuplja servisne tokove:

1. `Repair install`
2. `Repair model`
3. `Repair runtime`
4. `Repair config`
5. `Guided repair`
6. `Check updates`
7. `Install update`
8. `Nazad`

### Diagnostics screen

`Diagnostics` prikazuje:

- effective state
- lifecycle
- health URL
- poslednje benchmark stanje

Akcije:

1. `Health details`
2. `View logs`
3. `Export diagnostics`
4. `Benchmark pregled`
5. `Nazad`

### Settings screen

`Settings` prikazuje trenutne vrednosti i vodi do promena:

1. `Promeni profil`
2. `Promeni context`
3. `Promeni output`
4. `Promeni stepove`
5. `Promeni working dir`
6. `Quick presets`
7. `Nazad`

### Result screens

Posle duzih akcija korisnik ne ide odmah nazad na meni. Umesto toga dobija rezultat ekran sa:

- naslovom akcije
- statusom `Info / Warning / Error`
- kratkim sazetkom
- log putanjom kada postoji
- preporucenim sledecim korakom
- `Enter za nazad`

Za tokove kao `download modela`, `repair`, `install update`, `test throughput` prikazuje se i zivi status kada postoji:

- faza
- procenat
- brzina
- ETA
- poslednja smislena poruka

## Error handling

TUI ne treba da dumpuje sirove stack trace poruke kao primarni UX. Za korisnika postoje 3 nivoa:

- `Info`: akcija uspesna
- `Warning`: akcija radi, ali ima napomena
- `Error`: nije uspelo, uz jednu jasnu preporuku

Detaljan log ostaje dostupan kroz `View logs` ili kroz putanju prikazanu na result ekranu.

## Testing

Pre zavrsetka implementacije treba proveriti:

1. shell syntax za nove Linux TUI skripte
2. dashboard navigaciju kroz scripted smoke testove
3. da `Home` prikazuje stvarne status podatke iz postojece instalacije
4. da `Start/Stop/OpenCode/Test` tokovi i dalje pozivaju postojece backend skripte
5. da `Modeli`, `Tools`, `Diagnostics`, `Settings` ne vrate korisnika u slepu ulicu
6. da headless fallback i dalje radi, bez oslanjanja na GUI

## Success criteria

- korisnik ne vidi vise 20+ opcija odjednom na prvom ekranu
- glavne dnevne akcije su odvojene od servisnih
- model tok je citljiviji i manje zbunjujuci
- dugi tokovi daju jasan feedback umesto osecanja da se nista ne desava
- Linux ostaje stabilan i bez zavisnosti od punog GUI okruzenja
