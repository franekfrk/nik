# shellcheck shell=bash
nik_baner() {
    local entry=$1 output='' state='niedostępny' players='' log='' line tone=error
    # The probe stays plain even when the caller explicitly forces colors.
    if output=$(NIK_COLOR=never timeout 3 bash "$entry" status 2>/dev/null); then
        state='działa'; tone=success
    fi
    while IFS= read -r line; do
        line=${line#"${line%%[![:space:]]*}"}
        case $line in
            'Log: '*) log=${line#Log: } ;;
            *online:*) players=${line#*online:}; players=${players# } ;;
        esac
    done <<< "$output"
    nik_panel 'NACZELNY INSPEKTORAT KREEPEROWY' 'NIK 2.4 • PRZYGODA ZACZYNA SIĘ TUTAJ'
    nik_message 1 gold '  %-12s ' 'Minecraft:'
    nik_message 1 "$tone" '%s\n' "$state"
    if [[ -n $players ]]; then
        nik_message 1 gold '  %-12s ' 'Gracze:'
        nik_message 1 command '%s\n' "$players"
    fi
    if [[ -n $log ]]; then
        nik_message 1 gold '  %-12s ' 'Log:'
        nik_ui_text "$log" muted
    fi
    nik_message 1 text '\n  Wpisz: '
    nik_message 1 command 'nik\n'
    nik_signature
}
