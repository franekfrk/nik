# shellcheck shell=bash
nik_docker() {
    local output rc=0
    command -v docker >/dev/null || nik_die 'Brak Dockera.'
    command -v timeout >/dev/null || nik_die 'Brak timeout (GNU coreutils).'
    output=$(timeout --foreground "${NIK_TIMEOUT}s" docker "$@" 2>&1) || rc=$?
    if ((rc)); then
        if ((rc == 124)); then nik_message 2 error 'NIK: przekroczono limit czasu Docker/RCON.\n'
        else nik_message 2 error 'NIK: Docker/RCON zakończony błędem %s.\n%s\n' "$rc" "$output"; fi
        return "$rc"
    fi
    printf '%s\n' "$output"
}
nik_check() {
    local state
    state=$(nik_docker inspect --format '{{.State.Running}}' "$NIK_CONTAINER") || return "$?"
    [[ $state == true ]] || { nik_message 2 error 'NIK: kontener nie działa.\n'; return 1; }
}
nik_response_failed() {
    local line
    while IFS= read -r line; do
        if [[ ${line,,} =~ $NIK_ERROR_PATTERN ]]; then return 0; fi
    done <<< "$1"
    return 1
}
nik_rcon() {
    local command=$1 output plain rc=0 noop=0 result=OK
    [[ $command != *$'\n'* && $command != *$'\r'* ]] || nik_die 'Niedozwolony znak w poleceniu.'
    if ((NIK_DRY_RUN)); then nik_message 1 gold '[podgląd] %s\n' "$command"; return 0; fi
    # Abort before mutation when audit logging is unavailable.
    nik_log START "$command" || { nik_message 2 error 'NIK: nie można zapisać logu.\n'; return 1; }
    if nik_check; then :; else
        rc=$?; nik_log ERROR "$command" || true; return "$rc"
    fi
    output=$(nik_docker exec "$NIK_CONTAINER" rcon-cli "$command") || rc=$?
    # Minecraft command failures may still arrive with Docker exit code zero.
    plain=$(printf '%s' "$output" | sed -E $'s/\033\\[[0-9;]*[[:alpha:]]//g')
    plain=${plain//$'\r'/}
    if [[ $command == 'effect clear '* ]] && [[ $plain == "Target doesn't have the requested effect" || $plain == 'Target has no effects to remove' ]]; then
        noop=1
    elif [[ $command =~ ^attribute\ [^\ ]+\ minecraft:(movement_speed|jump_strength)\ modifier\ remove\ nik:frozen$ && $plain == Attribute*' has no modifier nik:frozen' ]]; then
        noop=1
    fi
    if ((rc == 0 && !noop)); then
        if [[ -z ${plain//[[:space:]]/} ]] || nik_response_failed "$plain"; then rc=1; fi
    fi
    if ((rc)); then
        nik_log ERROR "$command" || true
        nik_message 2 error 'NIK: polecenie niepotwierdzone. Przerwano; wcześniejsze kroki mogły zostać wykonane.\n%s\n' "$output"
        return "$rc"
    fi
    ((noop == 0)) || result=NOOP
    nik_log "$result" "$command" || { nik_message 2 error 'NIK: wykonano komendę, ale zapis wyniku do logu nie powiódł się.\n'; return 1; }
    if ((noop)); then nik_message 1 muted 'Brak blokady/efektu do usunięcia.\n'; else nik_message 1 success '%s\n' "$output"; fi
}
