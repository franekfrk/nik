# shellcheck shell=bash
nik_help() {
    local name=${1:-} cmd group
    local -a groups=('PRZEDMIOTY I EKWIPUNEK' 'PODRÓŻE I RATUNEK' 'GRACZE I EFEKTY' 'OD TATY DLA FRANKA' 'ŚWIAT I STWORZENIA' 'SŁOWNIKI I WYSZUKIWANIE' 'SERWER I POZOSTAŁE')
    nik_panel 'NIK v2 — polskie komendy Minecraft' 'TWÓJ ŚWIAT • TWOJE PRZYGODY • WERSJA 2.6'
    if [[ -n $name ]]; then
        [[ -v NIK_USAGE[$name] ]] || nik_die "Nieznana komenda: $name"
        nik_section 'JAK UŻYWAĆ'
        nik_ui_text "nik ${NIK_USAGE[$name]}" command
        nik_ui_text "${NIK_DESCRIPTIONS[$name]}"
    else
        nik_ui_text 'Wybierz komendę. Tab podpowiada nazwy, graczy i przedmioty.' muted
        for group in "${groups[@]}"; do
            nik_section "$group"
            while IFS= read -r cmd; do
                nik_help_group "$cmd"
                [[ $REPLY != "$group" ]] || nik_help_row "$cmd" "${NIK_DESCRIPTIONS[$cmd]}"
            done < <(printf '%s\n' "${!NIK_HANDLERS[@]}" | sort)
        done
    fi
    nik_section 'OPCJE'
    nik_help_row --podglad 'Pokaż plan bez wykonywania zmian.'
    nik_help_row --potwierdz 'Potwierdź operację wymagającą zgody.'
    nik_help_row --konfiguracja 'KATALOG — wybierz własną konfigurację.'
    nik_help_row --pomoc 'Pomoc ogólna lub dla wybranej komendy.'
    nik_help_row --wersja 'Pokaż wersję NIK.'
    nik_help_row --rozszerzenia 'KATALOG — wczytaj własne moduły.'
    nik_signature
}
