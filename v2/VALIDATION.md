# NIK v2 — audyt i weryfikacja, 2026-10-24

Wynik kontroli kodu lokalnie i na serwerze: **147/147 testy Bats**, `bash -n`, ShellCheck 0.11.0,
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

12 testów Python uruchamia rzeczywisty kod archiwizacji i przywracania na
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
