# NIK v2 — polskie komendy Minecraft

Dla Franka ♥ Tata

NIK to przede wszystkim **modułowy projekt Bash do polskich komend Minecraft
Java w Dockerze**. Ma też opcjonalną nakładkę **WWW/PWA NIK Mobile** na telefon
i komputer. Dziecko lub gracz może wpisywać komendy w terminalu albo wybierać
czynności w panelu WWW. Oba interfejsy wywołują ten sam `nik.sh` i korzystają
z tej samej konfiguracji, walidacji oraz logiki gry.

## NIK 2.9.0 / Mobile 1.5 — kolejka i scenariusze

- Dodawaj kolejne akcje, gdy poprzednia pracuje w tle. Serwer wykonuje jedną
  operację naraz, a kolejka mieści maksymalnie sześć przyjętych zadań.
- „Powtórz” w wyniku otwiera formularz z zapisanymi parametrami. Nie wykonuje
  polecenia automatycznie; potwierdzenie trzeba zaznaczyć ponownie.
- Anuluj oczekującą akcję przed uruchomieniem NIK. Zatrzymanie już uruchomionej
  czynności nie cofa wcześniejszych zmian.
- Edytor scenariuszy ma osobne wiersze, dodawanie, usuwanie i strzałki kolejności.
  „Sprawdź plan” wywołuje podgląd NIK. Wynik pokazuje też odpowiedź każdego kroku.
- NIK przekazuje polskie opisy rozpoznanych błędów, np. brak gracza online,
  nieobsługiwana komenda, pusta ręka lub timeout. Oryginalna odpowiedź pozostaje
  w szczegółach.

Starsze wpisy historii bez zapisanych parametrów nadal się otwierają, lecz nie
mają przycisku powtórzenia. Parametry nie są odtwarzane z tekstu komend.

## NIK 2.8.0 — wygodniejszy terminal i panel

- Graficzny plecak i skrzynia Endera: sloty, prawdziwe ikonki, ilości, wyposażenie,
  zaklęcia i trwałość. Kliknięcie przedmiotu pokazuje jego szczegóły.
- Rzeczywisty postęp oraz tekst wyniku w trakcie pracy, wysyłane przez NIK.
- Edycja nazwy, gracza i parametrów ulubionej akcji oraz zmiana jej kolejności.
- Własne scenariusze złożone z 1–12 komend, dostępne w terminalu i panelu.
- Gwiazdki przy przedmiotach i stworzeniach oraz ostatnie wybory, zapisane prywatnie
  i dostępne również po odświeżeniu oraz na innych urządzeniach.
- Jednolity, wersjonowany wynik `--json` oraz strumień `--jsonl` dla komend NIK.

## Terminal albo panel WWW

W terminalu po wczytaniu skryptu możesz wpisać:

```bash
daj g1 diament 16
plecak g1
przywolaj g1 krowa 3
nik menu
```

Panel prowadzi przez te same czynności: wybierz gracza, wyszukaj przedmiot lub
stworzenie, ustaw ilość i naciśnij „Wykonaj”. Możesz też zapisać własny przycisk
w ulubionych. Działa w przeglądarce komputera i telefonu, a przez HTTPS można
zainstalować go jako PWA. Terminal obsługuje ponadto pełny zestaw komend NIK,
w tym operacje administracyjne opisane w dalszej części instrukcji.

NIK w terminalu działa samodzielnie. Panel uruchamia istniejący skrypt Bash;
odczyty graczy, zmiany gry i kopie świata wykonują komendy NIK. Backend WWW to
Python 3.11+ z biblioteką standardową; jego własne dane to historia i ulubione.
Instalacja i pełna obsługa nakładki: [instrukcja panelu](panel/README.md).

Polskie nazwy można wyszukiwać i uzupełniać klawiszem Tab. Pomoc, listy i komunikaty
używają minecraftowych kolorów; baner i pomoc mają tęczowy podpis. Tryb
`--podglad` pokazuje plan bez wykonywania komend.

`przywolaj GRACZ STWORZENIE [ILOŚĆ]` przyjmuje opcjonalnie 1–64 sztuki.
Bez ilości przywołuje dokładnie jedno stworzenie. `x`, 0 i przekroczony limit
są błędem przed pierwszym poleceniem gry. Przykład: `przywolaj g1 krowa 6`.
Wszystkie stworzenia pojawiają się 2 bloki obok aktualnej pozycji gracza;
NIK nie sprawdza wolnego miejsca. Przy błędzie w połowie wcześniej przywołane
stworzenia pozostają, a dalsze polecenia nie są wykonywane. Bossy nadal
wymagają potwierdzenia; dotyczy ono całej podanej liczby.

## NIK 2.7.0 — panel jako nakładka

Panel Mobile 1.3 zachowuje historię ostatnich 100 działań i ich wyniki po
odświeżeniu, logowaniu i restarcie. Ma trwałe ulubione akcje, filtry historii,
kolejkę, karty stanu graczy i kopie świata. Każdy odczyt i zmiana Minecrafta
przechodzą przez CLI NIK. Skróty otwierają formularz z zapisanymi ustawieniami;
wykonanie i potwierdzenia nadal należą do użytkownika.

Stan graczy jest dostępny również bez panelu: `nik stan`, `nik stan g1`,
`nik stan lista json`. Kopie: `nik kopia`, `nik kopia lista`, `nik kopia dane`.
Kopia chwilowo zatrzymuje Minecrafta, a po archiwizacji uruchamia go ponownie.
Szczegóły panelu i prywatnego pliku historii: [panel/README.md](panel/README.md).

## Stabilizacja 2.5.1

Wspólny strict mode obejmuje także podstawienia `$(...)` przez `inherit_errexit`.
Transport ma wymuszone zakończenie procesu ignorującego TERM, a blokady danych
mają limit oczekiwania. Rejestr, parser i pomoc są osobnymi modułami.
Jawny manifest paczki i testy prywatności chronią przed przypadkowym dołączeniem
prywatnych plików. Szczegóły: [architektura](ARCHITECTURE.md) i
[polityka prywatności i bezpieczeństwa](SECURITY.md).

