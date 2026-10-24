# shellcheck shell=bash
nik_cmd_scenario() {
    local action=${1:-lista} player
    local -a options=() values=()
    ((NIK_DRY_RUN == 0)) || options+=(--dry-run)
    ((NIK_CONFIRM == 0)) || options+=(--confirm)
    case $action in
        lista|dane) (($# <= 1)) || nik_die 'Użycie: scenariusz lista|dane' ;;
        zapisz) (($# >= 3)) || nik_die 'Użycie: scenariusz zapisz NAZWA "KROK"...'; values=("${@:2}") ;;
        pokaz|usun) nik_args 2 "$@"; values=("$2") ;;
        *) nik_args 2 "$@"; nik_player "$1"; player=${NIK_ALIASES[${1,,}]:-${1,,}}; values=("$2" "$player"); action=wykonaj ;;
    esac
    python3 "$NIK_ROOT/tools/scenarios.py" --root "$NIK_ROOT" --config "$NIK_CONFIG" "${options[@]}" "$action" "${values[@]}"
}
