# shellcheck shell=bash
declare -A NIK_HANDLERS=() NIK_DESTRUCTIVE=() NIK_USAGE=() NIK_DESCRIPTIONS=()
nik_register() {
    (($# == 5)) || nik_die 'Rejestr komend wymaga pięciu pól.'
    nik_id "$1"
    [[ $2 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && $3 =~ ^[01]$ && ( $4 == "$1" || $4 == "$1 "* ) && -n $5 ]] || nik_die 'Błędne metadane komendy.'
    [[ ! -v NIK_HANDLERS[$1] ]] || nik_die "Powtórzona komenda: $1"
    declare -F "$2" >/dev/null || nik_die "Brak funkcji obsługi: $2"
    NIK_HANDLERS[$1]=$2; NIK_DESTRUCTIVE[$1]=$3; NIK_USAGE[$1]=$4; NIK_DESCRIPTIONS[$1]=$5
}
nik_registry_validate() {
    local name
    for name in "${!NIK_HANDLERS[@]}"; do
        nik_id "$name"
        [[ ${NIK_DESTRUCTIVE[$name]:-} =~ ^[01]$ && ( ${NIK_USAGE[$name]:-} == "$name" || ${NIK_USAGE[$name]:-} == "$name "* ) && -n ${NIK_DESCRIPTIONS[$name]:-} ]] || nik_die "Niespójny rejestr: $name"
        declare -F "${NIK_HANDLERS[$name]}" >/dev/null || nik_die "Brak funkcji komendy: $name"
    done
}
nik_registry() {
    nik_register prowadz nik_cmd_guide 0 'prowadz GRACZ MIEJSCE [CZAS]' 'Kierunek i odległość w grze co 2 s; domyślnie 60 s, Ctrl+C kończy.'
    nik_register odliczanie nik_cmd_countdown 0 'odliczanie GRACZ SEKUNDY [TEKST]' 'Kolorowe odliczanie 1–60 sekund i duży napis na koniec.'
    nik_register losuj nik_cmd_random 0 'losuj GRACZ' 'Wylosuj zadanie z własnej listy i daj książkę od Taty.'
    nik_register nagroda nik_cmd_reward 0 'nagroda GRACZ NAZWA | lista' 'Daj zestaw nagród i wyświetl gratulacje od Taty.'
    nik_register przepis nik_cmd_recipe 0 'przepis PRZEDMIOT' 'Składniki i układ wytwarzania z oficjalnych receptur 26.3.'
    nik_register menu nik_cmd_menu 0 'menu' 'Kolorowe menu: wybierz gracza, kategorię i czynność.'
    nik_register ratunek nik_cmd_rescue 0 'ratunek GRACZ [MIEJSCE]' 'Ratunek do domu lub punktu: ochrona przed ogniem, odmrożenie i leczenie.'
    nik_register napraw nik_cmd_repair 0 'napraw GRACZ' 'Napraw trzymany przedmiot z zachowaniem jego danych.'
    nik_register ender nik_cmd_ender 0 'ender GRACZ' 'Podgląd skrzyni Endera wskazanego gracza.'
    nik_register fajerwerki nik_cmd_fireworks 0 'fajerwerki GRACZ' 'Kolorowy pokaz cząsteczek i dźwięku bez obrażeń.'
    nik_register zadanie nik_cmd_quest 0 'zadanie GRACZ [TREŚĆ | pokaz | ksiazka | gotowe | usun]' 'Zadanie od Taty w prywatnej książce, do odczytu w grze.'
    nik_register ochrona nik_cmd_protection 0 'ochrona [status | budowanie | wylacz]' 'Profil reguł świata; zmiany wymagają --potwierdz.'

    nik_register punkt nik_cmd_point 0 'punkt GRACZ NAZWA | lista | usun NAZWA' 'Zapisz aktualną pozycję gracza jako nazwane miejsce.'
    nik_register plecak nik_cmd_inventory 0 'plecak GRACZ' 'Czytelny podgląd przedmiotów i zaklęć w plecaku.'
    nik_register napis nik_cmd_title 0 'napis GRACZ TREŚĆ...' 'Duży złoty tytuł z podpisem Od Taty ♥.'
    nik_register przywolaj nik_cmd_summon 0 'przywolaj GRACZ STWORZENIE [ILOŚĆ] | co' 'Przywołaj 1–64 stworzenia (domyślnie jedno); boss wymaga --potwierdz.'

    nik_register gdzie nik_cmd_where 0 'gdzie GRACZ' 'Pokaż pozycję, wymiar i kierunek gracza online.'
    nik_register powrot nik_cmd_back 0 'powrot GRACZ' 'Wróć do pozycji sprzed ostatniej udanej teleportacji NIK.'
    nik_register tata nik_cmd_dad 0 'tata GRACZ TREŚĆ...' 'Prywatna, kolorowa wiadomość od Taty w czacie gry.'
    nik_register wiadomosc nik_cmd_dad 0 'wiadomosc GRACZ TREŚĆ...' 'Wiadomość od Taty; odpowiednik tata.'

    nik_register zaklnij nik_cmd_enchant_hand 0 'zaklnij GRACZ ZAKLĘCIE[:POZIOM]...' 'Zaklnij przedmiot w głównej ręce; nie daje nowego.'
    nik_register kreatywny nik_cmd_creative 0 'kreatywny GRACZ' 'Tryb kreatywny wskazanego gracza, w tym samym świecie.'
    nik_register przetrwanie nik_cmd_survival 0 'przetrwanie GRACZ' 'Tryb przetrwania wskazanego gracza.'
    nik_register obserwator nik_cmd_spectator 0 'obserwator GRACZ' 'Tryb obserwatora wskazanego gracza.'
    nik_register przygodowy nik_cmd_adventure 0 'przygodowy GRACZ' 'Tryb przygodowy wskazanego gracza.'
    nik_register zestaw nik_cmd_favorite 0 'zestaw lista | pokaz NAZWA | zapisz NAZWA ITEM[=ILOŚĆ]... | GRACZ NAZWA' 'Zapisuj i dawaj ulubione zestawy; zachowuje rzeczy w ekwipunku.'
    nik_register kopia nik_cmd_backup 0 'kopia [utworz|lista|dane]' 'Archiwum świata; krótko zatrzymuje i uruchamia serwer.'
    nik_register przywroc nik_cmd_restore 1 'przywroc ID_KOPII' 'Przywróć świat po kopii bieżącego; wymaga --potwierdz, rozłącza graczy.'

    nik_register daj nik_cmd_give 0 'daj GRACZ ITEM [ILOŚĆ]' 'Daj przedmiot (1–2304 szt.).'
    nik_register encik nik_cmd_enchant 0 'encik GRACZ ITEM ZAKLĘCIE[:POZIOM]... | co' 'Daj nowy zaklęty przedmiot; zaklęcia po polsku lub angielsku.'
    nik_register wyposaz nik_cmd_equip 1 'wyposaz GRACZ [ZESTAW]' 'Nadpisz wskazane sloty zestawu; wymaga --potwierdz.'
    nik_register tp nik_cmd_tp 0 'tp GRACZ end|CEL | GRACZ X Y Z' 'Teleport do miejsca, gracza lub współrzędnych.'
    nik_register dom nik_cmd_home 0 'dom GRACZ' 'Teleport do domu.'
    nik_register zamek nik_cmd_castle 0 'zamek GRACZ' 'Teleport do zamku.'
    nik_register dolacz nik_cmd_join 0 'dolacz GRACZ GRACZ' 'Teleport do drugiego gracza.'
    nik_register miejsce nik_cmd_place 0 'miejsce lista | dodaj NAZWA X Y Z WYMIAR' 'Lista i zapis miejsc.'
    nik_register efekt nik_cmd_effect 0 'efekt GRACZ EFEKT [CZAS] [POZIOM] | co' 'Dodaj efekt (domyślnie 30 s, poziom I).'
    nik_register usun nik_cmd_remove 0 'usun GRACZ EFEKT' 'Usuń jeden efekt.'
    nik_register wyczysc nik_cmd_clear 1 'wyczysc GRACZ' 'Usuń wszystkie efekty; wymaga --potwierdz.'
    nik_register zdrowie nik_cmd_health 0 'zdrowie GRACZ' 'Ulecz i nasyć gracza.'
    nik_register zamroz nik_cmd_freeze 0 'zamroz GRACZ' 'Zablokuj chodzenie i zwykłe skoki do odmroz.'
    nik_register odmroz nik_cmd_thaw 0 'odmroz GRACZ' 'Usuń blokadę NIK i stare efekty zamrażania.'
    nik_register kick nik_cmd_kick 1 'kick GRACZ [POWÓD...]' 'Wyrzuć gracza; wymaga --potwierdz.'
    nik_register grzmot nik_cmd_lightning 1 'grzmot GRACZ' 'Przywołaj piorun; wymaga --potwierdz.'
    nik_register wybuch nik_cmd_explosion 1 'wybuch GRACZ' 'Przywołaj wybuch; wymaga --potwierdz.'
    nik_register restartmc nik_cmd_restart 1 'restartmc' 'Restart kontenera; wymaga --potwierdz.'
    nik_register zapisz nik_cmd_save 0 'zapisz' 'Zapisz świat.'
    nik_register dzien nik_cmd_day 0 'dzien' 'Ustaw dzień i czystą pogodę.'
    nik_register noc nik_cmd_night 0 'noc' 'Ustaw noc.'
    nik_register pogoda nik_cmd_weather 0 'pogoda slonce|deszcz|burza [CZAS]' 'Zmień pogodę, opcjonalnie na 30s, 10m, 1h.'
    nik_register burza nik_cmd_storm 0 'burza' 'Rozpocznij burzę.'
    nik_register online nik_cmd_online 0 'online' 'Pokaż graczy online.'
    nik_register status nik_cmd_status 0 'status' 'Sprawdź konfigurację, kontener i RCON.'
    nik_register diagnoza nik_cmd_status 0 'diagnoza' 'Diagnostyka połączenia i konfiguracji.'
    nik_register scenariusz nik_cmd_scenario 0 'scenariusz lista|pokaz NAZWA|zapisz NAZWA KROK...|usun NAZWA|GRACZ NAZWA' 'Własny plan 1–12 komend NIK; walidacja wszystkich kroków przed wykonaniem.'
    nik_register stan nik_cmd_player_status 0 'stan [GRACZ|lista] [json]' 'Stan online, zdrowie, jedzenie, tryb i pozycja; tylko odczyt.'
    nik_register gracze nik_cmd_players 0 'gracze' 'Lista skonfigurowanych graczy.'
    nik_register gracz_lista nik_cmd_players 0 'gracz_lista' 'Lista skonfigurowanych graczy (zgodność v1).'
    nik_register przedmioty nik_cmd_items 0 'przedmioty' 'Słownik PL → EN.'
    nik_register szukaj nik_cmd_search 0 'szukaj FRAZA' 'Szukaj przedmiotów po PL/EN.'
    nik_register log_rotacja nik_cmd_rotate 1 'log_rotacja' 'Usuń stare wpisy logu; wymaga --potwierdz.'
}
