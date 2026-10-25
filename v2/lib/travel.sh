# shellcheck shell=bash
nik_location_python() { command -v python3 >/dev/null || nik_die 'Pozycja i powrót wymagają Python 3.'; }
nik_location_capture() {
    local player=$1 pos dimension rotation before_dimension
    nik_location_python
    nik_rcon "data get entity $player Dimension" >/dev/null || return "$?"; before_dimension=$NIK_RCON_RESPONSE
    nik_rcon "data get entity $player Pos" >/dev/null || return "$?"; pos=$NIK_RCON_RESPONSE
    nik_rcon "data get entity $player Dimension" >/dev/null || return "$?"; dimension=$NIK_RCON_RESPONSE
    [[ $before_dimension == "$dimension" ]] || { nik_message 2 error 'NIK: gracz zmienił wymiar podczas odczytu pozycji. Przerwano odczyt.\n'; return 1; }
    nik_rcon "data get entity $player Rotation" >/dev/null || return "$?"; rotation=$NIK_RCON_RESPONSE
    python3 "$NIK_ROOT/tools/location.py" capture "$player" "$NIK_CONTAINER" "$pos" "$dimension" "$rotation"
}
nik_cmd_where() {
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY record point x y z dimension yaw pitch
    if ((NIK_DRY_RUN)); then
        nik_rcon "data get entity $player Dimension"; nik_rcon "data get entity $player Pos"; nik_rcon "data get entity $player Dimension"; nik_rcon "data get entity $player Rotation"; return
    fi
    record=$(nik_location_capture "$player") || return "$?"
    # A private temporary file avoids evaluating or sourcing RCON output.
    point=$(umask 077; mktemp) || return "$?"
    printf '%s\n' "$record" > "$point"
    local fields rc=0
    fields=$(python3 "$NIK_ROOT/tools/location.py" read "$point" "$player" "$NIK_CONTAINER") || rc=$?
    rm -f -- "$point"
    ((rc == 0)) || return "$rc"
    IFS=$'\t' read -r x y z dimension yaw pitch <<< "$fields"
    nik_message 1 title '\nPOZYCJA GRACZA: %s\n' "$1"
    nik_message 1 command '  X: %s   Y: %s   Z: %s\n' "$x" "$y" "$z"
    nik_message 1 gold '  Wymiar: %s\n' "$dimension"
    nik_message 1 muted '  Kierunek: %s°   Nachylenie: %s°\n\n' "$yaw" "$pitch"
}
nik_travel_directory() {
    local directory=$NIK_STATE
    [[ ! -L $directory && ! -L $directory/returns ]] || nik_die 'Katalog powrotów nie może być dowiązaniem.'
    umask 077
    mkdir -p -- "$directory/returns" || return "$?"
    chmod 700 -- "$directory" "$directory/returns" || return "$?"
    REPLY=$directory/returns
}
nik_teleport() (
    local player=$1 command=$2 directory record pending inflight
    if ((NIK_DRY_RUN)); then
        nik_message 1 gold '[podgląd] zapamiętanie pozycji sprzed teleportacji\n'
        nik_rcon "$command"; return
    fi
    nik_location_python
    nik_travel_directory || return "$?"; directory=$REPLY
    record=$directory/$player.json
    [[ ! -L $record && ! -L $directory/$player.uncertain.json && ! -L $directory/$player.inflight.json && ! -L $directory/$player.lock ]] || nik_die 'Punkt powrotu lub blokada jest dowiązaniem.'
    exec 8> "$directory/$player.lock"
    nik_lock 8 || return "$?"
    inflight=$directory/$player.inflight.json
    [[ ! -e $inflight ]] || nik_die 'Poprzednia teleportacja nie ma potwierdzenia. Najpierw użyj powrot GRACZ.'
    # A named journal written before mutation survives process termination, including SIGKILL.
    # The anonymous temporary file is removed on errors before that point.
    pending=$(mktemp "$directory/.pending.XXXXXX") || return "$?"
    trap 'rm -f -- "$pending"' EXIT
    nik_location_capture "$player" > "$pending" || return "$?"
    mv -f -- "$pending" "$inflight" || return "$?"
    local rc=0
    nik_rcon "$command" || rc=$?
    if ((rc)); then
        if [[ ${NIK_RCON_UNCERTAIN:-0} == 1 ]]; then
            mv -f -- "$inflight" "$directory/$player.uncertain.json" || { nik_message 2 error 'NIK: zachowano awaryjny punkt powrotu w %s.\n' "$inflight"; return "$rc"; }
            if [[ -n ${NIK_RESULT_PATH:-} ]]; then
                printf '%s' "${NIK_RCON_ERROR_RESPONSE:-}" | python3 "$NIK_ROOT/tools/result_data.py" error teleport_uncertain 'Wynik teleportacji jest niepewny. Zapisano pozycję wyjściową; po odzyskaniu RCON użyj polecenia powrot.' || true
            fi
            nik_message 2 error 'NIK: wynik teleportacji jest niepewny. Zapisano pozycję wyjściową; po odzyskaniu RCON użyj powrot GRACZ.\n'
        else
            rm -f -- "$inflight" || return "$?"
        fi
        return "$rc"
    fi
    mv -f -- "$inflight" "$record" || { nik_message 2 error 'NIK: teleport wykonany; zachowano punkt odzyskiwania w %s.\n' "$inflight"; return 1; }
    rm -f -- "$directory/$player.uncertain.json"
)
nik_cmd_back() (
    nik_args 1 "$@"; nik_player "$1"; local player=$REPLY directory record fields x y z dimension yaw pitch
    nik_location_python
    directory=$NIK_STATE/returns; record=$directory/$player.json
    [[ ! -L $NIK_STATE && ! -L $directory && ! -L $record && ! -L $directory/$player.uncertain.json && ! -L $directory/$player.inflight.json && ! -L $directory/$player.lock ]] || nik_die 'Punkt powrotu jest dowiązaniem.'
    [[ -d $directory ]] || nik_die 'Brak punktu powrotu. Najpierw teleportuj gracza przez NIK.'
    if (( !NIK_DRY_RUN )); then
        umask 077
        exec 8> "$directory/$player.lock" || return "$?"; nik_lock 8 || return "$?"
    fi
    # Select recovery priority after obtaining the same lock as teleport.
    if [[ -f $directory/$player.uncertain.json ]]; then record=$directory/$player.uncertain.json; fi
    if [[ -f $directory/$player.inflight.json ]]; then record=$directory/$player.inflight.json; fi
    [[ -f $record ]] || nik_die 'Brak punktu powrotu. Najpierw teleportuj gracza przez NIK.'
    fields=$(python3 "$NIK_ROOT/tools/location.py" read "$record" "$player" "$NIK_CONTAINER") || return "$?"
    IFS=$'\t' read -r x y z dimension yaw pitch <<< "$fields"
    nik_rcon "execute in $dimension run tp $player $x $y $z $yaw $pitch" || return "$?"
    # Consume only after a confirmed return; errors retain the recovery point.
    if (( !NIK_DRY_RUN )); then rm -f -- "$record" || return "$?"; fi
)
nik_cmd_dad() {
    (($# >= 2)) || nik_die 'Użycie: tata GRACZ TREŚĆ...'
    nik_player "$1"; local player=$REPLY message; shift
    command -v python3 >/dev/null || nik_die 'Wiadomości wymagają Python 3.'
    message=$(python3 "$NIK_ROOT/tools/dad-message.py" chat "$@") || return "$?"
    nik_rcon "tellraw $player $message"
}

# All built-in dimensions share the same floor and body-space validation.
nik_tp_end() { nik_tp_surface "$1" end; }

# Only the single landing chunk is held, with a private recovery lease written
# before force loading. An interrupted cleanup is retried on the next teleport to that dimension.
nik_surface_forced() {
    local dimension=$1
    nik_rcon "execute in $dimension run forceload query 0 0" >/dev/null || return "$?"
    case $NIK_RCON_RESPONSE in
        "Chunk at [0, 0] in $dimension is not marked for force loading") REPLY=0 ;;
        "Chunk at [0, 0] in $dimension is marked for force loading") REPLY=1 ;;
        *) nik_message 2 error 'NIK: nie rozpoznano stanu chunka lądowania.\n'; return 1 ;;
    esac
}
nik_surface_release() {
    local lease=$1 destination=$2 dimension=$3
    [[ -f $lease ]] || return 0
    [[ $(cat -- "$lease") == "$destination:0,0" ]] || nik_die 'Nieprawidłowy zapis tymczasowego ładowania terenu.'
    nik_surface_forced "$dimension" || return "$?"
    if ((REPLY)); then
        nik_rcon "execute in $dimension run forceload remove 0 0" >/dev/null || return "$?"
        nik_surface_forced "$dimension" || return "$?"
        ((REPLY == 0)) || return 1
    fi
    rm -f -- "$lease"
}
# Probe the native surface selection with a harmless, effect-free cloud first.
# Its finite lifetime is a fallback if RCON is lost before cleanup. No terrain
# changes, unowned chunk tickets, player effects or speculative player retries.
nik_tp_surface() (
    local player=$1 destination=$2 identity uuid nbt tag attempt floor guard selected='' lease ready=0
    local dimension label maximum floors
    case $destination in
        end)
            dimension=minecraft:the_end; label=End; maximum=96
            floors='end_stone obsidian end_stone_bricks purpur_block purpur_pillar stone cobblestone' ;;
        nether)
            dimension=minecraft:the_nether; label=Nether; maximum=120
            floors='netherrack basalt blackstone soul_sand soul_soil nether_bricks red_nether_bricks obsidian crying_obsidian polished_basalt smooth_basalt crimson_nylium warped_nylium' ;;
        swiat)
            dimension=minecraft:overworld; label='Zwykły świat'; maximum=320
            floors='grass_block dirt stone sand gravel coarse_dirt podzol mycelium rooted_dirt mud red_sand cobblestone mossy_cobblestone andesite diorite granite deepslate cobbled_deepslate tuff calcite snow_block clay moss_block terracotta' ;;
        *) nik_die 'Nieznany cel bezpiecznej teleportacji.' ;;
    esac
    local lease_path=$NIK_STATE/$destination-landing.lease lock_path=$NIK_STATE/$destination-landing.lock
    if ((NIK_DRY_RUN)); then
        nik_message 1 gold '[podgląd] %s: sprawdzenie gracza, sonda lądowania w obrębie chunka 0,0, do Y=%s; do 4 prób.\n' "$label" "$maximum"
        nik_message 1 gold '[podgląd] Tylko bezpieczne podłoże i dwa bloki powietrza; bez wody, lawy, magmy i niebezpiecznych bloków. Sonda bez efektów wygasa i jest usuwana. Tymczasowe ładowanie jednego chunka jest sprzątane.\n'
        nik_message 1 gold '[podgląd] Zapamiętanie pozycji i jeden teleport po ponownej kontroli miejsca; przy błędzie przerwanie.\n'
        return
    fi
    nik_location_python
    nik_travel_directory >/dev/null || return "$?"
    local suffix
    for suffix in json uncertain.json inflight.json lock; do
        [[ ! -L $NIK_STATE/returns/$player.$suffix ]] || nik_die 'Punkt powrotu lub blokada jest dowiązaniem.'
    done
    [[ ! -e $NIK_STATE/returns/$player.inflight.json ]] || nik_die 'Poprzednia teleportacja nie ma potwierdzenia. Najpierw użyj powrot GRACZ.'
    [[ ! -L $lease_path && ! -L $lock_path ]] || nik_die 'Blokada lub zapis lądowania jest dowiązaniem.'
    exec 9> "$lock_path"
    nik_lock 9 || return "$?"
    # Finish a previous interrupted cleanup before acquiring another lease.
    nik_surface_release "$lease_path" "$destination" "$dimension" || return "$?"
    # Check the player before creating the probe; nik_teleport captures the
    # current origin again immediately before the final guarded movement.
    nik_rcon "data get entity $player Pos" >/dev/null || return "$?"
    identity=$(python3 - <<'NIK_UUID'
import uuid,struct
value=uuid.uuid4()
print(str(value),','.join(map(str,struct.unpack('>iiii',value.bytes))),value.hex,sep='\t')
NIK_UUID
    ) || return "$?"
    IFS=$'\t' read -r uuid nbt tag <<< "$identity"
    tag=nik_${destination}_$tag
    nik_surface_forced "$dimension" || return "$?"
    if ((REPLY == 0)); then lease=$lease_path; else lease=''; fi
    # Cleanup runs in a subshell, preserving the operation's result and errors.
    # The UUID and private tag restrict removal to this one owned probe.
    trap '( NIK_TIMEOUT=2; NIK_RESULT_PATH=""; NIK_PROGRESS=0; nik_rcon "execute as $uuid if entity @s[type=minecraft:area_effect_cloud,tag=$tag] run kill @s" >/dev/null 2>&1 || true; if [[ -n $lease ]]; then nik_surface_release "$lease" "$destination" "$dimension" >/dev/null 2>&1 || nik_message 2 error "NIK: sprzątanie chunka odłożone do następnego tp %s po odzyskaniu RCON.\n" "$destination"; fi )' EXIT
    if [[ -n $lease ]]; then
        (umask 077; printf '%s:0,0\n' "$destination" > "$lease") || return "$?"
        nik_rcon "execute in $dimension run forceload add 0 0" >/dev/null || return "$?"
    fi
    for attempt in {1..15}; do
        nik_rcon "execute in $dimension if loaded 0 64 0" surface_probe >/dev/null || return "$?"
        if ((NIK_RCON_MATCHED)); then ready=1; break; fi
        sleep 0.2
    done
    ((ready)) || { nik_message 2 error 'NIK: teren docelowy nie załadował się na czas. Gracz nie został przeniesiony.\n'; return 1; }
    nik_message 1 command 'NIK: szukam bezpiecznego miejsca — %s.\n' "$label"
    nik_rcon "execute in $dimension run summon minecraft:area_effect_cloud 8 100 8 {UUID:[I;$nbt],Tags:[\"$tag\"],Duration:1200,WaitTime:0,Radius:0.5f,custom_particle:{type:\"minecraft:entity_effect\",color:0},potion_contents:{}}" >/dev/null || return "$?"
    for attempt in 1 2 3 4; do
        nik_rcon "execute in $dimension run spreadplayers 8 8 0 6 under $maximum false $uuid" >/dev/null || return "$?"
        local -a safe_floors=()
        read -r -a safe_floors <<< "$floors"
        for floor in "${safe_floors[@]}"; do
            guard="execute as $uuid at @s if dimension $dimension if entity @s[type=minecraft:area_effect_cloud,tag=$tag] if block ~ ~-1 ~ minecraft:$floor if block ~ ~ ~ minecraft:air if block ~ ~1 ~ minecraft:air"
            nik_rcon "$guard run data get entity @s Pos" surface_probe >/dev/null || return "$?"
            if ((NIK_RCON_MATCHED)); then selected=$guard; break; fi
        done
        [[ -z $selected ]] || break
    done
    [[ -n $selected ]] || { nik_message 2 error 'NIK: nie znaleziono bezpiecznego podłoża w wybranym wymiarze. Gracz nie został przeniesiony.\n'; return 1; }
    # Recheck the floor and both air blocks in the same server command as tp.
    nik_teleport "$player" "$selected run tp $player ~ ~ ~"
)

nik_tp_nether() { nik_tp_surface "$1" nether; }
nik_tp_world() { nik_tp_surface "$1" swiat; }
