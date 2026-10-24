# NIK v1 — wersja archiwalna

**Bez dalszego rozwoju.** Używaj [NIK v2](../../v2/README.md).
Kod v1 zachowano bez zmian jako historyczny punkt odniesienia.
Poniżej historyczna instrukcja v1; jej dawne ścieżki dotyczą poprzedniego układu repozytorium.

---

# NIK — Naczelny Inspektorat Kreeperowy

NIK to skrypt Bash do zarządzania serwerem Minecraft przez polskie komendy w terminalu. Pozwala dawać przedmioty, nakładać efekty i zaklęcia, teleportować graczy, zmieniać pogodę oraz zapisywać świat. Oferuje słownik przedmiotów PL → EN, podpowiedzi klawiszem Tab i logowanie komend.

Skrypt działa na komputerze z dostępem do Dockera obsługującego serwer. Wysyła polecenia przez `docker exec <kontener> rcon-cli`. Nie zestawia sam połączenia SSH z innym serwerem i nie instaluje Minecrafta.

## Wymagania

- Linux z Bashem 4 lub nowszym i narzędziami `date`, `awk`, `grep`, `sed`, `sort`, `mktemp` oraz `timeout`.
- Docker i uprawnienia do wykonywania `docker ps`, `docker exec` oraz `docker restart` jako bieżący użytkownik.
- Uruchomiony kontener serwera Minecraft Java z dostępnym poleceniem `rcon-cli`.
- Włączony RCON i poprawnie skonfigurowane uwierzytelnienie klienta wewnątrz kontenera. Hasło RCON pozostaje w konfiguracji serwera/kontenera.

Słownik przedmiotów w kodzie opisano jako przygotowany dla Minecraft 1.21.4. Dostępność przedmiotów, zaklęć i składnia poleceń zależą od wersji serwera. Zgodność z innymi wersjami wymaga sprawdzenia na swoim serwerze.

## Instalacja

Na komputerze obsługującym kontener wykonaj:

```bash
git clone https://github.com/franekfrk/nik.git
cd nik
cp nik.local.example.sh nik.local.sh
nano nik.local.sh
```

Po uzupełnieniu konfiguracji wczytaj skrypt do bieżącej sesji Bash:

```bash
source ./nik.sh
nik
```

Używaj `source`, ponieważ funkcje, aliasy i podpowiedzi muszą zostać zdefiniowane w bieżącej powłoce. Uruchomienie przez `bash nik.sh` lub `./nik.sh` wyświetla instrukcję zamiast instalować komendy w sesji.

## Co zmienić w konfiguracji

Edytuj **`nik.local.sh`**. Plik jest automatycznie wczytywany z katalogu skryptu i wykluczony z Gita. `nik.local.example.sh` zawiera wyłącznie przykładowe dane.

### Kontener i logi

```bash
MC_CONTAINER="minecraft"
MC_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nik/nik.log"
MC_LOG_DNI=30
```

Zmień `MC_CONTAINER` na nazwę swojego kontenera widoczną w `docker ps`. `MC_LOG` określa ścieżkę pliku z historią komend. Wpisy starsze niż `MC_LOG_DNI` dni są usuwane przy wczytywaniu skryptu.

### Gracze

```bash
MC_GRACZE=(gracz1 gracz2)
MC_GRACZE_SKROTY=([gracz1]="g1" [gracz2]="g2")
MC_GRACZE_NICKI=([gracz1]="PlayerOne" [gracz2]="PlayerTwo")
```

- `MC_GRACZE` to nazwy używane w poleceniach NIK.
- `MC_GRACZE_SKROTY` przypisuje im krótkie aliasy.
- `MC_GRACZE_NICKI` zawiera rzeczywiste nicki Minecraft. Zastąp `PlayerOne` i `PlayerTwo` nickami swoich graczy.

Aby dodać gracza, dopisz go do wszystkich trzech tablic. Polecenia przyjmują nazwę z `MC_GRACZE` lub jej skrót, np. `zdrowie gracz1` i `zdrowie g1`. Obsługiwane nicki zawierają od 1 do 16 liter ASCII, cyfr lub podkreślników, opcjonalnie z kropką na początku.

### Dom i zamek

Ustaw po trzy współrzędne dla każdej lokalizacji:

```bash
MC_DOM_X="0"
MC_DOM_Y="64"
MC_DOM_Z="0"
MC_ZAMEK_X="100"
MC_ZAMEK_Y="70"
MC_ZAMEK_Z="100"
```

To przykładowe wartości — wpisz współrzędne ze swojego świata. Dom i zamek są wspólne dla wszystkich graczy. Puste wartości z szablonu blokują teleport do danego miejsca. Polecenia używają bieżącego wymiaru gracza.

Po każdej zmianie konfiguracji ponownie wykonaj `source ./nik.sh`.

## Przykłady użycia

Przykłady zakładają konfigurację graczy i skrótów pokazaną powyżej.

```bash
nik                               # pomoc
gracz_lista                       # skonfigurowani gracze
online                            # gracze online
szukaj kilof                      # wyszukiwanie przedmiotów PL/EN
daj g1 diamentowy_kilof            # domyślnie 1 sztuka
daj g1 diamond 64                  # angielskie ID też działa
efekt g1 sila 60                   # siła na 60 sekund
usun g1 sila                      # usunięcie wskazanego efektu
wyczysc g1                        # usunięcie wszystkich efektów
zdrowie g1                        # leczenie i nasycenie
dom g1                            # teleport do skonfigurowanego domu
tp g1 100 70 200                   # teleport pod podane współrzędne
dolacz g1 g2                      # teleport gracza1 do gracza2
encik g1 tarcza unbreaking:3       # przedmiot z zaklęciem
dzien                             # dzień i czysta pogoda
pogoda deszcz
zapisz                            # zapis świata
```

Pełne listy wyświetlisz poleceniami `przedmioty`, `efekt co` oraz `encik co`. Klawisz Tab podpowiada skonfigurowanych graczy, przedmioty, efekty i zaklęcia.

Pozostałe komendy obejmują `zamek`, `noc`, `burza`, `zamroz`, `odmroz`, `kick`, `wyposaz`, `grzmot`, `wybuch` i `restartmc`.

`encik` **zastępuje przedmiot trzymany w głównej ręce**, a następnie nakłada zaklęcia. `wyposaz` zastępuje również zbroję, drugą rękę i wybrane sloty ekwipunku. `wybuch` przywołuje creepera z natychmiastowym wybuchem, a `restartmc` restartuje kontener. Używaj tych komend ze świadomością ich skutków w świecie gry.

## Automatyczne wczytywanie

Opcjonalnie dodaj do `~/.bashrc`, dostosowując ścieżkę do swojej instalacji:

```bash
if [[ -f "$HOME/nik/nik.sh" ]]; then
    source "$HOME/nik/nik.sh"
fi
```

Skrypt przy każdym wczytaniu pokazuje baner i sprawdza stan kontenera. Definiuje też funkcje i aliasy w bieżącej sesji, m.in. `tp` i `kick`.

## Rozwiązywanie problemów

- **Minecraft nie działa** — sprawdź `docker ps`, nazwę w `MC_CONTAINER` i uprawnienia użytkownika do Dockera.
- **Brak `rcon-cli` lub błąd uwierzytelnienia** — sprawdź `docker exec minecraft rcon-cli list`, podstawiając nazwę swojego kontenera. Skonfiguruj RCON i klienta w kontenerze.
- **Nieznany gracz lub pusta lista** — uzupełnij trzy tablice w `nik.local.sh` i ponownie wczytaj skrypt.
- **Brak teleportu do domu lub zamku** — uzupełnij wszystkie trzy współrzędne danej lokalizacji.
- **Polecenia nie są dostępne** — upewnij się, że pracujesz w Bashu i używasz `source`, nie uruchamiasz skryptu jako osobnego procesu.

## Prywatna konfiguracja

Nie dodawaj do repozytorium pliku `nik.local.sh`, haseł RCON, kluczy SSH ani logów. Logi mogą zawierać nicki, współrzędne i treść komend; domyślnie są zapisywane poza projektem. `.gitignore` pomija lokalną konfigurację, pliki `.env`, logi i typowe pliki kluczy.

`nik.local.sh` jest kodem Bash wykonywanym przy `source` — używaj własnego, zaufanego pliku. Do uruchamiania NIK nie jest potrzebny klucz SSH do tego repozytorium.