## Panel NIK Mobile — nowe w 2.6

Minecraftowy panel w przeglądarce, zaprojektowany na telefon: wybór gracza,
duże kafelki, wyszukiwanie przedmiotów/stworzeń, ilości, zaklęcia, efekty,
teleporty, zadania i wiadomości od Taty. Uruchamia istniejący `nik.sh` z prywatną
konfiguracją. Obsługuje PWA i prywatny HTTPS przez Tailscale Serve na porcie 6767.
Instrukcja: [panel/README.md](panel/README.md).

## Nowe w 2.5 — menu i wspólna zabawa

```bash
nik menu
prowadz g1 baza              # pasek nad ekwipunkiem; domyślnie do 60 s
prowadz g1 baza 2m           # odczyt pozycji i kierunku co 2 s, maks. 10 min
odliczanie g1 10 "Start!"
losuj g1                     # losowe zadanie + książka od Taty
nagroda lista
nagroda g1 budowniczy
przepis pochodnia
```

Menu wybiera gracza, kategorię, czynność i potrzebne argumenty. Przed uruchomieniem
pokazuje komendę i wybór: wykonaj, podgląd albo anuluj. Błędne dane nie zamykają menu.
Wymaga interaktywnego terminala; `nik menu --podglad` zachowuje podgląd wszystkich
wybranych czynności. Menu nie włącza automatycznie ochrony świata ani operacji
wymagających `--potwierdz`. Klasyczne komendy i Tab nadal działają.

`prowadz` pokazuje kierunek względem aktualnego patrzenia, odległość poziomą i różnicę
wysokości. Działa w tym samym wymiarze; nie wyznacza bezpiecznej drogi ani nie omija
przeszkód. Kończy się przy zbliżeniu na mniej niż 3 bloki w poziomie, upływie czasu,
błędzie odczytu lub Ctrl+C. Sprawdź różnicę wysokości! Nie teleportuje gracza.
Po zatrzymaniu ostatni pasek znika zgodnie ze zwykłym czasem wyświetlania gry.
`odliczanie` przyjmuje 1–60 sekund, działa na pierwszym planie; Ctrl+C zatrzymuje.
Czasy są orientacyjne i obejmują opóźnienia RCON. Tytuły/pasek mogą być zastępowane
przez inne komendy lub pluginy.

Własna lista wyzwań: `config/challenges.txt`, jedno wyzwanie na wiersz, komentarze
zaczynają się od `#`. Każdy tekst ma 1–512 znaków. Bez tego pliku używana jest lista
przykładowa w `data/challenges.txt`. `losuj` korzysta z istniejącego systemu zadań:
nie nadpisuje aktywnego zadania. Najpierw `zadanie GRACZ gotowe` lub świadomie usuń.
Wykonanie wyzwania oznaczasz ręcznie; nagroda nie jest przyznawana automatycznie.

Własne nagrody: `config/rewards/NAZWA.tsv` (nadpisują przykładową nagrodę o tej
samej nazwie). Wiersz: angielskie ID przedmiotu bez `minecraft:`, tabulator, ilość.
Przykład: `diamond<TAB>3`, `torch<TAB>64`. Maksymalnie 36 wierszy, 1–2304 sztuki
na wiersz. Pełna lista jest sprawdzana przed dawaniem. Kolejne wywołanie ponownie
daje nagrodę; błąd gry w połowie może pozostawić wcześniej dane przedmioty.
Przy pełnym ekwipunku `/give` może upuścić przedmioty obok gracza.

`przepis` korzysta z 2042 oficjalnych plików receptur vanilla Minecraft Java 26.3.
Pokazuje stałe wyniki: układ siatki z legendą, składniki zamienne, piece,
przecinarkę i ulepszenia kowalskie. Kilka receptur tego samego wyniku wyświetla
osobno. To katalog podstawowej gry: nie uwzględnia zmian datapacków, handlu,
łupów, warzenia mikstur ani dynamicznych wyników receptur specjalnych.
Dla przedmiotu bez stałej receptury wyjaśnia brak wpisu. Receptury działają offline.
Prywatne wyzwania i nagrody należą do `config/`, są wykluczone z publicznego ZIP-a
oraz Gita, a dołączane tylko do paczki prywatnej.

## Wymagania

Linux, Bash >= 4.4, Docker, `rcon-cli` wewnątrz kontenera, GNU coreutils
(`timeout`, `date`, `mktemp`), `flock`, awk, sed, sort i chmod.
Python 3.11+ służy do kopii świata, podpowiedzi literówek, audytów, migracji, pakowania i testów. Do kontroli kodu potrzebne
są ShellCheck oraz Bats. NIK używa dostępu bieżącego użytkownika do Dockera.
RCON nadal korzysta z uwierzytelnienia skonfigurowanego w kontenerze; nie trzeba
wpisywać hasła w NIK. Sam NIK nie zestawia połączenia SSH.

Katalog i reguły sprawdzono dla **Minecraft Java 26.3**: 1657 przedmiotów,
43 zaklęcia i 40 efektów. Porównano cały rejestr gry, nie tylko changelog.
`air` jest wykluczone z katalogu zwykłych przedmiotów. Reguły vanilla mogą się
różnić od reguł niestandardowych datapacków.

## Instalacja

Publiczna paczka zawiera wyłącznie przykładową konfigurację:

```bash
cp -R config.example/. config/
# Edytuj config/config.env, config/players.tsv i config/places.tsv.
bash nik.sh help
bash nik.sh --podglad daj g1 diamentowy_kilof
bash nik.sh status
```

Prywatna paczka ma uzupełnioną konfigurację. Przechowuj ją poza publicznym Gitem.
Na serwerze można umieścić zawartość paczki w `~/.nik` i dodać do `.bashrc`:

