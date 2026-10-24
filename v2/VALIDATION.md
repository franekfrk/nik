# NIK v2 — audyt i weryfikacja, 2026-10-24

Wynik kontroli kodu lokalnie i na serwerze: **229/229 testy Bats**, `bash -n`, ShellCheck 0.11.0,
`py_compile` narzędzi Python i audyt całego katalogu danych.

## Znalezione i poprawione problemy

| Obszar | Poprawka i dowód |
|---|---|
| Zamrażanie | Usunięto Jump Boost 250. Używane są odwracalne modyfikatory `nik:frozen` dla movement_speed i jump_strength. Bazowe wartości atrybutów pozostają bez zmian. |
| Odmrażanie | Nieobecny efekt/modyfikator jest obsługiwanym NOOP; operacja nie przerywa przed usunięciem reszty blokady. Testowane powtórzone zamroz/odmroz na modelu stanu serwera. |
| Leczenie | Instant Health używa w grze 32-bitowego przesunięcia `4 << amplifier`. Dla 255 daje ono 0. Zastąpiono je skończonym poziomem 10; nasycenie używa 20. Zweryfikowano kod klasy vanilla HealOrHarmMobEffect. |
| Zaklęcia | Ręczne kategorie zastąpiono 715 regułami przedmiotów i 27 parami konfliktów wygenerowanymi z vanilla 26.3. Test obejmuje wszystkie reguły i konflikty. |
| Polskie zaklęcia | 43 nazwy z oficjalnego pliku pl_pl.json; stare angielskie nazwy nadal działają. Testy wszystkich odpowiedników, polskich znaków, poziomów, konfliktów i Tab. |
| Brakujące zaklęcie | Dodano lunge, razem ze wspieranymi włóczniami. Łącznie 43 zaklęcia. |
| Zaklęte książki | Używają stored_enchantments, zamiast komponentu zaklinającego sam przedmiot. |
| Wybuch | Creeper ma Fuse:0s oraz ignited:1b; zerowy lont bez zapalenia nie gwarantował natychmiastowego wybuchu. Zweryfikowano zapis pól klasy Creeper. |
| Efekty | Poziom I odpowiada amplifier 0. Dodano jawny parametr poziomu i ograniczenie dla natychmiastowego leczenia/obrażeń. Przywrócono opisy efektów. |
| Wyposażenie | inventory ma zakres 0–26, hotbar 0–8. Poprawiono walidację i dopuszczono rzeczy bez zaklęć. |
| Konfiguracja | Wykrywane są kolizje miejsc z graczami oraz zarezerwowane nazwy co/lista. |
| RCON | Rozpoznawane są rzeczywiste angielskie błędy gry i odpowiedzi z ANSI. Wyłącznie kolorowa odpowiedź nie jest potwierdzeniem. Nazwa gracza Unknown w prawidłowej liście nie oznacza błędu. |
| Podpowiedzi | Działają aliasy daj/d, fragmenty nazw i globalne opcje --konfiguracja/--podglad. Dane podpowiedzi nigdy nie zawierają ANSI. |
| Listy | Zaklęcie, max i opis mieszczą się w jednej tabeli. Opisy zawijają się pod kolumną; bardzo wąski terminal używa kart. |
| Kolory | Wspólna paleta pomocy, list, banera, statusów i błędów. Tęczowy podpis Dla Franka ♥ Tata. Brak dawnego dopisku o skrótach v1. |
| Prywatność paczek | Wykluczono klucze i sekrety także z podkatalogów źródeł. ZIP powstaje najpierw w prywatnym pliku tymczasowym, potem jest atomowo podmieniany. |

## Kompletność danych

Rejestry wygenerowano offline z pliku Mojang 26.3 przez
`net.minecraft.data.Main --reports`, bez uruchamiania świata Minecraft.
Polskie tłumaczenia pobrano przez oficjalny manifest i indeks zasobów Mojang;
sprawdzono SHA1. Dane zaklęć i tagów odczytano z tej samej wersji vanilla.

- 1658 wpisów rejestru item; katalog NIK zawiera **1657 przedmiotów**, z wyłączeniem air.
- **43 zaklęcia**, zgodne maksymalne poziomy, obsługiwane przedmioty i konflikty.
- **40 efektów**, zgodnie z rejestrem mob_effect.
- 119 skróconych nazw jaj/płyt/szablonów; dodatkowo doprecyzowany żelazny łańcuch.
- Stare nazwy działają jako aliasy. Zmiana game ID chain → iron_chain ma jawną migrację.
- Naturalne jajo niuchacza pozostaje odróżnione od jaja przyzywającego.

