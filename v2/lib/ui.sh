# shellcheck shell=bash
nik_ui_width() {
    local width=${NIK_WIDTH:-100}
    if [[ -t 1 && ! -v NIK_WIDTH ]]; then width=$(tput cols 2>/dev/null) || width=80; fi
    [[ $width =~ ^[0-9]{2,3}$ ]] || width=100
    width=$((10#$width)); ((width >= 40)) || width=40; ((width <= 110)) || width=110
    NIK_UI_WIDTH=$width
}
nik_ui_lines() {
    local text=$1 width=$2 word line='' part
    local -a words=()
    read -r -a words <<< "$text"
    for word in "${words[@]}"; do
        while ((${#word}>width)); do
            [[ -z $line ]] || { printf '%s\n' "$line"; line=''; }
            part=${word:0:width}; printf '%s\n' "$part"; word=${word:width}
        done
        if [[ -n $line ]] && ((${#line}+${#word}+1>width)); then printf '%s\n' "$line"; line=''; fi
        [[ -z $word ]] || line+="${line:+ }$word"
    done
    [[ -z $line ]] || printf '%s\n' "$line"
    return 0
}
nik_ui_text() {
    local text=$1 style=${2:-text} line
    nik_ui_width
    while IFS= read -r line; do nik_message 1 "$style" '  %s\n' "$line"; done < <(nik_ui_lines "$text" "$((NIK_UI_WIDTH-2))")
}
nik_panel() {
    local title=$1 subtitle=${2:-} rule line
    nik_ui_width
    printf -v rule '%*s' "$((NIK_UI_WIDTH-4))" ''; rule=${rule// /─}
    nik_message 1 frame '\n  ┌%s┐\n' "$rule"
    while IFS= read -r line; do
        nik_message 1 frame '  │ '; nik_message 1 title '%s%*s' "$line" "$((NIK_UI_WIDTH-6-${#line}))" ''; nik_message 1 frame ' │\n'
    done < <(nik_ui_lines "$title" "$((NIK_UI_WIDTH-6))")
    if [[ -n $subtitle ]]; then
        while IFS= read -r line; do
            nik_message 1 frame '  │ '; nik_message 1 muted '%s%*s' "$line" "$((NIK_UI_WIDTH-6-${#line}))" ''; nik_message 1 frame ' │\n'
        done < <(nik_ui_lines "$subtitle" "$((NIK_UI_WIDTH-6))")
    fi
    nik_message 1 frame '  └%s┘\n' "$rule"
}
nik_section() {
    local title=$1 rule
    nik_ui_width
    printf -v rule '%*s' "$((NIK_UI_WIDTH-2))" ''; rule=${rule// /─}
    printf '\n'; nik_ui_text "$title" gold
    nik_message 1 muted '  %s\n' "$rule"
}
nik_help_row() {
    local command=$1 description=$2 line first=1
    nik_ui_width
    while IFS= read -r line; do
        if ((first)); then nik_message 1 command '  %-17s   ' "$command"; first=0
        else printf '%22s' ''; fi
        nik_message 1 text '%s\n' "$line"
    done < <(nik_ui_lines "$description" "$((NIK_UI_WIDTH-22))")
}
nik_help_group() {
    case $1 in
        daj|encik|zaklnij|napraw|wyposaz|zestaw|plecak|ender) REPLY='PRZEDMIOTY I EKWIPUNEK' ;;
        tp|dom|zamek|dolacz|gdzie|powrot|punkt|miejsce|ratunek) REPLY='PODRÓŻE I RATUNEK' ;;
        efekt|usun|wyczysc|zdrowie|zamroz|odmroz|kreatywny|przetrwanie|obserwator|przygodowy) REPLY='GRACZE I EFEKTY' ;;
        tata|wiadomosc|napis|zadanie|fajerwerki) REPLY='OD TATY DLA FRANKA' ;;
        dzien|noc|pogoda|burza|przywolaj|ochrona) REPLY='ŚWIAT I STWORZENIA' ;;
        przedmioty|szukaj) REPLY='SŁOWNIKI I WYSZUKIWANIE' ;;
        *) REPLY='SERWER I POZOSTAŁE' ;;
    esac
}