```bash
source "$HOME/.nik/nik.sh"
```

Po wczytaniu działają `nik` oraz krótkie komendy, m.in. `daj`, `d`, `encik`,
`dom`, `efekt`, `zapiszswiat`, `listaefektow` i `gracze`. W interaktywnym Bashu
pojawia się baner. Strict mode `set -Eeuo pipefail` działa w procesie CLI,
więc nie zmienia opcji powłoki użytkownika.

## Używanie

```bash
nik                         # pomoc
nik encik --pomoc
przedmioty                  # pełna lista
szukaj diament
encik co                    # zaklęcia, poziomy i opisy
efekt co                    # efekty
d g1 jajo_creepera
d g1 "żelazny miecz" 1
encik g1 diamentowy_miecz ostrosc:5 naprawa
efekt g1 sila 60              # poziom I na 60 s
efekt g1 sila 60 2            # poziom II
nik wyposaz g1 walka --podglad
nik wyposaz g1 walka --potwierdz
```

Nazwy Skróty i nazwy graczy zależą od Twojego `players.tsv`.
`config.example` używa `gracz1/g1` i `gracz2/g2`.

Wszystkie opcje opisują `nik help` i `nik KOMENDA --pomoc`. Opcje mogą wystąpić
przed lub po komendzie; `--` kończy ich rozpoznawanie. `--podglad` waliduje
konfigurację i argumenty, ale nie łączy się z Dockerem ani nie zapisuje danych.
Dla przywracania sprawdza także lokalne archiwum i jego sumę SHA256.
`--potwierdz` jest wymagane dla `wyposaz`, `wyczysc`, `kick`, `grzmot`, `wybuch`,
`restartmc`, `przywroc` i `log_rotacja`.

Tab działa dla `nik daj`, `daj`, `d` i pozostałych skrótów. Dopasowuje również
fragment nazwy, stare aliasy oraz angielskie ID. `daj g1 jajo_` + Tab pokazuje
pasujące jaja; `daj g1 przyzy` + Tab także je znajduje, ale przedstawia krótkie
nazwy. W interaktywnym Bashu włączane jest `show-all-if-ambiguous`.

## Ważne zachowania komend

- `encik` daje nowy przedmiot. Nie zastępuje rzeczy w ręce. Zaklęte książki
  otrzymują `stored_enchantments`. Zgodność przedmiotu, konflikty i maksymalne
  poziomy są sprawdzane według definicji gry.
- `wyposaz` zastępuje wskazane sloty. Cały zestaw jest walidowany przed zmianami;
  główna ręka nie jest używana jako slot roboczy. Dostępne są zestawy `walka`,
  `kopanie` i `budowniczy`. Dozwolone są też rzeczy bez zaklęć.
- `zamroz` usuwa stare efekty slowness/jump_boost i nakłada własne modyfikatory
  `nik:frozen` na movement_speed oraz jump_strength. Nie zmienia bazowych
  atrybutów gracza i nie daje Jump Boost. Blokada trwa do `odmroz`, również po
  ponownym logowaniu. Nie jest blokadą teleportacji, lotu kreatywnego ani fizyki;
  ponowne dodanie Jump Boost przez inne narzędzie może umożliwić skakanie.
- `odmroz` usuwa modyfikatory NIK oraz slowness i jump_boost z dawnej implementacji.
  Inne efekty pozostają. Powtórzenie zamrażania/odmrażania jest obsługiwane;
  brak usuwanego efektu lub modyfikatora nie przerywa operacji.
- `zdrowie` korzysta z poziomów, które nie przepełniają obliczeń leczenia.
  Numery poziomów w `efekt` zaczynają się od I, czyli 1. Dla efektów
  natychmiastowego leczenia/obrażeń ograniczono poziomy, aby uniknąć przepełnienia.
- `tp g1 '~' '~1' '~'` wylicza pozycję względem gracza. Nazwane miejsca zawierają
  wymiar. Migracja domu/zamku z v1 przyjmuje overworld, bo v1 nie zapisywało wymiaru.
- `wybuch` przyzywa zapalonego creepera z zerowym lontem; wymaga `--potwierdz`.
- `restartmc` sprawdza uruchomienie kontenera, nie pełną gotowość gry.
  Do jej sprawdzenia użyj `nik status`.

## Nazwy i zgodność

Usunięto zbędne fragmenty nazw jaj, płyt i szablonów. Wszystkie stare nazwy
pozostają aliasami. Przykłady:

| Stara nazwa | Krótka nazwa |
|---|---|
| jajo_przyzywajace_creepera | jajo_creepera |
| jajo_przyzywajace_krowe | jajo_krowy |
| szablon_kowalski_silence_armor_trim_smithing_template | szablon_silence |
| plyta_muzyczna_music_disc_pigstep | plyta_pigstep |

`jajo_niuchacza` to naturalne jajo; przyzywanie używa `jajo_niuchacza_spawn`.
`zolwie_jajko` to naturalne jajo żółwia, a `jajo_zolwia` jest przyzywające.
`chain` i `lancuch` wskazują obecnie `iron_chain`; nazwa główna to `zelazny_lancuch`.
Minecraft zmienił ten ID i wprowadził osobne warianty miedziane.

Akceptowane są polskie znaki, wielkie litery, myślniki i spacje w cudzysłowie.
Działają aliasy `neterytowy_kilof`, `stol_zaklec`, `crafting` czy `spawn_creepera`.
Nie dodano niejednoznacznego `kilof`, który ukrywałby wybór materiału.
Nazwy wariantów miedzi zachowują informacje o utlenieniu i woskowaniu.
Pełne zmiany: `data/item-renames.tsv`; migracje ID: `data/item-id-migrations.tsv`.

## Konfiguracja

Domyślny katalog to `config/` obok skryptu. Zmień go opcją `--konfiguracja KATALOG`
lub zmienną `NIK_CONFIG`. `config.env` zawiera literalne `KLUCZ=wartość`:
bez cudzysłowów, `source`, `eval` i rozwijania `$HOME`. Zapisuj pliki z końcami LF.

