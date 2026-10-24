# NIK Mobile 1.0

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
180 sekund. Złożone kopie/przywracanie świata, restart serwera i dowolna konsola
nie są udostępnione w tej wersji panelu; pozostają dostępne w CLI.

Identyfikator żądania zapobiega powtórzeniu tego samego zlecenia w sesji.
Po błędzie sieci panel sprawdza wynik zamiast automatycznie wysyłać komendę ponownie.
Restart usługi usuwa pamięć sesji/kolejki/wyników; wymaga ponownego logowania.
Historia na ekranie jest tylko bieżącą sesją, a pełny prywatny log operacji prowadzi NIK.

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
Błędne logowania są ograniczane, a wyniki operacji należą do konkretnej sesji.
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
