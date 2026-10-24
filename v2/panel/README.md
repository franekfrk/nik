# NIK Mobile 1.4 — nakładka WWW/PWA na NIK

NIK jest projektem opartym na Bashu, z polskimi komendami do Minecrafta.
Dziecko lub gracz może korzystać z terminala — np. `daj g1 diament 16` — albo
z tego panelu WWW: wybiera gracza, przedmiot i ilość, a następnie naciska
„Wykonaj”. Na telefonie panel można zainstalować jako PWA przez HTTPS.

Minecraftowy panel na telefon i komputer. Wykonuje istniejący `nik.sh` jako proces
Bash z tablicą argumentów, bez shell=True/eval i bez osobnego silnika komend.
Korzysta z tego samego configu, słowników, walidacji, RCON i logu NIK.
Python 3.11+ z biblioteką standardową wystarcza do uruchomienia. Nie wymaga Node,
instalacji pakietów pip ani usług chmurowych do obsługi komend.

## Instalacja na serwerze

Zawartość NIK v2 umieść w `~/.nik`, a swoją konfigurację w `~/.nik/config`.
Ustal prywatną nazwę urządzenia Tailscale i włącz Serve/HTTPS w sieci Tailscale.
Przykładowa domena poniżej jest wyłącznie przykładem:

```bash
python3 ~/.nik/panel/setup.py --origin https://serwer.przyklad.ts.net:6767 --port 6767
systemctl --user enable --now ~/.nik/panel/nik-panel.service
loginctl enable-linger "$USER"
sudo tailscale serve --bg --https=6767 http://127.0.0.1:6767
```

`loginctl enable-linger` zapewnia start również bez zalogowania przez SSH.
System może wymagać autoryzacji administratora dla linger lub Tailscale Serve.
Serve jest prywatne w tailnecie; nie konfiguruj Funnel dla panelu administracyjnego.
W razie istniejącej konfiguracji Serve dodawaj konkretny port, nie resetuj całej.
Certyfikat i jego odnawianie obsługuje Tailscale. Backend domyślnie nasłuchuje na
127.0.0.1:6767, a telefon otwiera adres HTTPS z pierwszej komendy przez Tailscale.
Nie ma certyfikatu samopodpisanego ani instrukcji omijania ostrzeżeń TLS.

Hasło początkowe jest generowane na serwerze:

```bash
cat ~/.nik/config/panel-password.txt
```

Plik hasła i `panel.json` mają uprawnienia 600. Hasło nie trafia do kodu ani publicznej
paczki. JSON zawiera sól i PBKDF2-SHA256 z 600000 iteracji. Plik hasła służy właścicielowi
do pierwszego logowania; po zapisaniu hasła w bezpiecznym miejscu można go usunąć.
Ponowne `setup.py` zachowuje istniejący hash hasła. Dane logowania należą do prywatnego
configu i są dołączane wyłącznie do paczki prywatnej. Dostęp oznacza uprawnienia
administratora tego NIK; panel nie ma kont/ograniczeń dla dzieci ani osobnych ról.

## Obsługa

Wybierz gracza i kategorię: pulpit, ekwipunek/stworzenia, podróże, od Taty albo świat.
Podgląd pokazuje plan bez modyfikacji gry. Zwykłe wykonanie uruchamia prawdziwą
komendę, a wynik sukcesu pojawia się dopiero po kodzie wyjścia 0.
Lista stworzeń i przedmiotów jest przeszukiwana po polsku i angielsku.
Ilości stworzeń: 1–64, przedmiotów: 1–2304. Zaklęcia mają poziomy z katalogu NIK;
zgodność zaklęć z przedmiotem nadal sprawdza NIK. Usuwanie wszystkich efektów
wymaga dodatkowego potwierdzenia w formularzu.

Czynności trafiają do jednej kolejki (do sześciu oczekujących/wykonywanych).
Można pozostawić operację w tle i sprawdzić wynik. „Zatrzymaj” kończy proces NIK,
ale nie cofa kroków wykonanych już w Minecraft. Limit jednej operacji panelu wynosi
180 sekund; kopia świata ma osobny limit 35 minut i czas na wznowienie serwera.
Tworzenie kopii wymaga potwierdzenia przerwy w grze. Przywracanie świata, restart
serwera i dowolna konsola pozostają dostępne w CLI. Trwającej kopii nie można
anulować z panelu; kolejka czeka na bezpieczne zakończenie i ponowne uruchomienie
kontenera. Jednostka systemd daje procesom 180 sekund na zamknięcie.