| Klucz | Domyślnie | Znaczenie |
|---|---|---|
| CONTAINER | minecraft | Kontener |
| TIMEOUT | 10 | Sekundy na jedno wywołanie Docker/RCON, 1–300 |
| LOG | katalog stanu użytkownika/nik/nik.log | Absolutna ścieżka logu |
| LOG_DAYS | 30 | Retencja przy `nik log_rotacja --potwierdz` |
| COMPONENTS | modern | Format komponentów; legacy dla składni 1.20.5–1.21.4 |

Format legacy zmienia tylko składnię komponentów, nie gwarantuje zgodności
katalogu 26.3 ze starszymi grami.

Kolumny TSV są rozdzielone tabulatorem:

- `players.tsv`: nazwa, skrót, nick Minecraft.
- `places.tsv`: nazwa, X, Y, Z, wymiar, np. `minecraft:overworld`.
- `sets/NAZWA.tsv`: slot, przedmiot, opcjonalne zaklęcia rozdzielone spacjami.

Walidacja wykrywa niekompletne dane, konflikty nazw i skrótów, powtórzone nicki,
nieprawidłowe współrzędne oraz kolizje miejsc z graczami. Nazwy `co` i `lista`
są zarezerwowane. Zestawy obsługują inventory.0–26, hotbar.0–8, armor.* i weapon.*.
Przy migracji: `python3 tools/migrate-v1.py STARY_PLIK NOWY_KATALOG`.
Migrator nie wykonuje starego skryptu i nie nadpisuje istniejącej konfiguracji.

## Kolory i listy

Listy są posortowane i wyrównane. Zaklęcia mają kolumny **Zaklęcie | Max | Opis**,
efekty **Nazwa PL | ID | Opis**. Opisy zawijają się pod swoją kolumną.
Dla bardzo wąskich terminali stosowany jest układ pionowy.
`NIK_COLOR=auto/always/never` steruje kolorami; `NO_COLOR` wyłącza je automatycznie.
Potoki domyślnie nie zawierają kodów ANSI. Przewijanie z kolorami:

```bash
NIK_COLOR=always nik przedmioty | less -R
```

Wyjście z `less`: q. Dane dla Tab zawsze pozostają bez kolorów.

## Obsługa błędów i logi

Błąd Docker/RCON lub rozpoznany komunikat błędu gry przerywa operację. Nie ma
ponowień mogących zduplikować przedmioty. Pusta lub wyłącznie kolorowa odpowiedź
nie jest uznawana za potwierdzenie. Dopuszczone braki efektu/modyfikatora przy
ich usuwaniu są rejestrowane jako NOOP. Reguły błędów opierają się na angielskich
komunikatach vanilla; inne języki i pluginy mogą wymagać rozszerzenia wzorca.

Wielokrokowe komendy nie są transakcją: wcześniejsze zmiany nie są cofane po
błędzie kolejnego kroku. Log zapisuje START/OK/NOOP/ERROR, ma uprawnienia 600,
a zapis i rotacja korzystają z `flock`. Brak możliwości zapisania START blokuje
zmianę świata. Rotacja jest jawna. Kody: 0 sukces, 2 błędne użycie/konfiguracja,
1 błąd gry lub brak potwierdzenia; błędy narzędzi zachowują kod, np. timeout 124.

## Architektura, dane i rozszerzenia

`nik.sh` ładuje moduły `lib/`: konfigurację, resolvery, komunikację RCON,
komendy, kolory i tabele. `completion.sh` oraz `banner.sh` obsługują sesję Bash.
Dane i reguły są oddzielone w `data/`; prywatne ustawienia w `config/`.
`nik_register` przechowuje funkcję, składnię, opis i wymóg potwierdzenia.
Pomoc i lista komend powstają z tego rejestru.

Rozszerzenia są zaufanym kodem i ładują się tylko jawnie:

```bash
mkdir -p /tmp/nik-extensions
cp extensions/example.sh.example /tmp/nik-extensions/hello.sh
nik --rozszerzenia /tmp/nik-extensions hello
```

Rejestracja: `nik_register nazwa funkcja 0 'składnia' 'opis'`. Flaga 1 wymaga
potwierdzenia. Korzystaj z resolverów i `nik_rcon`; każdy krok sekwencji
sprawdzaj przez `|| return "$?"`.

Rejestry wygenerowano oficjalnym `net.minecraft.data.Main --reports` z używanego
pliku Mojang 26.3. Polskie nazwy nowych przedmiotów pochodzą z pliku językowego
Mojang, którego SHA1 zweryfikowano względem oficjalnego indeksu zasobów.
Reguły zaklęć rozwinięto z supported_items, exclusive_set i max_level.
Metadane źródeł: `data/catalog-source.txt` i `data/enchantment-rules-source.txt`.
Pomocnicze narzędzia: `tools/update-catalog.py` oraz `tools/update-enchantment-rules.py`.

