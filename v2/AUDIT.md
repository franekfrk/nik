# Audyt NIK 2.12.1 — 25 października 2026

Przegląd objął dyspozytor Bash i sourcing, konfigurację i nazwy, transport RCON,
teleporty i prywatny stan, scenariusze, obsługę kopii w izolowanych testach,
HTTP, uwierzytelnianie, kolejkę, trwałą historię, frontend/PWA oraz pakowanie.
Panel pozostaje nakładką: polecenia Minecrafta wykonuje wyłącznie NIK.

## Znalezione i naprawione

| Problem | Poprawka i dowód w testach |
|---|---|
| Zabicie procesu podczas teleportacji mogło pozostawić pozycję tylko w anonimowym pliku, którego `powrot` nie odnajdywał. Podobnie działał błąd końcowego przeniesienia pliku po udanym RCON. | Nazwany prywatny dziennik `returns/GRACZ.inflight.json` powstaje przed wysłaniem ruchu. Test zabija całą grupę procesów SIGKILL w trakcie mockowego RCON; kolejny `powrot` odzyskuje pozycję. Osobny test symuluje błąd `mv`. |
| `powrot` wybierał plik awaryjny przed uzyskaniem blokady, więc mógł nie zauważyć nowego zapisu utworzonego podczas oczekiwania. | Wybór po blokadzie; test tworzy dziennik podczas blokowania równoległego powrotu i sprawdza rzeczywiste argumenty teleportacji. |
| End polegał wyłącznie na natywnym tagu podłoża, który nie wyklucza każdego bloku zadającego obrażenia. | End korzysta z sondy i dozwolonych podłoży, jak pozostałe wymiary. Test magmy blokuje ruch gracza; podłoże i dwa bloki powietrza są kontrolowane ponownie w komendzie teleportacji. |
| Anulowanie po zapisaniu stanu „wykonuje się”, lecz przed `Popen`, nadal uruchamiało NIK. | Sprawdzenie anulowania i uruchomienie procesu pod tą samą blokadą. Test anuluje dokładnie w tym oknie i potwierdza brak uruchomienia procesu. |
| Równoległe błędne logowania mogły przejść sprawdzenie limitu, zanim pierwszy kosztowny hash został policzony. | Rezerwacja próby przed PBKDF2 pod blokadą; z 12 jednoczesnych prób 5 dociera do sprawdzenia hasła, 7 otrzymuje 429. |
| Odziedziczony `PYTHONOPTIMIZE` wyłączał asercje stosowane w walidatorach Python. | Osobny proces CLI usuwa tę zmienną przed uruchomieniem helperów. Test potwierdza odrzucenie błędnej pozycji; `source` zachowuje środowisko powłoki użytkownika. |
| Pozycja i wymiar pochodziły z osobnych odpowiedzi; przejście gracza przez portal pomiędzy nimi mogło połączyć dane dwóch światów. | Wymiar jest odczytywany przed i po pozycji. Wykryta zmiana przerywa odczyt przed ruchem. Test zachowuje poprzedni punkt i potwierdza brak teleportacji. |

## Wdrożenie — dodatkowa znaleziona kopia

Stara kopia v1 w katalogu domowym serwera zawierała prywatne ustawienia i miała
tryb 664. Po upewnieniu się, że pliki startowe powłoki z niej nie korzystają,
została przeniesiona do prywatnego `.nik/backups/audit-legacy-*/` z trybem 600.
Suma SHA256 przed i po operacji potwierdziła zachowanie identycznej treści.
Lokalny oryginał v1 również ma tryb 600. Nie zmieniano haseł ani danych graczy.

## Prywatność i weryfikacja

- Publiczna paczka korzysta z jawnego manifestu. Prywatne configi, historia,
  logi, punkty powrotu i kopie pozostają poza Gitem i publicznym ZIP-em.
- Skan rzeczywistych prywatnych nicków, ustawień i wykrytych sekretów nie znalazł
  dopasowań w bieżących plikach ani w 357 unikalnych tekstowych blobach historii
  publicznej gałęzi sprzed wydania. Skan jest celowany, nie wykrywa każdego
  możliwego sekretu. Nie publikuje samych wartości.
- Kontrole wydania: Bash-n, ShellCheck, audyty katalogów i manifestu, 160 testów
  Python, 276 Bats i 8 JavaScript. Testy awarii używają mocków i prywatnych fixture'ów.
- Testy na serwerze obejmują status, sourcing i podgląd oraz sondę lądowania.
  Nie obejmują teleportowania graczy, zatrzymywania produkcyjnego świata ani
  przywracania produkcyjnych kopii. Codzienny cron pozostaje bez zmian.

## Granice

RCON i zapis lokalny nie tworzą jednej transakcji. Dziennik odzyskiwania chroni
przed przerwaniem procesu; nie jest gwarancją trwałości przy fizycznej awarii dysku.
Po niepewnym wyniku nie ma automatycznego ponowienia ruchu. `powrot` najpierw
odczytuje `inflight`, następnie `uncertain`, a na końcu zwykły punkt. Nowa
teleportacja z istniejącym dziennikiem wymaga najpierw odzyskania przez `powrot`.
Przy utracie RCON sprzątanie wymuszonego ładowania chunka może czekać na następne
użycie tego wymiaru. Normalne zagrożenia gry i późniejsze zmiany bloków pozostają.