Identyfikator żądania zapobiega powtórzeniu tego samego zlecenia w sesji.
Po błędzie sieci panel sprawdza wynik zamiast automatycznie wysyłać komendę ponownie.
Restart usługi wymaga ponownego logowania, ale zachowuje historię i wyniki.
Niedokończone operacje są oznaczane jako przerwane z nieznanym wynikiem; panel
nie ponawia ich automatycznie. Sprawdź stan gry przed ręcznym powtórzeniem.

## PWA

Otwórz prawidłowy adres HTTPS w telefonie podłączonym do Tailscale.
Na Androidzie wybierz „Zainstaluj aplikację” w panelu lub przeglądarce.
Na iPhonie otwórz Safari: Udostępnij → Do ekranu początkowego.
Manifest, ikony 192/512 oraz service worker są częścią wydania.

Service worker zapisuje wyłącznie publiczną oprawę: HTML, JS, CSS, ikony i grafikę.
Nie zapisuje API, configu, haseł, danych graczy ani wyników komend. Bez połączenia
zostaje ekran aplikacji z informacją o braku sieci. Komendy wymagają serwera;
nie ma kolejki offline, automatycznego odtwarzania ani powiadomień push.
Wszystkie zasoby wizualne są lokalne, bez zewnętrznych fontów, CDN i analityki.

## Usługa i testy

```bash
systemctl --user status nik-panel
systemctl --user restart nik-panel
systemctl --user stop nik-panel
journalctl --user -u nik-panel -n 50
```

Usługa działa z uprawnieniami właściciela NIK i jego dostępem do Dockera.
Cookie ma HttpOnly/SameSite=Strict/Secure przy HTTPS. Żądania zmieniające stan
wymagają logowania, prawidłowego Host/Origin, JSON oraz tokenu CSRF.
Błędne logowania są ograniczane. Historia i wyniki są wspólne dla zalogowanych
administratorów używających jednego hasła panelu. Anulowanie czynności i klucze
żądań pozostają przypisane do sesji, która zleciła operację.
To panel dla zaufanego administratora w prywatnej sieci, nie usługa wieloużytkownikowa.

Testy: `python3 -m unittest discover -s tests -p test_panel.py` z katalogu v2.
Uruchamiają serwer HTTP na loopbacku, atrapę NIK oraz prawdziwy NIK w podglądzie.
Sprawdzają wszystkie adaptery czynności, logowanie/CSRF/izolację wyników,
powtórzenia żądań, błędy gry, brak dostępu do plików prywatnych i manifest PWA.
Testy nie wysyłają wiadomości prawdziwym graczom i nie przywołują stworzeń.
Node jest potrzebny tylko do kontroli składni JS w CI, nie na serwerze panelu.

## Dostęp lokalny po IP (opcjonalny)

Aby dodatkowo udostępnić panel bez Tailscale w zaufanej sieci LAN, uruchom setup
z dotychczasowym adresem HTTPS i opcją `--lan-ip ADRES_IPV4_SERWERA`, następnie
zrestartuj `systemctl --user restart nik-panel`. Panel nasłuchuje tylko na wskazanym
prywatnym IPv4 oraz loopbacku. Hasło pozostaje takie samo.

Telefon w tej samej sieci otwiera `http://ADRES_IPV4_SERWERA:6767`.
Ten dostęp używa HTTP: hasło i komendy nie są szyfrowane w LAN. Pełna instalacja
PWA i szyfrowanie nadal wymagają adresu HTTPS Tailscale. Sesje logowania dla obu
adresów są oddzielne. Nie przekierowuj portu panelu na routerze do Internetu.

## Ikonki Minecrafta (Mobile 1.1)

Katalog, menu czynności i wybór przedmiotu używają prawdziwych ikonek Minecrafta.
1657 przedmiotów i 90 stworzeń ma lokalne grafiki; w formularzu pojawia się podgląd
wybranego przedmiotu. Dwa atlasy PNG są dostarczane z panelem i cache PWA.
Nie potrzeba zewnętrznego CDN ani wysyłania zapytań o obrazki do Internetu.
Pochodzenie i autorstwo: [ASSETS.md](ASSETS.md).

## Trwała historia (Mobile 1.2)

W sekcji **Ostatnie działania** kliknij wpis, aby otworzyć zapisany wynik, również
po użyciu „Zostaw w tle”, odświeżeniu, ponownym logowaniu lub restarcie panelu.
Historia obejmuje ostatnie 100 działań z datą, graczem, statusem i wynikiem.
Przycisk „Pokaż starsze działania” rozwija kolejne wpisy, a „Odśwież” pobiera
historię z innych urządzeń. Powrót do karty również odświeża listę.