Źródła: [wydanie 26.3](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3),
[zmiana komponentów w 1.21.5](https://www.minecraft.net/en-us/article/minecraft-java-edition-1-21-5),
[modyfikatory atrybutów](https://feedback.minecraft.net/hc/en-us/articles/27439697297421-Minecraft-Java-Edition-Snapshot-24w21b).

## Testy i paczki

```bash
bash tests/check.sh
```

CI uruchamia `bash -n`, ShellCheck, audyt danych i Bats. Testy używają atrapy
Docker/RCON; obejmują walidację, wszystkie reguły zaklęć, idempotencję zamrażania,
timeouty, odpowiedzi gry, tabele, Tab i prywatność paczek. Patrz `VALIDATION.md`.

`tools/package.py --out DIST --private-config KATALOG` buduje publiczny i prywatny
ZIP. Publiczny pomija konfigurację oraz pliki sekretów; prywatny zawiera tylko
jawnie wskazaną konfigurację. Prywatny plik powstaje z uprawnieniami 600.
Pakowanie jest niezależne od historii Gita. Kod pochodzi z dotychczasowego NIK;
nie dodano nowej licencji projektu.

### Polskie nazwy zaklęć

Wszystkie 43 zaklęcia mają polskie nazwy z gry, bez spacji i ze znakami `_`:
`ostrosc`, `naprawa`, `niezniszczalnosc`, `jedwabny_dotyk`, `szczescie`.
Angielskie nazwy nadal działają i można mieszać oba języki w jednej komendzie.
Akceptowane są też polskie znaki: `ostrość:5`, `niezniszczalność:3`.
Nazwę ze spacjami podaj w cudzysłowie, np. `"Jedwabny dotyk"`.
`encik co` pokazuje polską i angielską nazwę, poziom maksymalny oraz opis.
Tab uzupełnia nazwy w obu językach. Poziom dopisz po dwukropku, np. `ostrosc:5`.

## Nowe funkcje w 2.1

Wszystkie widoczne opcje są po polsku. Dawne angielskie opcje pozostają aliasami:

| Polska opcja | Zgodność angielska | Znaczenie |
|---|---|---|
| `--konfiguracja KATALOG` | `--config` | Wybierz konfigurację |
| `--podglad` | `--dry-run` | Pokaż polecenia bez wykonywania |
| `--potwierdz` | `--confirm` | Potwierdź operację wymagającą zgody |
| `--pomoc` | `--help`, `-h` | Pomoc ogólna lub wybranej komendy |
| `--wersja` | `--version` | Wersja NIK |
| `--rozszerzenia KATALOG` | `--extensions` | Wczytaj własne moduły |

Możesz pisać `nik pomoc`, `nik polecenia`, a klawisz Tab podpowiada również opcje.
Literówki w nazwach poleceń, graczy, przedmiotów, zaklęć i efektów wyświetlają
maksymalnie trzy podpowiedzi. NIK nigdy nie wykonuje poprawionej komendy sam.

### Zaklinanie przedmiotu w ręce

```bash
zaklnij g1 ostrosc:5 naprawa niezniszczalnosc:3
zaklnij g1 ostrosc:5 --podglad
```

`zaklnij` zmienia rzecz w głównej ręce; `encik` nadal daje nową rzecz.
NIK sprawdza wszystkie nowe zaklęcia przed pierwszą zmianą. Minecraft sprawdza,
czy pasują do trzymanej rzeczy oraz jej istniejących zaklęć. Komenda zatrzymuje
się po błędzie. Wcześniejsze zaklęcia z tej samej komendy mogą już być dodane.

### Tryby gracza

```bash
kreatywny g1
przetrwanie g1
obserwator g1
przygodowy g1
```

Zmieniają wyłącznie tryb wskazanego gracza. Świat i tryby pozostałych graczy
pozostają bez zmian. Przed zmianą możesz dopisać `--podglad`.

### Własne ulubione zestawy

```bash
zestaw zapisz wyprawa diamentowy_miecz pochodnia=64 pieczona_wolowina=32
zestaw lista
zestaw pokaz wyprawa
zestaw g1 wyprawa --podglad
zestaw g1 wyprawa
```

`zestaw` daje zapisane przedmioty do ekwipunku bez nadpisywania slotów. Zachowuje
się jak kilka poleceń `daj`: przy pełnym ekwipunku gra może upuścić przedmioty.
Nazwa jest unikalna; zapis istniejącego zestawu jest odrzucany. Maksymalnie
36 pozycji, każda 1–2304 sztuki. Dane trafiają do prywatnego
`config/favorites/`, wykluczonego z publicznej paczki i Gita.
Dotychczasowe zestawy slotów i zaklęć nadal obsługuje `wyposaz`.

### Kopie i przywracanie świata

```bash
zapiszswiat                         # zapis bieżącego świata; bez archiwum
kopia --podglad                     # opis bez zatrzymywania serwera
kopia                              # utwórz osobne archiwum
kopia lista
przywroc ID_KOPII --podglad          # sprawdź archiwum bez zmian
przywroc ID_KOPII --potwierdz
```

**`kopia` i `przywroc` na czas operacji zatrzymują kontener Minecraft.** Gracze
zostaną rozłączeni. Po zakończeniu uruchamiają go ponownie, jeśli wcześniej działał;
pełną gotowość gry sprawdza `nik status`. Operacje mają wspólną blokadę, aby
nie wykonywały się równolegle. Każde przywracanie najpierw tworzy kopię bieżącego świata.

Kopie zawierają dane świata wskazanego przez `level-name` w `/data/server.properties`,
wraz z wymiarami w jego katalogu oraz oddzielnymi katalogami `_nether` i `_the_end`,
jeśli istnieją. Wymagany jest trwały, zapisywalny wolumen Docker pod `/data`
i Python 3.11+ wewnątrz obrazu Minecraft. Używany jest już zainstalowany obraz:
kontener pomocniczy nie pobiera obrazu i nie ma sieci. Podczas tworzenia kopii
widzi wolumen tylko do odczytu. Przywracanie zachowuje właściciela plików świata.

Archiwa `.tar.gz`, manifesty i sumy SHA256 znajdują się w `~/.nik/world-backups/`
(obok `nik.sh`, również przy innej lokalizacji instalacji). Uprawnienia: katalog
700, nowe pliki 600. Kopie nie są wysyłane do Gita ani publicznej paczki.
Nie są automatycznie kasowane. Archiwum z błędną sumą, dowiązaniem, plikiem
specjalnym lub ścieżką poza światem jest odrzucane przed zatrzymaniem serwera.

Kopia obejmuje świat i graczy zapisanych w świecie. Nie archiwizuje całego kontenera,
konfiguracji serwera, plików pluginów ani zewnętrznych baz danych. Pełny dysk,
błąd Dockera lub przerwanie mogą uniemożliwić operację; kopia stanu sprzed
przywracania pozostaje dostępna. Jeśli ponowne uruchomienie kontenera się nie uda,
użyj `nik status` i sprawdź logi Dockera. Wymuszone zabicie procesu lub awaria
hosta wymagają ręcznej kontroli kontenera. Kopie na tym samym dysku warto
przechowywać również na innym nośniku.

## Status wersji

**NIK v2 jest rozwijaną wersją. NIK v1 jest archiwalny i nie jest dalej rozwijany.**
Kod i dokumentację v1 zachowano w repozytorium w `archive/v1/`.

## Pozycja, powrót i wiadomości — nowe w 2.2

```bash
gdzie g1
tp g1 gracz2
powrot g1

tata g1 "Franek, czas na kolację!"
wiadomosc g1 "Świetna budowla! ♥"  # ta sama funkcja
```

`gdzie` odczytuje X/Y/Z, wymiar i kierunek patrzenia gracza online. Nie teleportuje.
`tp`, `dom`, `zamek` i `dolacz` zapisują pozycję gracza sprzed udanej teleportacji,
łącznie z wymiarem, obrotem i nachyleniem. `powrot` wraca do tego punktu.
Każda kolejna udana teleportacja NIK zastępuje poprzedni punkt. Udany powrót
zużywa punkt; nieudany zachowuje go do ponownej próby. Ta funkcja nie śledzi
śmierci, portali ani teleportów wykonanych poza NIK. Punkt nie gwarantuje,
że po późniejszych zmianach świata miejsce nadal będzie bezpieczne.

Przed teleportacją NIK odczytuje pozycję, wymiar i obrót w trzech kolejnych
zapytaniach. Brak gracza lub nierozpoznana odpowiedź przerywa operację przed
teleportacją. Odczyty nie są atomowym zdjęciem stanu; poruszający się gracz
może zmienić pozycję między zapytaniami. Same współrzędne pochodzą z jednego odczytu.
Powroty są blokowane osobno dla każdego gracza, aby równoległe polecenia NIK
nie nadpisywały punktu w trakcie tej samej operacji.

Punkty przechowywane są prywatnie w `~/.nik/state/returns/` (katalog 700, pliki 600).
To stan działania, wykluczony z Gita i obu ZIP-ów; prywatny ZIP zawiera konfigurację,
a nie historię pozycji. Można wybrać inny katalog przez zmienną `NIK_STATE`
ze ścieżką absolutną. `gdzie` nie zapisuje trwałego punktu powrotu.

`tata` i `wiadomosc` wysyłają prywatny komunikat w czacie gry, tylko wskazanemu
graczu. Podpis **[Tata ♥]** jest złoty, a treść biała. Treść ma 1–512 znaków,
z polskimi znakami i emoji, bez znaków sterujących. Jest dosłownym tekstem:
`@a`, nawiasy i ciągi wyglądające jak polecenia nie stają się selektorami ani akcjami.
Wszystkie wiadomości są od Taty; komenda nie nadaje uprawnień graczowi.
Podobnie jak inne komendy NIK, treść jest zapisywana w prywatnym logu.

```bash
gdzie g1 --podglad
powrot g1 --podglad
tata g1 "Świetna robota!" --podglad
tata g1 -- "--pomoc"                # dosłowna treść przypominająca opcję
```

`--podglad` nie odpytuje gry i nie zapisuje ani nie zużywa punktu. Dla `powrot`
sprawdza istniejący prywatny plik i pokazuje docelową komendę.
Tab podpowiada graczy dla `gdzie`, `powrot`, `tata` i `wiadomosc`.

Vanilla `tellraw` nie wysyła tekstu potwierdzającego do konsoli RCON. Tylko dla
tej komendy pusta odpowiedź z poprawnym wynikiem transportu jest oczekiwana;
błędy składni, gracza i transportu nadal przerywają operację. Potwierdzenie w
terminalu oznacza poprawne wykonanie polecenia; nie jest potwierdzeniem
przeczytania wiadomości ani jej wyglądu w kliencie gry.

## Punkty, plecak, napisy i stworzenia — nowe w 2.3

```bash
punkt g1 baza                  # zapisz bieżącą pozycję i wymiar
miejsce lista
tp g1 baza
plecak g1
napis g1 "Brawo! ♥"
przywolaj g1 krowa
przywolaj co                   # pełna lista stworzeń
```

`punkt` zapisuje aktualne X/Y/Z i wymiar gracza online w prywatnym
`config/places.tsv`. Nazwa przyjmuje polskie znaki i spacje w cudzysłowie,
normalizowane jak nazwy przedmiotów, np. `"Moja baza"` → `moja_baza`.
Istniejące miejsca i nazwy kolidujące z graczami są odrzucane. Punkt nie wykonuje
teleportacji; korzysta z tych samych odczytów i ograniczeń co `gdzie`.
Teleportuj do niego zwykłym `tp`; nadal powstanie punkt powrotu.

`plecak` odczytuje listę Inventory gracza online. Pokazuje pasek szybkiego wyboru
(1–9), plecak (1–27), polskie nazwy przedmiotów, ilości i zaklęcia. Jeśli odczyt
zawiera sloty wyposażenia stosowane w starszych formatach, również je opisuje.
Nie odpytuje osobno wyposażenia i Ender Chest. Zawartość jest tylko odczytywana,
bez zmiany ekwipunku. Bardzo rozbudowane lub ucięte odpowiedzi są odrzucane,
zamiast przedstawiać częściową listę. Parser obsługuje strukturę SNBT i nie
wykonuje kodu. Podgląd nie zapisuje zawartości na dysku.

`napis` wyświetla wskazanemu graczowi duży złoty tytuł i turkusowy podpis
**Od Taty ♥**. Wygaszanie: 0,5 s pojawiania, 4 s wyświetlania, 1 s znikania
(przy 20 tickach/s). Treść ma te same ograniczenia co `tata`: 1–512 znaków,
bez znaków sterujących, jako zwykły tekst, z polskimi znakami i emoji.
Zastępuje bieżący tytuł gracza. Ustawienie czasu, podpisu i tytułu to trzy
kolejne polecenia; błąd przerywa dalsze kroki.

`przywolaj` tworzy jedno stworzenie **2 bloki w kierunku +X od gracza**, na tej
samej wysokości i w jego wymiarze. Nie daje jaja. Komenda nie szuka wolnej ani
bezpiecznej przestrzeni; wybierz miejsce z odpowiednią ilością miejsca.
Przyjmuje polską nazwę, angielskie ID lub `minecraft:ID`. Przykłady:
`krowa`/`cow`, `zelazny_golem`/`golem`, `smok_endu`/`smok`.
Lista zawiera 90 rodzajów z rejestru vanilla 26.3, odpowiadających jajom w
katalogu oraz dodatkowym przywoływalnym stworzeniom. Tab podpowiada oba języki.
Nie przyjmuje własnego NBT ani wielu stworzeń naraz.

Smok Endu i wither mogą niszczyć otoczenie; dla obu potrzebne jest
`--potwierdz`. Pozostałe stworzenia zachowują zwykłe zachowanie gry,
w tym walkę i znikanie potworów na poziomie pokojowym.

```bash
punkt g1 baza --podglad
plecak g1 --podglad
napis g1 "Brawo!" --podglad
przywolaj g1 krowa --podglad
przywolaj g1 smok --potwierdz
```

Podgląd nie odpytuje gracza, nie zapisuje miejsca i nie wykonuje zmian w grze.
Nowe miejsca pozostają tylko w prywatnej konfiguracji. Nie są publikowane w
Gicie ani paczce publicznej; trafiają do odświeżonej paczki prywatnej.

## Wygoda, ratunek i wspólne przygody — nowe w 2.4

```bash
ratunek g1                     # dom, leczenie, ognioodporność, odmrożenie
ratunek g1 baza                 # wybrane wcześniej zapisane miejsce
napraw g1                      # przedmiot w głównej ręce
pogoda slonce 10m
efekt g1 sila 1h 2
punkt lista
punkt usun baza --potwierdz
ender g1
fajerwerki g1
zadanie g1 "Zbuduj latarnię przy porcie"
zadanie g1 pokaz
zadanie g1 ksiazka
zadanie g1 gotowe
ochrona status
ochrona budowanie --podglad
ochrona budowanie --potwierdz
ochrona wylacz --potwierdz
```

### Ratunek i naprawa

`ratunek` wymaga istniejącego miejsca: domyślnie `dom`, ewentualnie nazwy podanej
jako drugi argument. Wybierz miejsce, które jest rzeczywiście bezpieczne.
Przed zmianami sprawdzana jest nazwa celu. Gracz dostaje 30 sekund odporności
na ogień, leczenie i nasycenie; potem NIK teleportuje go do celu i usuwa własną
blokadę poruszania oraz dawne efekty zamrożenia. Powstaje zwykły punkt powrotu,
który może prowadzić z powrotem do niebezpiecznego miejsca.

**Odporność chroni przed obrażeniami od ognia, ale nie zeruje licznika płonięcia.**
Płomienie mogą pozostać widoczne do ich zwykłego wygaśnięcia lub wejścia do wody.
Vanilla nie pozwala bezpośrednio zmieniać NBT gracza przez `/data`; ratunek nie
stawia wody i nie zmienia trybu gry, aby go ugasić. Jest wielokrokowy, nie
przywraca martwego gracza i może nie zdążyć ochronić go w sytuacji krytycznej.

`napraw` odczytuje SelectedItem i sprawdza zapisane uszkodzenie. Jeśli go nie ma,
nie zmienia przedmiotu. Dla uszkodzonej rzeczy wywołuje inline item modifier
`{type:"minecraft:set_damage",damage:1.0,add:false}`. W tej funkcji 1.0 oznacza
pełną trwałość. Pozostałe komponenty, nazwa, zaklęcia, liczba i typ przedmiotu
pozostają zachowane. Gracz powinien trzymać tę samą rzecz przez czas operacji.
Składnia jest sprawdzona dla 26.3; starsze wersje gry mogą używać innego formatu.

### Wygodne czasy i punkty

Czas można podawać jako sekundy bez sufiksu lub `30s`, `10m`, `1h`.
Dotyczy `efekt` i opcjonalnego czasu w `pogoda`; zakres wynosi 1–1 000 000 sekund.
`slonce` i `słońce` są odpowiednikami `czysto`. Dawne liczby i angielskie opcje
pozostają obsługiwane. Czas pogody dotyczy pogody całego świata.

`punkt lista` pokazuje nazwy, współrzędne i wymiary. `punkt usun NAZWA` wymaga
`--potwierdz`, działa pod tą samą blokadą co dodawanie i atomowo zastępuje plik
miejsc, zachowując inne wpisy. Można usunąć również `dom` i `zamek`; korzystające
z nich komendy zgłoszą później brak miejsca. Podgląd niczego nie usuwa.

### Ender Chest, fajerwerki i zadania

`ender` pokazuje 27 slotów skrzyni Endera. Odczyt jest prywatny i nie zmienia
przedmiotów. Korzysta z tego samego parsera SNBT, polskich nazw i kolorowej tabeli
co `plecak`, z osobnymi etykietami slotów 1–27.

`fajerwerki` to efekt cząsteczek firework i trzech kolorów dust, z dźwiękami
wybuchu i migotania. Jest skierowany do wskazanego gracza. Nie przywołuje
wybuchających rakiet, nie powoduje obrażeń ani nie niszczy bloków. Wygląd
cząsteczek i dźwięki zależą od ustawień i klienta gracza.

`zadanie GRACZ "TREŚĆ"` zapisuje jedno aktywne zadanie i daje książkę
**Zadanie od Taty**. Franek otwiera ją w grze jak zwykłą książkę — bez dodatkowych
uprawnień, pluginów i komendy `/trigger`. Dłuższy tekst jest dzielony na strony.
Przy pełnym ekwipunku `/give` może upuścić książkę, jak inne dawane przedmioty.

`pokaz` (także brak dodatkowego argumentu) wyświetla zapisane zadanie w terminalu;
`ksiazka` daje kolejną książkę, `gotowe` oznacza wykonanie w konfiguracji.
Status zmienia administrator; skrypt nie ocenia automatycznie budowli.
Wydane książki są dokumentami z chwili ich wydania i nie aktualizują się same.
Po zakończeniu można wydać nową książkę z aktualnym statusem. Nowe zadanie
zastępuje zakończone; aktywne trzeba wcześniej zakończyć lub usunąć.
`zadanie GRACZ usun --potwierdz` usuwa zapis, nie odbiera wcześniej wydanych książek.

Treść ma 1–512 znaków i jest dosłownym tekstem; nie staje się poleceniem ani
akcją kliknięcia. Rekordy `config/quests/` i ich blokady są prywatne. Paczka
prywatna zachowuje zadania; Git i paczka publiczna ich nie zawierają.

### Ochrona budowania

Profil dotyczy reguł świata, więc zmiana wymaga `--potwierdz`. Nie włącza się
sam przy instalacji ani wczytaniu skryptu. Przed ustawieniem zapisywane są
bieżące wartości czterech reguł:

| Reguła 26.3 | Budowanie |
|---|---|
| `minecraft:mob_griefing` | `false` |
| `minecraft:fire_spread_radius_around_player` | `0` |
| `minecraft:tnt_explodes` | `false` |
| `minecraft:projectiles_can_break_blocks` | `false` |

Wyłączenie mob_griefing wpływa też na niektóre zwykłe zachowania mobów.
Profil nie chroni przed niszczeniem przez graczy, komendami administratora ani
wszystkimi sposobami powstawania ognia. `ochrona wylacz` przywraca **zapisane
wartości**, a nie domyślne. Kolejne włączenie nie nadpisuje kopii aktywnego profilu.
Jeżeli operacja przerwie się po części zmian, kopia pozostaje do odzyskania przez
`ochrona wylacz --potwierdz`. Zachowaj ją do czasu przywrócenia reguł.
Dane znajdują się w prywatnym `state/protection/`, poza Gitem i ZIP-ami.

Nazwy reguł i zero wyłączające rozprzestrzenianie ognia potwierdza
[oficjalny opis zmian reguł](https://www.minecraft.net/en-us/article/minecraft-snapshot-25w44a).
Format inline item modifiers odpowiada
[zmianom w Minecraft 26.3](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3).

### Odświeżony wygląd

Pomoc ma minecraftową ramkę, komendy podzielone na grupy i opcje w osobnych
wierszach. Status serwera ma panel połączenia i konfiguracji. Słowniki,
ekwipunki, zadania i punkty mają wspólne nagłówki oraz kolory. Tęczowy podpis
**Dla Franka ♥ Tata** pozostaje. Układ pomocy i statusu dopasowuje się do
szerokości 40–110 znaków (`NIK_WIDTH`); długie opisy zawijają się w swojej kolumnie.
`NO_COLOR` i `NIK_COLOR=never` wyłączają kolory, a podpowiedzi Tab pozostają czyste.


## Własne scenariusze

```bash
nik scenariusz zapisz wyprawa "dzien" "zdrowie {gracz}" "daj {gracz} pochodnia 64"
nik scenariusz lista
nik scenariusz pokaz wyprawa
nik --podglad scenariusz g1 wyprawa
nik scenariusz g1 wyprawa
nik scenariusz usun wyprawa --potwierdz
```

`{gracz}` jest zastępowany wybranym graczem. W panelu użyj „Nowy plan” na pulpicie;
każdy wiersz edytora jest jedną komendą. Zapis istniejącej nazwy aktualizuje plan.
NIK sprawdza wszystkie kroki w podglądzie przed pierwszą zmianą w grze.
Wykonuje je po kolei i zatrzymuje się po błędzie; wcześniejsze zmiany pozostają.
Scenariusze nie są transakcją i nie cofają automatycznie wykonanych poleceń.

Definicje są prywatne w `config/scenarios/*.json` (600, katalog 700).
Dozwolona jest lista komend NIK, m.in. dawanie przedmiotów, leczenie, efekty,
teleporty, pogoda, napisy, wiadomości i własne zestawy. NIK parsuje kroki do tablic
argumentów; nie uruchamia kodu powłoki, `eval`, zagnieżdżonych planów ani poleceń
administracyjnych takich jak restart i przywracanie świata. Ostateczną walidację
każdego kroku nadal wykonuje oryginalna komenda NIK.

## JSON i postęp

```bash
nik --json --podglad daj g1 diament 2
nik --json plecak g1
nik --jsonl scenariusz g1 wyprawa
```

Zwykły terminal zachowuje kolorowe komunikaty i obecne skróty. `--json` zwraca
jeden obiekt: `schema: 1`, `ok`, `code`, `output`, `result`. Kod procesu pozostaje
zgodny z wynikiem komendy. `result` zawiera typowane dane dla plecaka, Endera,
scenariuszy oraz istniejących odczytów JSON; dla pozostałych komend może być null.
`output` pozostaje tekstem dla człowieka. `--jsonl` wysyła kolejne rekordy
`progress`, `output` i końcowy `result` z tym samym obiektem wyniku.

Typowane dane ekwipunku obejmują numery slotów, ID, polskie nazwy, ilości,
zaklęcia, zużycie oraz maksymalną trwałość. Komponenty odczytane z Minecrafta
mają pierwszeństwo. Gdy brak własnego maksimum, NIK może użyć danych referencyjnych
vanilla 26.1 dla znanych przedmiotów — panel oznacza je jako trwałość domyślną.
Nie zgaduje maksimum nieznanych przedmiotów. Źródło i licencja danych znajdują się
w `data/durability-source.txt` i `data/durability-LICENSE.txt`.
