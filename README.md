# NIK v2 — Naczelny Inspektorat Kreeperowy

**Dla Franka ♥ Tata**

Polskie komendy Minecraft Java w terminalu Bash: przedmioty, zaklęcia, efekty,
teleporty, tryby gry, własne zestawy i kopie świata. Kolorowe listy i baner,
podpowiedzi Tab oraz sugestie przy literówkach. Aktualna wersja: **2.1.0**.

**Rozwijany jest NIK v2 w katalogu [`v2/`](v2/).** NIK v1 jest archiwalny,
bez dalszego rozwoju. Jego kod i dotychczasowa dokumentacja znajdują się
w [`archive/v1/`](archive/v1/). Archiwum zachowuje historyczny kod; instaluj v2.

## Co potrafi

| Funkcja | Przykład |
|---|---|
| Przedmioty i szukanie PL/EN | `daj g1 diament 64`, `szukaj jajo_` |
| Nowy zaklęty przedmiot | `encik g1 diamentowy_miecz ostrosc:5 naprawa` |
| Zaklinanie rzeczy w głównej ręce | `zaklnij g1 ostrosc:5 naprawa` |
| Pełne, kolorowe listy | `przedmioty`, `encik co`, `efekt co` |
| Efekty i leczenie | `efekt g1 sila 60 2`, `zdrowie g1` |
| Teleporty i miejsca | `dom g1`, `tp g1 gracz2`, `miejsce lista` |
| Tryb wskazanego gracza, ten sam świat | `kreatywny g1`, `przetrwanie g1`, `obserwator g1` |
| Własne zestawy | `zestaw zapisz wyprawa pochodnia=64 pieczona_wolowina=32` |
| Dawanie zapisanego zestawu | `zestaw g1 wyprawa` |
| Zapis bieżącego stanu | `zapiszswiat` |
| Oddzielne kopie świata | `kopia`, `kopia lista` |
| Przywracanie po kopii bieżącego świata | `przywroc ID_KOPII --potwierdz` |
| Diagnostyka | `nik status` |

Katalog dla Minecraft Java **26.3** obejmuje 1657 przedmiotów, 43 zaklęcia
z polskimi i angielskimi nazwami oraz 40 efektów. Starsze nazwy przedmiotów
pozostają aliasami. Dane i reguły pochodzą z rejestrów oraz tłumaczeń vanilla.
Niestandardowe datapacki mogą wymagać osobnych zmian.

## Instalacja na serwerze

Wymagania: Linux, Bash 4.4+, Docker dostępny dla użytkownika, `rcon-cli` w
kontenerze Minecraft, GNU coreutils, `flock`, awk, sed, sort oraz Python 3.11+.
Kopie świata wymagają również Python 3.11+ w obrazie Minecraft i trwałego
wolumenu `/data`. Hasło RCON pozostaje w konfiguracji kontenera.
NIK nie wymaga wpisywania go do publicznych plików i nie łączy się sam przez SSH.

Pierwsza instalacja:

```bash
git clone https://github.com/franekfrk/nik.git
cd nik
mkdir -p "$HOME/.nik"
cp -R v2/. "$HOME/.nik/"
cp -R "$HOME/.nik/config.example/." "$HOME/.nik/config/"
chmod 700 "$HOME/.nik" "$HOME/.nik/config"
# Edytuj ~/.nik/config/config.env, players.tsv i places.tsv.
source "$HOME/.nik/nik.sh"
nik
```

Do `~/.bashrc` dodaj:

```bash
source "$HOME/.nik/nik.sh"
```

Po wczytaniu działają skróty `daj`, `d`, `encik`, `zaklnij`, `kreatywny`,
`zestaw`, `kopia`, `zapiszswiat` i pozostałe komendy oraz uzupełnianie Tab.
Używaj `source`, żeby dodać je do aktualnej sesji. Strict mode skryptu nie zmienia
ustawień powłoki użytkownika. Przy aktualizacji zachowaj dotychczasowe `config/`;
nie kopiuj ponownie przykładów na własne ustawienia.

## Opcje po polsku

```bash
nik --pomoc
nik zaklnij --pomoc
nik --wersja
zaklnij g1 ostrosc:5 --podglad
wyposaz g1 walka --potwierdz
nik --konfiguracja /sciezka/do/config status
```

`--podglad` pokazuje plan bez wykonywania operacji. `--potwierdz` jest wymagane
przy wybranych operacjach, m.in. przywracaniu świata, nadpisywaniu wyposażenia
czy restartowaniu. Klawisz Tab podpowiada polskie opcje. Angielskie opcje
`--config`, `--dry-run`, `--confirm`, `--help`, `--version` nadal działają jako aliasy.
Nazwy przedmiotów i zaklęć można podawać także z polskimi znakami.

## Zapis a kopia świata

`zapiszswiat` zapisuje bieżący stan gry. `kopia` tworzy osobne archiwum w
`~/.nik/world-backups/`, które można później przywrócić. **Tworzenie i przywracanie
kopii na krótko zatrzymuje kontener i rozłącza graczy.** Przywracanie najpierw
zachowuje bieżący świat. Archiwum i sumy SHA256 są sprawdzane przed zmianami;
kontener uruchamia się ponownie, jeśli działał przed operacją. Gotowość gry
sprawdź przez `nik status`.

Kopia obejmuje świat, dane graczy w świecie i jego wymiary. Nie obejmuje
konfiguracji serwera, pluginów ani zewnętrznych baz. Kopii nie usuwa się
automatycznie. Szczegóły, wymagania i granice odzyskiwania opisuje
[dokumentacja v2](v2/README.md).

## Dane prywatne i paczki

Repozytorium zawiera przykłady `PlayerOne` i `PlayerTwo`. Własna konfiguracja,
logi, oryginalny prywatny skrypt, archiwa światów oraz gotowe prywatne ZIP-y
są wykluczone z Gita. `.gitignore` nie usuwa sekretów wcześniej zapisanych
w historii — sprawdzaj pliki przed publikowaniem.

```bash
python3 v2/tools/package.py --out dist
# Opcjonalnie, wyłącznie do prywatnego przechowania:
python3 v2/tools/package.py --out dist --private-config "$HOME/.nik/config"
```

Paczka publiczna zawiera kod i przykłady. Paczka prywatna zawiera dodatkowo
wskazane ustawienia. **Nie publikuj paczki prywatnej.** Sumy plików zapisują się
w `dist/SHA256SUMS`.

## Testy i architektura

```bash
# Narzędzia kontroli: ShellCheck, Bats, Python 3.11+.
bash v2/tests/check.sh
```

Moduły Bash znajdują się w `v2/lib/`, katalogi i reguły w `v2/data/`, a narzędzia
w `v2/tools/`. CI sprawdza składnię Bash, ShellCheck, integralność danych,
testy komend z modelem Docker/RCON oraz izolowane testy kopii i przywracania.
Testy nie korzystają z produkcyjnego świata ani prywatnych ustawień.

Pełne użycie: [README v2](v2/README.md). Zakres kontroli i ograniczenia:
[VALIDATION.md](v2/VALIDATION.md).