SQLite z biblioteki standardowej Pythona przechowuje historię lokalnie w
`NIK_ROOT/state/panel/history.sqlite3` (plik 600, katalog panel 700).
Nie wymaga osobnego serwera bazy. Wynik jest ograniczony do 128 KiB, jak wcześniej.
Operacje aktywne są zachowywane do zakończenia nawet przy przekroczeniu limitu
100 wpisów. Najstarsze zakończone wpisy są usuwane po przekroczeniu limitu.
Błąd zapisu nowego zlecenia blokuje wykonanie komendy; uszkodzona baza nie jest
kasowana ani zastępowana pustą bazą. Jeżeli proces zniknie przed zapisaniem wyniku,
po restarcie zobaczysz ostrzeżenie o niepewnym wyniku zamiast fałszywego sukcesu.

Historia zawiera prywatne wyniki, np. plecaki i współrzędne. Jest dostępna tylko
po logowaniu, wspólna dla telefonu i komputera administratora. Nie zawiera haseł,
cookies ani kluczy sesji. Katalog `state` jest wykluczony z publicznych paczek
oraz Gita. API historii nie trafia do cache PWA ani localStorage. Kopia prywatnej
konfiguracji nie obejmuje historii: jej kopię wykonuj przy zatrzymanym panelu,
kopiując `state/panel`. Restart panelu nie odtwarza ani nie ponawia komend.


## Ulubione, kolejka i stan świata (Mobile 1.3)

- **Ulubione:** w formularzu akcji ustaw gracza, parametry i nazwę, następnie
  „Zapisz w ulubionych”. NIK sprawdza skrót w podglądzie. Maksymalnie 24 skróty
  są zapisane prywatnie obok historii i dostępne na wszystkich urządzeniach po
  logowaniu. Kliknięcie otwiera formularz, zachowując przedmiot, ilość, zaklęcia
  i pozostałe parametry. Nie zapisuje zgody na działania wymagające potwierdzenia.
- **Historia:** filtruj po graczu, polskiej komendzie i lokalnej dacie. Wpisy
  mają osobne etykiety oczekiwania, pracy, sukcesu i błędu. Kliknięcie otwiera wynik.
- **Kolejka:** wspólna dla zalogowanych urządzeń; jeden proces NIK wykonuje akcje
  po kolei. Panel odświeża aktywne wpisy co 5 sekund, bez ponawiania komend.
- **Gracze online:** `nik stan lista json` odczytuje listę online, zdrowie w HP,
  jedzenie, tryb gry, pozycję i wymiar. Karty pokazują czas ostatniego odczytu.
  „Odśwież” zleca nowy odczyt przez NIK. Wyjście gracza podczas odczytu daje
  jawny komunikat zamiast wymyślonych wartości. Pokazywani są gracze z konfiguracji.
- **Kopie świata:** karta Świat pokazuje datę i rozmiar ostatniej kopii oraz
  ostatnie pięć archiwów z `nik kopia dane`. Przycisk wykonuje `nik kopia utworz`
  po potwierdzeniu krótkiego zatrzymania Minecrafta. Nie daje dostępu do dowolnych
  plików ani przywracania świata. Utworzone archiwa pozostają w `world-backups`.
- **Zestawy:** Ekwipunek udostępnia własne `nik zestaw GRACZ NAZWA` oraz gotowe
  `nik wyposaz GRACZ NAZWA`. Wyposażenie zastępuje sloty i wymaga potwierdzenia.

Panel nie wykonuje bezpośrednio Docker/RCON ani nie czyta plików graczy/świata.
Wszystkie dane Minecrafta i kopii pochodzą z komend NIK. SQLite przechowuje tylko
stan interfejsu: historię i ulubione. Odczyty graczy i kopii również trafiają do
kolejki i historii. Po wejściu panel odtwarza ostatni odczyt; użyj przycisku
odświeżania, aby uzyskać aktualne dane. Gdy nie ma jeszcze odczytu, zleca pierwszy.


## Graficzny plecak, postęp i własne plany (Mobile 1.4)

„Zajrzyj do plecaka” i „Skrzynia Endera” pokazują sloty z lokalnymi ikonami.
Kliknij rzecz, aby przeczytać zaklęcia, ilość i trwałość. Wyposażenie pochodzi
z odczytu NIK, również z nowego pola equipment. Wynik tekstowy pozostaje dostępny
pod przyciskiem. Stare wpisy historii, które zawierają tylko tekst, nadal się otwierają.