Sumy źródeł zapisano w `data/catalog-source.txt` i `data/enchantment-rules-source.txt`.
`tools/audit-items.py` kontroluje zgodność całego katalogu z rejestrem oraz integralność aliasów i reguł.

Sprawdzono także oficjalne źródła internetowe:
[wydanie 26.3](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3),
[zmiany identyfikatorów modyfikatorów](https://feedback.minecraft.net/hc/en-us/articles/27439697297421-Minecraft-Java-Edition-Snapshot-24w21b),
[zmiany operacji atrybutów](https://feedback.minecraft.net/hc/en-us/articles/24531969592077-Minecraft-Java-Edition-Snapshot-24w09a).

## Granice kontroli

Testy integracyjne używają modelu Docker/RCON; sprawdzono też odczyty z prawdziwego
serwera. Nie wykonywano teleportacji, rozdawania rzeczy, leczenia, wybuchów ani
zamrażania gracza w celu testów. Wybrane mechanizmy potwierdzono odczytem danych
oraz bytecode używanej wersji gry. Zachowanie klienta Bedrock/Geyser wymaga
potwierdzenia w grze przez użytkownika.

Komendy wielokrokowe przerywają po błędzie, ale nie cofają już wykonanych zmian.
Rozpoznawanie komunikatów dotyczy angielskich odpowiedzi vanilla; niestandardowe
pluginy lub datapacki mogą wymagać dodatkowych reguł. Blokada atrybutów nie jest
blokadą lotu kreatywnego, teleportacji ani fizyki; nowy Jump Boost z innego źródła
może znów umożliwić skakanie. NIK nie utrzymuje cyklicznej pętli nad graczem.

Dodatkowo prawdziwy parser Minecrafta 26.3 przyjął 25 wygenerowanych poleceń (m.in. item replace, enchantments, stored_enchantments, atrybuty i efekty). Kontrola negatywna odrzuciła nieistniejący item. Każde polecenie było poprzedzone execute as @s, a wcześniej odczytem potwierdzono brak encji @s dla konsoli RCON; żadna próba nie wykonała zmian na graczu. Log na serwerze: ~/.nik/logs/vanilla-parser-check.log.

## Rozszerzenia 2.1

Dodano zaklinanie rzeczy w ręce, cztery tryby gry gracza, własne zestawy dawane
bez nadpisywania slotów, podpowiedzi literówek i polskie opcje z aliasami angielskimi.
Testy Bats obejmują nowe komendy, walidację całego zestawu przed wykonaniem,
kontrolę błędów gry i uzupełnianie Tab.

Testy Python uruchamiają rzeczywisty kod archiwizacji i przywracania na
izolowanym modelu Dockera oraz osobnym katalogu świata. Obejmują zgodność zawartości,
kopię przed przywracaniem, zastępowanie starych plików, osobne wymiary,
błędne archiwum, dowiązania, wyjście poza katalog, błąd archiwizacji, błąd
przywracania z odtworzeniem poprzedniego stanu, ponowny start i zachowanie
pierwotnie zatrzymanego kontenera. Testy nie przywracają produkcyjnego świata.

Dodatkowa próba na prawdziwym Dockerze, w osobnym kontenerze i sztucznym świecie,
potwierdziła utworzenie archiwum, sumę SHA256, kopię przed przywracaniem,
przywrócenie zawartości, usunięcie plików nienależących do kopii, zachowanie UID
właściciela i ponowny start. Kontener oraz pliki testowe usunięto. Produkcyjny
Minecraft nie był zatrzymywany. Parser produkcyjnego Minecrafta przyjął ponadto
7 nowych poleceń (4 tryby i 3 zaklęcia), a odrzucił kontrolę negatywną.
Wykorzystano kontekst execute as @s po potwierdzeniu braku encji konsoli;
żadnemu graczowi nie zmieniono trybu ani przedmiotu.

## Rozszerzenia 2.2

Dodano `gdzie`, `powrot`, `tata` i `wiadomosc`. 13 nowych testów Bats sprawdza
odczyt pozycji, wszystkie ścieżki teleportowania, powrót z wymiarem i kierunkiem,
prywatność plików, błędy gracza, zachowanie punktu po błędzie, podgląd bez skutków
ubocznych, uszkodzony stan i dowiązania oraz treść wiadomości jako dosłowny JSON.
7 nowych testów Python obejmuje parser odpowiedzi RCON, precyzję współrzędnych,
notację wykładniczą, nieprawidłowe liczby/wymiary, tożsamość punktu i bezpieczne
komponenty wiadomości.

Kod TellRawCommand z oficjalnego pliku Mojang 26.3 potwierdza brak sendSuccess:
polecenie wywołuje ServerPlayer.sendSystemMessage i zwraca wynik bez tekstu RCON.
Dodano wyłącznie dla tellraw obsługę spodziewanej pustej odpowiedzi. Zwykłe
komendy nadal odrzucają puste odpowiedzi. Testy wiadomości nie wysyłają treści
prawdziwym graczom. Powroty są testowane na modelu; produkcyjnym graczom nie
zmieniano pozycji w celu weryfikacji.

Rzeczywisty parser Minecraft 26.3 przyjął dodatkowo 5 poleceń: odczyty Pos,
Dimension, Rotation, powrót do innego wymiaru z obrotem i tellraw ze znakami
polskimi, cudzysłowami i symbolem ♥. Kontrola negatywna została odrzucona.
Polecenia uruchomiono za execute as @s po sprawdzeniu, że konsola nie ma encji;
nie zmieniły pozycji graczy i nie wysłały im wiadomości. W chwili kontroli nie
było skonfigurowanego gracza online, więc rzeczywisty odczyt jego danych i wygląd
wiadomości w kliencie pozostają do potwierdzenia w grze. Log parsera:
`~/.nik/logs/features-22-parser-check.log`.

## Rozszerzenia 2.3

Dodano punkt, plecak, napis i przywolaj. 15 nowych testów Bats obejmuje odczyt
punktu z wymiarem, konflikty nazw, puste i ucięte ekwipunki, polskie nazwy,
ilości i zaklęcia, wąski terminal, kolory, treść tytułów, błędy gry, przywoływanie
stworzeń PL/EN, ochronę bossów i kompletność słownika.
9 nowych testów Python sprawdza SNBT: zagnieżdżenia, tablice typowane,
cudzysłowy i Unicode, sloty, liczniki współczesne i dawne, zaklęte książki,
nieznane przedmioty oraz odrzucanie uszkodzonego i nadmiernie złożonego wejścia.

Sprawdzono oficjalny kod Mojang 26.3 dla Inventory.save i ItemStackWithSlot;
slot zapisuje się jako Slot, a przedmiot jest serializowany przez kodek ItemStack.
Sloty wyposażenia spoza listy Inventory nie są osobno odpytywane. Zbudowano
słownik 90 stworzeń na podstawie istniejących jaj, rejestru entity_type i pl_pl.json.
Źródła opisuje data/creatures-source.txt.

Dodatkowa kontrola rzeczywistego parsera Minecrafta 26.3 przyjęła 94 polecenia:
90 przywołań różnych typów stworzeń, odczyt Inventory i trzy kroki wyświetlenia
tytułu. Kontrola z nieistniejącym stworzeniem została odrzucona. Polecenia
poprzedzono execute as @s po potwierdzeniu braku encji konsoli. Nie przywołano
stworzeń i nie wyświetlano nic prawdziwym graczom. Log:
`~/.nik/logs/features-23-parser-check.log`. W czasie kontroli żaden skonfigurowany
gracz nie był online; wygląd napisu i rzeczywisty odczyt jego plecaka wymagają
potwierdzenia w kliencie gry. Testy parsera SNBT korzystają z danych testowych.

## Rozszerzenia 2.4

Dodano ratunek, naprawę w ręce, czasy s/m/h, listę i usuwanie punktów,
podgląd EnderItems, dekoracyjne fajerwerki, zadania w książkach i odwracalny
profil reguł świata. Nowy moduł ui.sh grupuje pomoc, zawija opisy i buduje
panele dopasowane do terminala. Zachowano kolory, NO_COLOR, tęczowy podpis,
skróty, opcje PL/EN oraz uzupełnianie Tab.

17 nowych testów Bats obejmuje jednostki czasu i błędy, plan i kolejność ratunku,
naprawę tylko komponentu uszkodzeń, Ender Chest, potwierdzanie usuwania miejsc,
zadania i prywatne pliki, odporność na błędy wydania książki, ochronę reguł,
odzyskanie po częściowej awarii, kontekstowe podpowiedzi i układ 40-kolumnowy.
7 nowych testów Python sprawdza tożsamość prywatnych rekordów, dosłowną treść
książek, stronicowanie, oryginalne wartości reguł i odrzucanie uszkodzonego stanu.

Uruchomiono dodatkowy serwer vanilla 26.3 w osobnym kontenerze, bez sieci i
publikowanych portów, z osobnym światem. Na prawdziwym silniku sprawdzono:
- naprawę miecza z damage 500 do 0 przy identycznych pozostałych danych,
  w tym zaklęciach, nazwie, typie, liczbie i custom_data;
- zapis książki z zadaniem jako written_book_content z polskimi znakami;
- włączenie czterech reguł przez prawdziwe CLI i dokładne przywrócenie ich wartości.

Przedmioty trzymał testowy armor stand; testy nie zastępowały ekwipunku gracza.
Po próbach kontener i świat zostały usunięte. Log wyniku na serwerze:
`~/.nik/logs/features-24-real-game-check.log`. Produkcyjny świat nie był zmieniany.
Silnik i parser nie potwierdzają wyglądu książki, cząsteczek ani dźwięku w
kliencie Bedrock/Geyser; ten zakres wymaga wejścia gracza do gry.

Dodatkowo produkcyjny parser Minecrafta przyjął 27 wygenerowanych poleceń,
w tym czasy pogody i efektów, naprawę inline, odczyt EnderItems, cząsteczki,
dźwięki, książkę i reguły. Kontrola negatywna z dawnym polem function zamiast
type została odrzucona. Użyto execute as @s po potwierdzeniu braku encji
konsoli, więc nie wykonano zmian w produkcyjnym świecie. Log:
`~/.nik/logs/features-24-parser-check.log`. Układ pomocy obejrzano także na
kolorowym renderze 80-kolumnowym i sprawdzono testami w szerokości 40 znaków.
Ramki używają podstawowych znaków box drawing, bez wymagania fontu emoji.

## Rozszerzenia 2.5 — menu, prowadzenie i zabawa

Pełny zestaw obejmuje 213 testów Bats i 51 testów Python oraz bash -n, ShellCheck
0.11.0 i audyt danych. Nowe testy obejmują kierunki względem patrzenia, odległość,
różnicę wysokości, niezgodny wymiar, zatrzymanie po błędzie, podgląd bez zapisu,
walidację czasu/tekstu, sekwencję odliczania, losowanie i blokadę nadpisania
aktywnego zadania, prywatne nagrody, pełną walidację zestawu przed dawaniem,
błędy RCON, ścieżki/dowiązania, Tab i renderowanie wszystkich stałych wyników
z 2042 oficjalnych receptur Minecraft 26.3.

Pięć testów uruchamia rzeczywiste menu Bash w pseudoterminalu: wybór gracza,
wyjście, formularz odliczania z podglądem, anulowanie, zmiana gracza, odzyskanie
po błędzie oraz dosłowne traktowanie znaków powłoki w treści. Nie wykonują
komend wobec prawdziwych graczy. Podgląd wyglądu wygenerowano z faktycznego
wyjścia ANSI menu przy szerokości 76 kolumn.

Parser produkcyjnego Minecraft 26.3 przyjął 13 nowych wariantów poleceń title/give;
celowo błędne polecenie kontrolne zostało odrzucone. Sprawdzono pusty kontekst
konsoli execute as @s, dlatego test nie wysłał wiadomości prawdziwym graczom,
nie dał im nagród i nie zmienił świata. Test parsera nie potwierdza wyglądu
na ekranie klienta Bedrock/Java; geometria prowadzenia ma osobne testy jednostkowe.
Przed wdrożeniem zachowywana jest kopia zmienianych plików, prywatny config
pozostaje na miejscu, a po wdrożeniu sprawdzany jest nik status.

## Stabilizacja 2.5.1

Zestaw rozszerzono do 229 testów Bats i 58 testów Python. Testy regresji obejmują:
nieobsłużony błąd w podstawieniu komendy, zachowanie opcji/shopt/pułapek powłoki
po source, walidację metadanych i aliasów rejestru, nicki Unknown/Cannot,
prywatne uprawnienia logu/blokady, dowiązanie blokady, błąd zegara audytu,
separatory w logu, limit oczekiwania na blokadę oraz proces Docker ignorujący TERM.

Siedem testów pakowania używa rzeczywistych archiwów ZIP i sztucznych sekretów.
Sprawdzają rozdzielenie configu, wykluczenie przypadkowego pliku spoza manifestu,
prywatne katalogi, ścieżki ../ i absolutne, duplikaty, dowiązania katalogów,
brak pliku wydania oraz zachowanie poprzedniego archiwum po błędzie.
Kontrola Git wykrywa śledzony plik prywatny i nowy plik poza manifestem.
Fixture testów kopiuje wyłącznie pliki z manifestu, nigdy katalog instalacji
z rzeczywistymi ustawieniami, logami lub kopiami świata.

Testy nie dowodzą braku wszystkich możliwych sekretów w kodzie. CI kontroluje
jawne granice wydania; przed publiczną publikacją wykonywany jest również audyt
wartości z rzeczywistej konfiguracji. Ochrona gałęzi GitHub wymaga osobnego
ustawienia po stronie właściciela repozytorium.

Dodatkowo pięć testów potwierdza opcjonalną ilość przywoływanych stworzeń:
brak ilości oznacza jedno, liczba jest wykonywana dokładnie (w tym wiodące zera),
błędna ilość nie wywołuje gry, bossy zachowują potwierdzenie, błąd zatrzymuje
sekwencję, a lista i Tab zachowują poprawne argumenty.

## NIK Mobile / wydanie 2.6

Dodano 23 testy panelu: adaptery i walidację wszystkich czynności, opcjonalne ilości,
bezpieczne argumenty dla prawdziwego nik.sh, logowanie, rate limit, cookie Secure,
Host/Origin, CSRF, idempotencję zleceń, statusy wyjścia procesu, izolację wyników
sesji, wylogowanie, CSP, brak dostępu do prywatnych ścieżek oraz zasoby PWA.
Wszystkie czynności sprawdzono z prawdziwym nik.sh w podglądzie i atrapą Dockera.
Łącznie: 229 testów Bats i 81 testów Python. JavaScript ma kontrolę składni w CI.

Widok panelu sprawdzono w przeglądarce przy szerokości 390 px oraz na komputerze.
Formularz przywołania wygenerował dokładnie sześć komend w podglądzie, bez
modyfikacji świata. Zasoby oprawy działają z cache service workera; API nie jest
zapisywane i nie ma odtwarzania komend offline. Instalacja na fizycznym telefonie
wymaga działania użytkownika w przeglądarce; nie jest symulowana testem backendu.

Na wdrożeniu sprawdzono rzeczywisty HTTPS, pełną weryfikację łańcucha i nazwy
certyfikatu, TLS 1.3, logowanie i metadane prywatnej konfiguracji, podglądy
1/3/12 stworzeń, idempotencję oraz rzeczywisty nik status przez usługę.
Testy nie wysłały wiadomości do graczy ani nie przywołały stworzeń.
Usługa użytkownika jest włączona i ma linger, a Tailscale Serve obsługuje HTTPS.
Hasła/hash/origins i pozostały prywatny config są wykluczone z publicznego wydania.

## Poprawka 2.6.1 — skracane odpowiedzi ekwipunku

Minecraft może zakończyć tekstową odpowiedź `/data get` wielokropkiem w połowie
SNBT. `plecak`, `ender` oraz odczyt uszkodzenia w `napraw` pobierają wtedy mniejsze
pola. Parser nadal odrzuca nieprawidłowe odpowiedzi i sprawdza sloty, ilości,
identyfikatory oraz poziomy zaklęć. Wszystkie odczyty używają istniejącego transportu,
limitów czasu i dziennika operacji. Odczyt rozbudowanego plecaka może potrwać dłużej.
Testy obejmują skrócone listy, przedmioty i mapy zaklęć, puste pola, starszy format,
uszkodzenie przedmiotu oraz brak modyfikacji ekwipunku. Zestaw: 231 testów Bats,
89 testów Python. Rzeczywisty plecak i skrzynia Endera sprawdzone bez zmian w grze.

## NIK 2.6.2 — lokalne ikonki Minecrafta

Panel Mobile 1.1 ma atlas dla wszystkich 1657 przedmiotów i 90 stworzeń,
indywidualne ikonki w katalogu, minecraftowe ikonki czynności i podgląd wyboru.
Testy sprawdzają pełne pokrycie katalogu, granice atlasów, publiczne trasy HTTP,
cache PWA i brak zmian w ochronie API. Grafiki są publiczne i nie zawierają danych
konfiguracji ani graczy.

Kontrola: 231 testów Bats i 92 testy Python (w tym 26 testów panelu), bash -n, ShellCheck i kontrola składni JavaScript. Ikonki i podgląd sprawdzono w przeglądarce dla szerokości 390 px i widoku desktop.

Sprawdzono też zamknięcie okna przez „Zostaw w tle” i ponowne otwarcie zakończonego wyniku z klikalnej historii. Odczyt historii nie wysyła ponownie polecenia. Wyniki pozostają w pamięci bieżącej strony.

## NIK 2.7.0 — trwała historia panelu

Historia ostatnich 100 działań wraz z wynikami jest przechowywana prywatnie
w SQLite. Testy obejmują ponowne logowanie, odtworzenie bazy i App, niepewny
wynik przerwanych zadań bez ponawiania, retencję, równoległe zapisy, uprawnienia,
dowiązania, uszkodzoną bazę, brak miejsca przed zleceniem i kontrolę dostępu HTTP.
Przeglądarka nie przechowuje wyników w localStorage ani cache PWA.

## NIK 2.7.0 — nakładka na komendy NIK

Ulubione przechodzą walidację NIK w podglądzie; zapis nie wykonuje akcji gry
i nie zachowuje zgody na nadpisywanie slotów ani zatrzymanie serwera. Adaptery
kopii i graczy wywołują wyłącznie nik.sh. Testy stanów graczy używają atrapy Dockera
i sprawdzają brak operacji zapisu. Odczyt metadanych kopii jest testowany na
prawdziwych archiwach izolowanego świata testowego. Trwającej kopii nie można
anulować przez API panelu.

Wydanie zweryfikowane: 118 testów Python i 231 testów Bats, bash -n, ShellCheck
oraz składnia app.js/sw.js. Na homelabie `nik stan lista json` poprawnie odczytał
komplet danych rzeczywistego gracza online. Po kontrolowanym restarcie usługi
i nowym logowaniu zachowano identyczny wynik podglądu plecaka oraz ulubione;
SQLite integrity_check i uprawnienia 600/700 przeszły kontrolę. W przeglądarce
sprawdzono odtworzenie parametrów ulubionej akcji, filtrowanie po komendzie,
odświeżenie historii i potwierdzenie kopii świata. Test archiwizacji używa
izolowanego świata, bez zatrzymywania produkcyjnego Minecrafta.

## Wydanie 2.8.0 / Mobile 1.4

W lokalnym pełnym przebiegu: 149 testów Python, 231 testów Bats, bash -n,
ShellCheck oraz audyt 125 publicznych plików. Nowe testy obejmują JSON/JSONL,
pełny i skrócony SNBT, wyposażenie, trwałość komponentu, pusty plecak i Ender,
błędy RCON, scenariusze i zatrzymanie po błędzie, migrację starego SQLite,
edycję i kolejność skrótów oraz trwałość preferencji katalogu.
Interfejs sprawdzono także w przeglądarce z atrapą Docker/RCON.

Odczyt rzeczywistego serwera potwierdził 38 zajętych slotów. Wykryto też zmianę
slotów podczas sekwencyjnego odczytu; NIK ponawia taki odczyt raz i przy dalszej
niespójności zwraca jasny błąd bez częściowego wyniku graficznego.

## Poprawka podglądu wyników podczas zadania w tle

Sześć testów JavaScript sprawdza otwieranie historii podczas pracy, zachowanie
wyniku po zakończeniu zadania w tle, powrót do jego postępu, spóźnione odpowiedzi
HTTP, błąd transportu i odpowiedź przychodzącą po wylogowaniu.

## Wydanie 2.9.0 / Mobile 1.5

154 testy Python, 8 testów JavaScript oraz 231 testów Bats obejmują m.in.
niezależne śledzenie wielu operacji, zachowanie widoku historii, zapis parametrów
bez potwierdzeń i nieznanych pól, anulowanie kolejki bez wywołania NIK,
natychmiastowe zwolnienie jej miejsca i wyścig z uruchomieniem zadania.
Testy interfejsu w przeglądarce potwierdzają dodawanie drugiego zadania w tle,
anulowanie oczekującego, formularz powtórzenia, zmianę kolejności i zapis kroków,
podgląd NIK oraz rozwijane wyniki kroków. Operacje zmieniające grę testowano
na atrapie Docker/RCON; serwer produkcyjny sprawdzany jest odczytami i podglądem.
