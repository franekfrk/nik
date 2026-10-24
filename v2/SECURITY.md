# Prywatność i bezpieczeństwo NIK

NIK działa z uprawnieniami użytkownika uruchamiającego Dockera. Dostęp do Dockera
jest uprzywilejowany. Rozszerzenia `.sh` są zaufanym kodem tego użytkownika;
nie są uruchamiane w piaskownicy. NIK nie jest usługą dla niezaufanych klientów.

Prywatne dane należą do `config/`, `state/`, `world-backups/`, `backups/` i logów.
Oryginał v1 `nik-oryginal.sh` oraz paczki `dist/` nie należą do Gita. Publiczny
kod i `config.example/` zawierają wyłącznie przykłady. Podpis dla Franka jest
celowym elementem projektu, a nie nickiem konta ani konfiguracją serwera.

Publiczny ZIP powstaje wyłącznie z jawnego manifestu plików. Dodatkowy plik
pozostawiony w `lib/`, `data/` czy `tools/` nie zostanie automatycznie spakowany.
Pakowanie odrzuca prywatne katalogi oraz dowiązania na każdym poziomie ścieżki.
Prywatna paczka osobno dołącza podany config i ma uprawnienia 600.
Nie przesyłaj jej do publicznych wydań, zgłoszeń ani artefaktów CI.

Audyty w CI sprawdzają prywatne ścieżki śledzone w Git, nagłówki kluczy prywatnych,
manifest i granice paczek. Testy wstawiają sztuczne sekrety do plików prywatnych
oraz przypadkowych plików i sprawdzają zawartość ZIP-ów. To nie jest uniwersalny
wykrywacz sekretów: przed publikacją nadal trzeba przejrzeć diff oraz sprawdzić
wartości z rzeczywistej konfiguracji. Manifest chroni dobór plików, nie wykrywa
hasła dopisanego do dozwolonego pliku kodu. Sam `.gitignore` nie usuwa danych
już śledzonych w Git ani z historii.

Logi zawierają polecenia administracyjne, w tym prywatne wiadomości i pozycje.
Log i jego blokada mają tryb 600; separatory wierszy są zapisywane dosłownie,
a dowiązania są odrzucane. Dane stanu mają katalogi 700 i pliki 600.
Te zabezpieczenia nie tworzą granicy bezpieczeństwa wobec innego procesu
uruchomionego jako ten sam użytkownik.

Podejrzewając wyciek, najpierw unieważnij klucz/hasło. Usunięcie pliku z najnowszego
commita nie usuwa sekretu z historii ani pobranych kopii. W publicznym zgłoszeniu
opisuj błąd bez sekretów; lokalizację ujawnionych danych przekaż właścicielowi
prywatnym kanałem ustalonym poza publicznym repozytorium.

Właściciel repozytorium może dodatkowo wymagać zielonego checka `test` przez
reguły ochrony gałęzi. Sam plik workflow nie konfiguruje tych reguł GitHuba.

## Panel Mobile

Panel jest prywatnym interfejsem administratora, z uprawnieniami użytkownika NIK.
Korzysta z HTTPS Tailscale, hasła PBKDF2, cookie HttpOnly/Secure/SameSite, kontroli
Host/Origin i CSRF. Ogranicza czynności do jawnych adapterów; nie udostępnia konsoli.
Service worker zapisuje tylko publiczne zasoby oprawy. Nie zapisuje API i nie
odtwarza poleceń offline. Hasło początkowe oraz panel.json należą do config/
i nigdy do publicznego repo ani ZIP-a. Szczegóły: panel/README.md.

Opcjonalny dostęp LAN przez wskazany prywatny IPv4 używa HTTP; cookie ma wtedy HttpOnly/SameSite, bez Secure. Używaj go wyłącznie w zaufanej sieci. HTTPS/PWA pozostaje dostępne przez Tailscale.

Historia i ulubione Mobile 1.3 są wspólne dla administratorów używających hasła
panelu. Dostęp wymaga sesji; modyfikacje ulubionych także CSRF. Plik SQLite ma
uprawnienia 600, katalog 700; `state` jest wyłączony z Gita i publicznych paczek.
Historia może zawierać pozycje i ekwipunek graczy. Sesje pozostają w pamięci, więc
restart wymaga logowania. Przerwane operacje nie są odtwarzane automatycznie.

## Dane Mobile 1.4 i scenariusze

Wyniki JSON/JSONL tworzy NIK. Kanał wyniku używa prywatnego pliku tymczasowego,
odrzuca dowiązania i pliki inne niż zwykłe. Panel zachowuje wyniki i preferencje
w prywatnym SQLite; te pliki nie należą do publicznej paczki.
Scenariusze są danymi konfiguracji: argumenty przechodzą przez parser bez powłoki,
listę dozwolonych komend i podgląd NIK wszystkich kroków przed wykonaniem.
Błąd zatrzymuje kolejne kroki; już wykonane zmiany pozostają w grze.