Panel odczytuje strumień JSONL z NIK: wyświetla faktyczne komunikaty postępu
i narastający wynik tekstowy, a po zakończeniu zachowuje dane graficzne w historii.
Odświeżenie strony lub otwarcie wyniku na innym urządzeniu nie ponawia komendy.

Przy ulubionej akcji użyj ołówka, aby zmienić nazwę, gracza i parametry. Formularz
w tym trybie zapisuje ustawienia; nie wykonuje akcji w Minecraft. Strzałki zmieniają
kolejność przycisków. Potwierdzenia wykonania nie są zapamiętywane w skrócie.

Katalog ma gwiazdki i filtry „Ulubione” oraz „Ostatnie wybory”, osobno dla rzeczy
i stworzeń. Do 100 gwiazdek i ostatnie 40 wyborów przechowuje prywatna baza panelu.

Na pulpicie „Nowy plan” otwiera edytor scenariusza NIK. Jedna komenda w wierszu,
1–12 kroków, a `{gracz}` oznacza wybranego gracza. Kliknięcie zapisanego planu
pozwala go uruchomić dla wskazanego gracza; ołówek edytuje definicję. Zapis planu,
walidacja i wykonanie są komendami NIK. Definicje znajdują się w prywatnym configu.

Bashowy NIK odpowiada za parsowanie SNBT, trwałość, scenariusze i wykonanie.
`panel/server.py` uruchamia jego CLI, a `enhancements.js` prezentuje przekazane
wyniki. Katalog oraz układ ulubionych są ustawieniami interfejsu. Hasła, historia,
preferencje i własne scenariusze nie trafiają do publicznego repozytorium ani ZIP-a.

Podczas działania zadania w tle można otwierać wyniki zakończonych działań.
Postęp i zakończenie zadania w tle nie zastępują aktualnie oglądanego wyniku.
Do bieżącej operacji wrócisz przez jej wpis w kolejce.

## Kolejka, powtarzanie i edytor scenariuszy (Mobile 1.5)

Po „Zostaw w tle” wybieraj następne akcje. Każda ma własny identyfikator i wynik;
panel śledzi je osobno także po odświeżeniu. Przyjętych może być do sześciu zadań,
wykonywanych kolejno. Zadania nie są ponawiane automatycznie.
Przy oczekującym wpisie użyj „Anuluj”. Zwolni to miejsce w kolejce bez wywołania
NIK. Administrator zalogowany tym samym wspólnym hasłem może anulować oczekujące
zadanie z innej sesji; zatrzymanie uruchomionego procesu jest dostępne jego sesji.

„Powtórz — sprawdź ustawienia” otwiera formularz, zachowuje tryb podglądu z wpisu
i pozwala zmienić parametry. Potwierdzenie nie jest przechowywane. Historia
zapisuje parametry wyłącznie w prywatnym SQLite; lista historii ich nie pobiera.
Starsze wpisy bez tych danych nie oferują powtórzenia.

Kroki planu przesuwasz strzałkami; dodajesz i usuwasz wiersze. W oknie uruchamiania
scenariusza „Sprawdź plan bez zmian w grze” zleca NIK --podglad. Wynik każdego
kroku ma rozwijane szczegóły. Polskie komunikaty błędów pochodzą z NIK, a surowe
odpowiedzi gry pozostają dostępne do diagnozy.

## End

W „Teleport do punktu” wybierz „End — lądowanie na powierzchni”. Panel wywołuje
`nik tp GRACZ end`. NIK dobiera podłoże przez mechanizm Minecrafta i zapisuje
punkt powrotu. Przy utracie RCON zobaczysz informację o niepewnym wyniku i
zapisanej pozycji wyjściowej. Po odzyskaniu połączenia użyj „Wróć na miejsce”.

## Nether

W „Teleport do punktu” wybierz „Nether — bezpieczne lądowanie”. Panel uruchamia
`nik tp GRACZ nether`; sonda, walidacja podłoża i punkt powrotu należą do NIK.
Tryb podglądu opisuje plan bez tworzenia sondy ani zmian w świecie.

## Zwykły świat

W „Teleport do punktu” wybierz „Zwykły świat — bezpieczne lądowanie”.
Nakładka wywołuje `nik tp GRACZ swiat`; wybór miejsca, walidacja i powrót
pozostają w NIK. Podgląd nie tworzy sondy ani nie przenosi gracza.
