# shellcheck shell=bash
if ! declare -F nik_message >/dev/null; then
    # shellcheck disable=SC1091
    source "$(dirname -- "${BASH_SOURCE[0]}")/colors.sh"
fi
nik_die() { nik_message 2 error 'NIK: %s\n' "$*"; exit 2; }
nik_unexpected() { nik_message 2 error 'NIK: zakończono z błędem (status %s, linia %s).\n' "$1" "$2"; exit "$1"; }
nik_args() { (( $# == $1 + 1 )) || nik_die 'Nieprawidłowa liczba argumentów. Użyj nik <komenda> --pomoc.'; }
nik_uint() { [[ $1 =~ ^[0-9]{1,8}$ ]] || nik_die 'Wymagana liczba całkowita (maks. 8 cyfr).'; REPLY=$((10#$1)); (( REPLY >= $2 && REPLY <= $3 )) || nik_die "Liczba poza zakresem $2–$3."; }
nik_coord() { [[ $1 =~ ^-?[0-9]{1,8}([.][0-9]{1,6})?$ || $1 =~ ^[\~\^](-?[0-9]{1,8}([.][0-9]{1,6})?)?$ ]] || nik_die 'Nieprawidłowa współrzędna.'; }
nik_id() { [[ $1 =~ ^[a-z][a-z0-9_]*$ ]] || nik_die 'Nieprawidłowa nazwa (a-z, 0-9, _).'; }
nik_dimension() { [[ $1 =~ ^[a-z0-9_.-]+:[a-z0-9_./-]+$ ]] || nik_die 'Wymiar musi mieć format minecraft:overworld.'; }
# Runtime: 1 local/game failure, 2 invalid input, 75 busy lock. Transport
# status codes (including timeout 124 and forced termination 137) are preserved.
nik_lock() {
    local rc=0
    flock -w "$NIK_TIMEOUT" -E 75 -x "$1" || rc=$?
    if ((rc)); then nik_message 2 error 'NIK: nie uzyskano blokady (status %s).\n' "$rc"; fi
    return "$rc"
}
nik_log() (
    local result=$1 command=$2 dir timestamp
    umask 077
    [[ ! -L $NIK_LOG && ! -L ${NIK_LOG}.lock ]] || return 1
    dir=$(dirname -- "$NIK_LOG") || return "$?"
    mkdir -p -- "$dir" || return "$?"
    exec 9>> "${NIK_LOG}.lock" || return "$?"
    chmod 600 -- "${NIK_LOG}.lock" || return "$?"
    nik_lock 9 || return "$?"
    [[ ! -L $NIK_LOG && ! -L ${NIK_LOG}.lock ]] || return 1
    # Escape record separators so one operation always occupies one audit row.
    command=${command//$'\n'/\\n}; command=${command//$'\r'/\\r}; command=${command//$'\t'/\\t}
    timestamp=$(date -u +%FT%TZ) || return "$?"
    touch -- "$NIK_LOG" || return "$?"
    chmod 600 -- "$NIK_LOG" "${NIK_LOG}.lock" || return "$?"
    printf '%s\t%s\t%s\n' "$timestamp" "$result" "$command" >> "$NIK_LOG" || return "$?"
)
nik_normalize_name() {
    local text=${1,,}
    text=${text//ą/a}; text=${text//ć/c}; text=${text//ę/e}; text=${text//ł/l}; text=${text//ń/n}
    text=${text//ó/o}; text=${text//ś/s}; text=${text//ź/z}; text=${text//ż/z}
    text=${text//Ą/a}; text=${text//Ć/c}; text=${text//Ę/e}; text=${text//Ł/l}; text=${text//Ń/n}
    text=${text//Ó/o}; text=${text//Ś/s}; text=${text//Ź/z}; text=${text//Ż/z}
    text=${text// /_}; text=${text//-/_}
    while [[ $text == *__* ]]; do text=${text//__/_}; done
    REPLY=${text#_}; REPLY=${REPLY%_}
}

nik_suggest() {
    local query=$1 suggestion; shift
    command -v python3 >/dev/null || return 0
    while IFS= read -r suggestion; do
        nik_message 2 gold 'Czy chodziło o: %s?\n' "$suggestion"
    done < <(printf '%s\n' "$@" | python3 "$NIK_ROOT/tools/suggest.py" "$query")
}

nik_progress() {
    if [[ ${NIK_PROGRESS:-0} == 1 ]]; then printf 'NIK:POSTEP\t%s\n' "$1" >&2; fi
}
