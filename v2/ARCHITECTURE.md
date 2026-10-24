# Architektura NIK v2

`nik.sh` ma dwa tryby. Wczytanie przez `source` instaluje funkcję uruchamiającą
osobny proces Bash, aliasy, completion i baner. Nie zmienia opcji `set`, `shopt`
ani pułapek w powłoce użytkownika. Wykonanie CLI ustawia `set -Eeuo pipefail`
i `shopt -s inherit_errexit` przed wczytaniem modułów. Wszystkie moduły domeny
wykonują się w tym samym modelu; nie są samodzielnymi programami.

| Warstwa | Pliki i odpowiedzialność |
|---|---|
| Uruchomienie i parser | `nik.sh`, `lib/cli.sh`: opcje, rozszerzenia, wybór komendy |
| Rejestr | `lib/registry.sh`: handler, użycie, opis i obowiązek potwierdzenia; walidacja po rozszerzeniach |
| Konfiguracja | `lib/config.sh`: parser danych bez source/eval, walidacja i konflikty |
| Nazwy i reguły | `players.sh`, `items.sh`, `enchantments.sh`, `effects.sh`, katalog `data/` |
| Transport | `lib/rcon.sh`: Docker, timeout, błędy transportu i semantyka odpowiedzi |
| Domena | `commands.sh`, `extras.sh`, `travel.sh`, `adventures.sh`, `family.sh`, `play.sh` |
| Prezentacja | `colors.sh`, `ui.sh`, `help.sh`, `display.sh`, `banner.sh`, `menu.sh` |
| Integracja z powłoką | `completion.sh`: aliasy wywołują CLI; nie omijają walidacji/rejestru |
| Dane strukturalne | narzędzia Python: parsery SNBT/JSON, stan prywatny, kopie świata, pakowanie |

Pomoc, lista komend i wykonanie korzystają z rejestru. `help/pomoc`,
`commands/polecenia`, `__complete` i opcje to wbudowane operacje parsera,
a nie operacje domeny. Menu uruchamia osobny CLI dla wybranej komendy.
Nie każda funkcja `nik_cmd_*` jest osobną komendą: część obsługuje podkomendy.
Subkomendy zmieniające świat (np. ochrona) sprawdzają potwierdzenie po rozpoznaniu
operacji. Flaga rejestru obejmuje komendy zawsze wymagające potwierdzenia.

## Model błędów

- 0: powodzenie lub rozpoznany, idempotentny brak zmiany.
- 1: lokalny błąd wykonania lub błąd semantyczny zwrócony przez grę.
- 2: błędne dane, konfiguracja, niespełnione wymagania lub brak potwierdzenia.
- 75: przekroczony czas oczekiwania na blokadę danych.
- Status transportu jest zachowywany, m.in. 124 dla timeoutu i 137 dla
  wymuszonego zakończenia po dodatkowych 2 sekundach. Procesy przerwane
  sygnałem mogą zwracać standardowe 128 + numer sygnału. Nieobsłużone błędy
  innych narzędzi również zachowują swój status.

Strict mode nie jest mechanizmem transakcji. Bash wyłącza `errexit` w testowanych
warunkach (`if`, `&&`, `||`, `!`), również we wnętrzu wywołanej tam funkcji.
Dlatego oczekiwane błędy transportu i operacji wieloetapowych mają jawne
sprawdzanie statusu. Nie uruchamiaj całej logiki domeny pod `if handler`.
`inherit_errexit` zapobiega maskowaniu nieobsłużonych błędów w `$(...)`.
Nieoczekiwane błędy trafiają do pułapki ERR bez drukowania całej komendy,
która może zawierać prywatny tekst.

Transport nie ponawia automatycznie mutacji: timeout nie dowodzi, że serwer
nie wykonał polecenia. Operacje sekwencyjne mogą zakończyć się częściowym sukcesem.
Wiadomości o błędzie opisują ten fakt; kopie świata mają osobny mechanizm
odzyskiwania i dłuższe, osobne limity operacji Docker (do 1800 sekund dla
archiwizacji). Lokalny log nie jest transakcją z Minecraftem.

## Utrzymanie

`bash tests/check.sh` uruchamia bash -n, ShellCheck, audyty danych/paczki,
testy Python oraz Bats. CI wykonuje ten sam zestaw na push i pull_request.
Nowa komenda wymaga rejestracji, walidacji, pomocy i testów ścieżki błędu.
Nowy plik wydania trzeba świadomie dodać do `tools/public-files.json`.
Testy parsera na serwerze nie zastępują oceny wyglądu w kliencie gry.
