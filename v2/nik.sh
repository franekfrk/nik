#!/usr/bin/env bash
# Strict mode is confined to the executable process, never the caller's shell.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    _nik_v2_entry=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/nik.sh
    nik() ( exec bash "$_nik_v2_entry" "$@"; )
    source "${_nik_v2_entry%/*}/lib/colors.sh"
    source "${_nik_v2_entry%/*}/lib/completion.sh"
    nik_skroty
    source "${_nik_v2_entry%/*}/lib/banner.sh"
    if [[ $- == *i* ]]; then nik_baner "$_nik_v2_entry"; fi
    return 0
fi
set -Eeuo pipefail
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then printf 'NIK wymaga Bash >= 4.4.\n' >&2; exit 2; fi
NIK_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/colors.sh
source "$NIK_ROOT/lib/colors.sh"
# shellcheck source=lib/helpers.sh
source "$NIK_ROOT/lib/helpers.sh"
trap 'nik_unexpected "$?" "$LINENO"' ERR
for module in config players items enchantments effects rcon display extras travel commands; do
    # shellcheck disable=SC1090
    source "$NIK_ROOT/lib/$module.sh"
done
nik_main "$@"
