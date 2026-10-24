# shellcheck shell=bash
nik_menu_row() {
    local number=$1 text=$2 line first=1
    nik_ui_width
    while IFS= read -r line; do
        if ((first)); then nik_message 1 gold '  [%s]  ' "$number"; first=0
        else printf '       '; fi
        nik_message 1 command '%s\n' "$line"
    done < <(nik_ui_lines "$text" "$((NIK_UI_WIDTH-8))")
}
nik_menu_read() {
    local prompt=$1
    nik_message 1 gold '  %s › ' "$prompt"
    IFS= read -r REPLY || return 1
    [[ $REPLY != *$'\e'* ]] || { nik_message 2 error 'Wpisz tekst bez znaków sterujących.\n'; return 1; }
}
nik_menu_player() {
    local name choice index=1
    local -a names=()
    nik_panel 'WYBIERZ GRACZA' 'Numer i Enter • 0 wraca'
    while IFS= read -r name; do
        names+=("$name"); nik_menu_row "$index" "$name"; index=$((index+1))
    done < <(printf '%s\n' "${!NIK_PLAYERS[@]}" | LC_ALL=C sort)
    nik_menu_read 'Gracz' || return 1; choice=$REPLY
    [[ $choice =~ ^[0-9]{1,3}$ ]] || return 1
    index=$((10#$choice)); ((index>=1 && index<=${#names[@]})) || return 1
    NIK_MENU_PLAYER=${names[index-1]}
}
nik_menu_field() {
    nik_menu_read "$1" || return 1
    [[ -n $REPLY ]] || REPLY=${2:-}
    [[ -n $REPLY ]]
}
nik_cmd_menu() {
    nik_args 0 "$@"
    [[ -t 0 && -t 1 ]] || nik_die 'Menu wymaga terminala. Użyj nik pomoc albo konkretnej komendy.'
    local NIK_MENU_PLAYER='' category choice command confirm rc key item amount
    local -a commands=() args=() options=()
    nik_menu_player || return 0
    while :; do
        nik_panel 'NIK — wspólna przygoda' "Gracz: $NIK_MENU_PLAYER • wybierz numer i naciśnij Enter"
        nik_section 'CO DZIŚ ROBIMY?'
        nik_menu_row 1 'Przedmioty i ekwipunek'
        nik_menu_row 2 'Podróże i ratunek'
        nik_menu_row 3 'Zabawa i wiadomości od Taty'
        nik_menu_row 4 'Świat i pogoda'
        nik_menu_row 5 'Receptury i słowniki'
        nik_menu_row 6 'Zmień gracza'
        nik_menu_row 0 'Wyjście'
        nik_signature
        nik_menu_read 'Wybór' || return 0; category=$REPLY
        case $category in
            0) return 0 ;;
            6) nik_menu_player || true; continue ;;
            1) commands=(daj napraw plecak ender zdrowie) ;;
            2) commands=(prowadz gdzie tp powrot ratunek punkt) ;;
            3) commands=(napis tata odliczanie losuj nagroda fajerwerki zadanie) ;;
            4) commands=(pogoda dzien noc ochrona status) ;;
            5) commands=(przepis szukaj przedmioty) ;;
            *) nik_message 2 error 'Wybierz numer 0–6.\n'; continue ;;
        esac
        nik_section 'WYBIERZ CZYNNOŚĆ'
        for key in "${!commands[@]}"; do command=${commands[key]}; nik_help_row "$((key+1))  $command" "${NIK_DESCRIPTIONS[$command]}"; done
        nik_help_row 0 'Powrót'
        nik_menu_read 'Czynność' || return 0; choice=$REPLY
        [[ $choice =~ ^[0-9]{1,2}$ ]] || continue
        choice=$((10#$choice)); ((choice>=1 && choice<=${#commands[@]})) || continue
        command=${commands[choice-1]}; args=("$command" "$NIK_MENU_PLAYER")
        case $command in
            daj)
                nik_menu_field 'Przedmiot' || continue; item=$REPLY
                nik_menu_field 'Ilość [1]' 1 || continue; amount=$REPLY
                args+=("$item" "$amount") ;;
            prowadz)
                nik_menu_field 'Miejsce (lista: punkt lista)' || continue; item=$REPLY
                nik_menu_field 'Czas [60s]' 60s || continue; args+=("$item" "$REPLY") ;;
            tp) nik_menu_field 'Miejsce lub gracz' || continue; args+=("$REPLY") ;;
            punkt) nik_menu_field 'Nazwa nowego punktu' || continue; args+=("$REPLY") ;;
            napis|tata|zadanie) nik_menu_field 'Treść' || continue; args+=("$REPLY") ;;
            odliczanie)
                nik_menu_field 'Sekundy [10]' 10 || continue; item=$REPLY
                nik_menu_field 'Napis końcowy [Start!]' 'Start!' || continue; args+=("$item" "$REPLY") ;;
            nagroda)
                nik_section 'DOSTĘPNE NAGRODY'; nik_reward_names
                nik_menu_field 'Nazwa nagrody' || continue; args+=("$REPLY") ;;
            pogoda)
                nik_menu_field 'Pogoda: slonce, deszcz, burza' || continue; item=$REPLY
                nik_menu_field 'Czas [10m]' 10m || continue; args=(pogoda "$item" "$REPLY") ;;
            ochrona) args=(ochrona status) ;;
            przepis|szukaj) nik_menu_field 'Przedmiot lub fraza' || continue; args=("$command" "$REPLY") ;;
            dzien|noc|status|przedmioty) args=("$command") ;;
        esac
        nik_section 'TWOJA KOMENDA'
        nik_message 1 command '  nik'; printf ' %q' "${args[@]}"; printf '\n'
        nik_ui_text '1 Wykonaj • 2 Podgląd • 0 Anuluj' gold
        nik_menu_read 'Decyzja' || return 0; confirm=$REPLY
        options=()
        ((NIK_DRY_RUN==0)) || options+=(--podglad)
        case $confirm in 1) : ;; 2) options+=(--podglad) ;; *) continue ;; esac
        rc=0
        NIK_STATE=$NIK_STATE bash "$NIK_ROOT/nik.sh" --konfiguracja "$NIK_CONFIG" "${options[@]}" -- "${args[@]}" || rc=$?
        ((rc==0)) || nik_message 2 error 'Komenda zakończona błędem (%s). Możesz poprawić dane.\n' "$rc"
        nik_menu_read 'Enter — wróć do menu' || return 0
    done
}
