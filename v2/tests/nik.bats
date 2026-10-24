#!/usr/bin/env bats
setup() {
    ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    WORK=$(mktemp -d)
    cp -R "$ROOT/config.example" "$WORK/config"
    export NIK_CONFIG="$WORK/config"
    printf 'LOG=%s/log/nik.log\n' "$WORK" >> "$NIK_CONFIG/config.env"
    export MOCK_CALLS="$WORK/calls" MOCK_MODE=ok MOCK_STATE="$WORK/state"
    mkdir "$WORK/bin"
    cat > "$WORK/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_CALLS"
if [[ $MOCK_MODE == transport ]]; then printf 'connection refused\n'; exit 7; fi
if [[ $MOCK_MODE == timeout ]]; then sleep 3; exit 0; fi
if [[ $1 == inspect ]]; then printf '%s\n' "${MOCK_RUNNING:-true}"; exit 0; fi
if [[ $MOCK_MODE == response ]]; then printf '%s\n' "$MOCK_RESPONSE"; exit 0; fi
if [[ $MOCK_MODE == stateful ]]; then
    command=${*: -1}
    read -r -a parts <<< "$command"
    if [[ $command == 'effect clear '* ]]; then printf "Target doesn't have the requested effect\n"; exit 0; fi
    if [[ $command == attribute* ]]; then
        attribute=${parts[2]}
        touch "$MOCK_STATE"
        if [[ ${parts[4]} == remove ]]; then
            if grep -qxF "$attribute" "$MOCK_STATE"; then
                grep -vxF "$attribute" "$MOCK_STATE" > "$MOCK_STATE.tmp" || true
                mv "$MOCK_STATE.tmp" "$MOCK_STATE"
                printf 'Removed modifier nik:frozen from attribute Speed for entity PlayerOne\n'
            else printf 'Attribute Speed for entity PlayerOne has no modifier nik:frozen\n'; fi
        else
            if grep -qxF "$attribute" "$MOCK_STATE"; then printf 'Modifier nik:frozen is already present on attribute Speed for entity PlayerOne\n'
            else printf '%s\n' "$attribute" >> "$MOCK_STATE"; printf 'Added modifier nik:frozen to attribute Speed for entity PlayerOne\n'; fi
        fi
        exit 0
    fi
fi
case $MOCK_MODE in
  semantic) printf 'Unknown or incomplete command\n' ;;
  empty) : ;;
  *) printf 'Command completed successfully\n' ;;
esac
MOCK
    chmod +x "$WORK/bin/docker"
    export PATH="$WORK/bin:$PATH"
}
teardown() { rm -rf "$WORK"; }
nik() { bash "$ROOT/nik.sh" "$@"; }
@test 'help without configuration or Docker' { run nik --config /missing help; [ "$status" -eq 0 ]; [[ $output == *'encik'* ]]; }
@test 'command help without configuration' { run nik --config /missing encik --help; [ "$status" -eq 0 ]; }
@test 'empty invocation shows help' { run nik; [ "$status" -eq 0 ]; }
@test 'version' { run nik --version; [ "$output" = 'NIK 2.1.0' ]; }
@test 'unknown command rejected' { run nik nonexistent; [ "$status" -eq 2 ]; }
@test 'source preserves caller shell flags' { run bash -c 'before=$-; source "$1"; [[ $before == "$-" ]]; nik --version' _ "$ROOT/nik.sh"; [ "$status" -eq 0 ]; }
@test 'player alias resolves, Polish item resolves, no Docker in dry run' { run nik --dry-run daj g1 diamentowy_kilof; [ "$status" -eq 0 ]; [[ $output == *'give PlayerOne minecraft:diamond_pickaxe 1'* ]]; [ ! -e "$MOCK_CALLS" ]; }
@test 'English namespaced item resolves' { run nik --dry-run daj gracz1 minecraft:diamond 64; [ "$status" -eq 0 ]; }
@test 'unknown player rejected' { run nik --dry-run daj nobody diamond; [ "$status" -eq 2 ]; }
@test 'unknown item rejected' { run nik --dry-run daj g1 nope; [ "$status" -eq 2 ]; }
@test 'zero count rejected' { run nik --dry-run daj g1 diamond 0; [ "$status" -eq 2 ]; }
@test 'oversized integer rejected' { run nik --dry-run daj g1 diamond 999999999999999999999999; [ "$status" -eq 2 ]; }
@test 'decimal normalization accepts leading zeros' { run nik --dry-run daj g1 diamond 008; [ "$status" -eq 0 ]; [[ $output == *' 8'* ]]; }
@test 'enchantments generate give not replace or enchant' { run nik --dry-run encik g1 diamond_sword sharpness:05 mending; [ "$status" -eq 0 ]; [[ $output == *'"minecraft:sharpness":5'* ]]; [[ $output != *'item replace'* ]]; }
@test 'zero enchant level rejected' { run nik --dry-run encik g1 diamond_sword sharpness:0; [ "$status" -eq 2 ]; }
@test '08 level properly rejected without arithmetic diagnostic' { run nik --dry-run encik g1 diamond_sword sharpness:08; [ "$status" -eq 2 ]; [[ $output != *'base'* ]]; }
@test 'enchantment incompatibility rejected' { run nik --dry-run encik g1 diamond_sword sharpness smite; [ "$status" -eq 2 ]; }
@test 'wrong item type rejected' { run nik --dry-run encik g1 shield sharpness; [ "$status" -eq 2 ]; }
@test 'duplicate enchantment rejected' { run nik --dry-run encik g1 shield unbreaking unbreaking; [ "$status" -eq 2 ]; }
@test 'riptide and loyalty conflict' { run nik --dry-run encik g1 trident riptide loyalty; [ "$status" -eq 2 ]; }
@test 'empty effect arguments handled cleanly' { run nik --dry-run efekt g1; [ "$status" -eq 2 ]; [[ $output != *'subscript'* ]]; }
@test 'effect resolves and time validated' { run nik --dry-run efekt g1 sila 60; [ "$status" -eq 0 ]; [[ $output == *'minecraft:strength 60'* ]]; run nik --dry-run efekt g1 sila garbage; [ "$status" -eq 2 ]; }
@test 'remove missing effect handled cleanly' { run nik --dry-run usun g1; [ "$status" -eq 2 ]; [[ $output != *'subscript'* ]]; }
@test 'thaw only removes two specific effects' { run nik --dry-run odmroz g1; [ "$status" -eq 0 ]; [[ $output == *'minecraft:slowness'* && $output == *'minecraft:jump_boost'* ]]; [[ $output != *$'PlayerOne\n'* ]]; }
@test 'invalid teleport coordinates rejected' { run nik --dry-run tp g1 '0 facing entity @a' 64 0; [ "$status" -eq 2 ]; }
@test 'relative teleport evaluates at player' { run nik --dry-run tp g1 '~1' '~' '~'; [ "$status" -eq 0 ]; [[ $output == *'execute at PlayerOne run tp'* ]]; }
@test 'mixed local coordinates rejected' { run nik --dry-run tp g1 '^' '~' 0; [ "$status" -eq 2 ]; }
@test 'place has explicit dimension' { printf 'baza\t1\t64\t2\tminecraft:the_nether\n' >> "$NIK_CONFIG/places.tsv"; run nik --dry-run tp g1 baza; [ "$status" -eq 0 ]; [[ $output == *'execute in minecraft:the_nether'* ]]; }
@test 'place save dry run does not write' { run nik --dry-run miejsce dodaj baza 1 64 2 minecraft:overworld; [ "$status" -eq 0 ]; [ "$(wc -l < "$NIK_CONFIG/places.tsv")" -eq 1 ]; }
@test 'place add persists and resolves' { run nik miejsce dodaj baza 1 64 2 minecraft:overworld; [ "$status" -eq 0 ]; run nik --dry-run tp g1 baza; [ "$status" -eq 0 ]; }
@test 'confirmation needed for destructive operations' { run nik wybuch g1; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]; }
@test 'confirmed operation executes via mock' { run nik --confirm wybuch g1; [ "$status" -eq 0 ]; grep -q 'summon' "$MOCK_CALLS"; }
@test 'Docker error preserves status' { export MOCK_MODE=transport; run nik zapisz; [ "$status" -eq 7 ]; }
@test 'semantic RCON error is failure' { export MOCK_MODE=semantic; run nik zapisz; [ "$status" -ne 0 ]; }
@test 'empty response is not confirmed success' { export MOCK_MODE=empty; run nik zapisz; [ "$status" -ne 0 ]; }
@test 'stopped container rejected' { export MOCK_RUNNING=false; run nik zapisz; [ "$status" -ne 0 ]; ! grep -q 'exec ' "$MOCK_CALLS"; }
@test 'timeout enforced' { printf 'TIMEOUT=1\n' >> "$NIK_CONFIG/config.env"; export MOCK_MODE=timeout; run nik zapisz; [ "$status" -eq 124 ]; }
@test 'multi-step action stops on first failure' { export MOCK_MODE=semantic; run nik zdrowie g1; [ "$status" -ne 0 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]; }
@test 'unavailable audit log prevents mutation' { printf 'LOG=/dev/null/cannot/write\n' >> "$NIK_CONFIG/config.env"; run nik zapisz; [ "$status" -ne 0 ]; [ ! -e "$MOCK_CALLS" ]; }
@test 'aliases collision rejected' { printf 'g1\tx\tOther\n' >> "$NIK_CONFIG/players.tsv"; run nik --dry-run status; [ "$status" -eq 2 ]; }
@test 'duplicate nick rejected' { printf 'other\tx\tplayerone\n' >> "$NIK_CONFIG/players.tsv"; run nik --dry-run status; [ "$status" -eq 2 ]; }
@test 'missing config rejected' { run nik --config /missing --dry-run status; [ "$status" -eq 2 ]; }
@test 'unknown config key rejected' { printf 'PASSWORD=example\n' >> "$NIK_CONFIG/config.env"; run nik --dry-run status; [ "$status" -eq 2 ]; }
@test 'configuration is never evaluated as shell code' { printf 'CONTAINER=$(touch /tmp/nik-should-not-exist)\n' >> "$NIK_CONFIG/config.env"; run nik --dry-run status; [ "$status" -eq 2 ]; [ ! -f /tmp/nik-should-not-exist ]; }
@test 'all built-in sets validate before Docker' { for preset in walka kopanie budowniczy; do run nik --dry-run wyposaz g1 "$preset"; [ "$status" -eq 0 ]; done; [ ! -e "$MOCK_CALLS" ]; }
@test 'bad last set row prevents all writes' { printf 'inventory.2\tshield\tsharpness\n' >> "$NIK_CONFIG/sets/kopanie.tsv"; run nik --confirm wyposaz g1 kopanie; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]; }
@test 'equipment does not use main hand as scratch space' { run nik --dry-run wyposaz g1 walka; [ "$status" -eq 0 ]; [[ $output != *'weapon.mainhand'* ]]; }
@test 'legacy component format selectable' { printf 'COMPONENTS=legacy\n' >> "$NIK_CONFIG/config.env"; run nik --dry-run encik g1 shield mending; [ "$status" -eq 0 ]; [[ $output == *'levels:'* ]]; }
@test 'registry extension explicit and usable' { mkdir "$WORK/ext"; cp "$ROOT/extensions/example.sh.example" "$WORK/ext/hello.sh"; run nik --extensions "$WORK/ext" hello; [ "$status" -eq 0 ]; [[ $output == *'Witaj'* ]]; }
@test 'newlines rejected in kick reason' { run nik --dry-run kick g1 $'a\nstop'; [ "$status" -eq 2 ]; }
@test 'status dry run needs no Docker' { run nik --dry-run status; [ "$status" -eq 0 ]; [ ! -e "$MOCK_CALLS" ]; }
@test 'logs include START and result with private permissions' { run nik zapisz; [ "$status" -eq 0 ]; grep -q START "$WORK/log/nik.log"; grep -q OK "$WORK/log/nik.log"; [ "$(stat -c %a "$WORK/log/nik.log")" = 600 ]; }
@test 'help lists every registered command' { run nik commands; [ "$status" -eq 0 ]; while IFS= read -r cmd; do run nik "$cmd" --help; [ "$status" -eq 0 ]; done <<< "$output"; }

@test 'completion suggests aliases without Docker' { run nik __complete daj 1 g; [ "$status" -eq 0 ]; [[ $output == *'g1'* ]]; [ ! -e "$MOCK_CALLS" ]; }
@test 'completion searches item substring' { run nik __complete daj 2 kilof; [ "$status" -eq 0 ]; [[ $output == *'diamentowy_kilof'* ]]; }
@test 'enchantment list available without Docker' { run nik encik co; [ "$status" -eq 0 ]; [[ $output == *'sharpness'* ]]; [ ! -e "$MOCK_CALLS" ]; }
@test 'every item ID round-trips through resolver' { run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; source "$1/lib/helpers.sh"; source "$1/lib/items.sh"; for item in "${!NIK_ITEMS[@]}"; do expected=${NIK_ITEMS[$item]}; nik_item "$item"; [[ $REPLY == "$expected" ]]; nik_item "$expected"; [[ $REPLY == "$expected" ]]; done' _ "$ROOT"; [ "$status" -eq 0 ]; }
@test 'all effects resolve in PL and EN' { run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; source "$1/lib/helpers.sh"; source "$1/lib/effects.sh"; for effect in "${!NIK_EFFECTS[@]}"; do expected=${NIK_EFFECTS[$effect]}; nik_effect "$effect"; [[ $REPLY == "$expected" ]]; nik_effect "$expected"; [[ $REPLY == "$expected" ]]; done' _ "$ROOT"; [ "$status" -eq 0 ]; }
@test 'log rotation removes old entries and keeps recent entries' { mkdir "$WORK/log"; printf '2000-01-01T00:00:00Z\tOK\told\n2999-01-01T00:00:00Z\tOK\tfuture\n' > "$WORK/log/nik.log"; run nik --confirm log_rotacja; [ "$status" -eq 0 ]; ! grep -q old "$WORK/log/nik.log"; grep -q future "$WORK/log/nik.log"; }
@test 'migration parses fixture without executing it' {
  cat > "$WORK/old.sh" <<'OLD'
MC_CONTAINER="minecraft"
MC_LOG="${MC_LOG:-$HOME/logi/nik.log}"
declare -a MC_GRACZE=(sample)
declare -A MC_GRACZE_SKROTY=( [sample]="s" )
gracz_nick() {
case "$1" in
sample|s)
echo "SampleNick"
;;
esac
}
MC_DOM_X=1
MC_DOM_Y=64
MC_DOM_Z=2
zamek() {
rcon "tp $nick 3 70 4"
}
touch /tmp/nik-migration-must-not-run
OLD
  run python3 "$ROOT/tools/migrate-v1.py" "$WORK/old.sh" "$WORK/imported"
  [ "$status" -eq 0 ]; [ ! -e /tmp/nik-migration-must-not-run ]; [ "$(stat -c %a "$WORK/imported/players.tsv")" = 600 ]
  run nik --config "$WORK/imported" --dry-run daj s diamond
  [ "$status" -eq 0 ]; [[ $output == *SampleNick* ]]
}
@test 'migration refuses to overwrite' { mkdir "$WORK/existing"; run python3 "$ROOT/tools/migrate-v1.py" /missing "$WORK/existing"; [ "$status" -ne 0 ]; }

@test 'v1 aliases work after source, including d to daj chain' {
  run bash -ic 'source "$1"
alias d=daj
d g1 diament --dry-run' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'give PlayerOne minecraft:diamond 1'* ]]
}
@test 'interactive source restores v1 banner' {
  run bash -ic 'source "$1"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'NACZELNY INSPEKTORAT KREEPEROWY'* ]]; [[ $output == *'Minecraft:'* ]]
}

@test 'item table has headings aligned spaces and no raw tabs or ANSI in pipes' {
  run nik przedmioty
  [ "$status" -eq 0 ]; [[ $output == *'PRZEDMIOTY'* && $output == *'ID MINECRAFT'* ]]
  [[ $output != *$'\t'* && $output != *$'\033'* ]]
}
@test 'effect list formatted with aligned columns' {
  run nik efekt co
  [ "$status" -eq 0 ]; [[ $output == *'EFEKTY'* && $output == *'fire_resistance'* ]]
  [[ $output != *$'\t'* ]]
}
@test 'enchantment table includes max levels and descriptions' {
  run nik encik co
  [ "$status" -eq 0 ]; [[ $output == *'MAX'* && $output == *'sharpness'* && $output == *'miecz'* ]]
}
@test 'color can be explicitly enabled and disabled' {
  export NIK_COLOR=always
  run nik efekt co
  [ "$status" -eq 0 ]; [[ $output == *$'\033[36m'* ]]
  export NIK_COLOR=never
  run nik efekt co
  [ "$status" -eq 0 ]; [[ $output != *$'\033'* ]]
}
@test 'empty search prints informative message' {
  run nik szukaj nieistniejacy_przedmiot
  [ "$status" -eq 0 ]; [[ $output == *'Brak wyników'* ]]
}
@test 'search formatted table includes matching rows only' {
  run nik szukaj diament
  [ "$status" -eq 0 ]; [[ $output == *'diamond_sword'* && $output != *'acacia_fence_gate'* ]]
}
@test 'narrow item table stays within specified width' {
  export NIK_WIDTH=60
  run nik przedmioty
  [ "$status" -eq 0 ]
  while IFS= read -r line; do [ "${#line}" -le 60 ]; done <<< "$output"
}
@test 'completion registered for daj d and effects after source' {
  run bash -c 'source "$1"; complete -p daj d efekt encik' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'_nik_v2_complete daj'* && $output == *'_nik_v2_complete d'* ]]
}
@test 'daj player jajo_ Tab returns every egg' {
  run bash -c 'source "$1"; COMP_WORDS=(daj gracz1 jajo_); COMP_CWORD=2; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* && $output == *'jajo_zombie'* ]]
  expected=$(awk -F '\t' '$1 ~ /^jajo_/ {n++} END {print n}' "$ROOT/data/items.tsv")
  [ "${#lines[@]}" -ge "$expected" ]
  # Aliases may also find natural eggs (e.g. zolwie_jajko). Every canonical
  # jajo_ name must still be present exactly once.
  while IFS= read -r name; do [[ $'\n'$output$'\n' == *$'\n'"$name"$'\n'* ]]; done < <(awk -F '\t' '$1 ~ /^jajo_/ {print $1}' "$ROOT/data/items.tsv")
  [ "$(printf '%s\n' "$output" | sort -u | wc -l)" -eq "${#lines[@]}" ]
}
@test 'd supports substring completion przyzy' {
  run bash -c 'source "$1"; COMP_WORDS=(d gracz1 przyzy); COMP_CWORD=2; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* && $output == *'przyzywacz_potworow'* ]]
}
@test 'nik daj completion remains working' {
  run bash -c 'source "$1"; COMP_WORDS=(nik daj gracz1 jajo_); COMP_CWORD=3; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* ]]
}
@test 'effect and enchantment completion works for aliases' {
  run bash -c 'source "$1"; COMP_WORDS=(efekt gracz1 odpor); COMP_CWORD=2; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'odpornosc'* ]]
  run bash -c 'source "$1"; COMP_WORDS=(encik gracz1 diamond_sword sharp); COMP_CWORD=3; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'sharpness'* ]]
}
@test 'search command completes item on first argument' {
  run bash -c 'source "$1"; COMP_WORDS=(szukaj kilof); COMP_CWORD=1; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'diamentowy_kilof'* ]]
}

@test 'rainbow dedication is at bottom of help and has six colors' {
  export NIK_COLOR=always
  run nik help
  [ "$status" -eq 0 ]
  [[ $output == *$'\033[1;91mD'* && $output == *$'\033[1;93ml'* && $output == *$'\033[1;92ma'* ]]
  [[ $output == *$'\033[1;91m♥'* && $output == *$'\033[1;95m'* ]]
}
@test 'plain help keeps dedication without escape codes' {
  export NIK_COLOR=never
  run nik help
  [ "$status" -eq 0 ]; [[ $output == *'Dla Franka ♥ Tata'* && $output != *$'\033'* ]]
}
@test 'help command names title and options are colored' {
  export NIK_COLOR=always
  run nik help
  [ "$status" -eq 0 ]; [[ $output == *$'\033[1;92m'* && $output == *$'\033[36m'* && $output == *$'\033[1;33m'* ]]
}
@test 'errors and dry-run are colored while retaining exit statuses' {
  export NIK_COLOR=always
  run nik daj g1 invalid_item
  [ "$status" -eq 2 ]; [[ $output == *$'\033[1;31m'* ]]
  run nik --dry-run daj g1 diamond
  [ "$status" -eq 0 ]; [[ $output == *$'\033[1;33m'* ]]
}
@test 'banner dedication and status survive forced color with no old notice' {
  export NIK_COLOR=always
  run bash -ic 'source "$1"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'Minecraft:'* && $output == *'działa'* && $output == *'Log:'* ]]
  [[ $output != *'skróty v1 aktywne'* && $output == *$'\033[1;91m♥'* ]]
}
@test 'players list restores alias information with colors' {
  export NIK_COLOR=always
  run nik gracz_lista
  [ "$status" -eq 0 ]; [[ $output == *'skrót: g1'* && $output == *$'\033[36m'* ]]
}
@test 'completion output remains plain even with forced colors' {
  export NIK_COLOR=always
  run nik __complete daj 2 jajo_
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* && $output != *$'\033'* ]]
}
@test 'NO_COLOR disables automatic styling' {
  export NO_COLOR=1
  run bash -ic 'source "$1"; nik help' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'Dla Franka ♥ Tata'* && $output != *$'\033'* ]]
}

@test 'short egg names resolve and old spellings still work' {
  run nik --dry-run daj g1 jajo_creepera
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:creeper_spawn_egg'* ]]
  run nik --dry-run daj g1 jajo_przyzywajace_creepera
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:creeper_spawn_egg'* ]]
}
@test 'all renamed v1 item names resolve to identical IDs' {
  run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; source "$1/lib/helpers.sh"; source "$1/lib/items.sh"; while IFS=$'"'"'\t'"'"' read -r old new id reason; do nik_item "$old"; [[ $REPLY == "$id" ]]; nik_item "$new"; [[ $REPLY == "$id" ]]; done < "$1/data/item-renames.tsv"' _ "$ROOT"
  [ "$status" -eq 0 ]
}
@test 'every alias resolves and full catalogue passes audit' {
  run python3 "$ROOT/tools/audit-items.py"
  [ "$status" -eq 0 ]
  run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; source "$1/lib/helpers.sh"; source "$1/lib/items.sh"; for name in "${!NIK_ITEM_ALIASES[@]}"; do expected=${NIK_ITEM_ALIASES[$name]}; nik_item "$name"; [[ $REPLY == "$expected" ]]; done' _ "$ROOT"
  [ "$status" -eq 0 ]
}
@test 'natural sniffer egg is never confused with spawn egg' {
  run nik --dry-run daj g1 jajo_niuchacza
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:sniffer_egg '* && $output != *'spawn_egg'* ]]
  run nik --dry-run daj g1 jajo_niuchacza_spawn
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:sniffer_spawn_egg'* ]]
}
@test 'egg names use correct Polish genitive forms' {
  run nik --dry-run daj g1 jajo_krowy
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:cow_spawn_egg'* ]]
  run nik --dry-run daj g1 jajo_przyzywajace_krowe
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:cow_spawn_egg'* ]]
}
@test 'Polish diacritics and quoted spaces are accepted' {
  run nik --dry-run daj g1 'ŻELAZNY MIECZ'
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:iron_sword'* ]]
  run nik --dry-run daj g1 'jajo żółwia'
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:turtle_spawn_egg'* ]]
}
@test 'compact disc and smithing template names resolve' {
  run nik --dry-run daj g1 plyta_pigstep
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:music_disc_pigstep'* ]]
  run nik --dry-run daj g1 szablon_silence
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:silence_armor_trim_smithing_template'* ]]
}
@test 'neteryt spelling alias and synonyms work' {
  run nik --dry-run daj g1 neterytowy_kilof
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:netherite_pickaxe'* ]]
  run nik --dry-run daj g1 crafting
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:crafting_table'* ]]
}
@test 'search by historical name displays current short name' {
  run nik szukaj jajo_przyzywajace_krowe
  [ "$status" -eq 0 ]; [[ $output == *'jajo_krowy'* && $output == *'cow_spawn_egg'* && $output != *'jajo_przyzywajace_krowe'* ]]
}
@test 'completion by old przyzy fragment returns short egg names' {
  run nik __complete daj 2 przyzy
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* && $output != *'jajo_przyzywajace_'* ]]
}
@test 'English ID completion suggests canonical Polish name' {
  run nik __complete daj 2 cow_spawn
  [ "$status" -eq 0 ]; [ "$output" = 'jajo_krowy' ]
}
@test 'ambiguous generic tools remain rejected' {
  run nik --dry-run daj g1 kilof
  [ "$status" -eq 2 ]
}

@test 'freeze uses zeroing modifiers and never gives Jump Boost' {
  run nik --dry-run zamroz g1
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:jump_strength modifier add nik:frozen -1 add_multiplied_total'* ]]
  [[ $output == *'minecraft:movement_speed modifier add nik:frozen -1 add_multiplied_total'* ]]
  [[ $output != *'effect give '* && $output != *'base set'* ]]
}
@test 'freeze and thaw are repeatable with stateful server responses' {
  export MOCK_MODE=stateful
  run nik zamroz g1
  [ "$status" -eq 0 ]; [ "$(wc -l < "$MOCK_STATE")" -eq 2 ]
  run nik zamroz g1
  [ "$status" -eq 0 ]; [ "$(wc -l < "$MOCK_STATE")" -eq 2 ]
  run nik odmroz g1
  [ "$status" -eq 0 ]; [ ! -s "$MOCK_STATE" ]
  run nik odmroz g1
  [ "$status" -eq 0 ]; [ ! -s "$MOCK_STATE" ]
}
@test 'thaw absent effects do not prevent removing other freeze state' {
  export MOCK_MODE=stateful
  run nik odmroz g1
  [ "$status" -eq 0 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 4 ]
  grep -q NOOP "$WORK/log/nik.log"
}
@test 'missing attribute is an error and stops freeze' {
  export MOCK_MODE=response MOCK_RESPONSE='Entity PlayerOne has no attribute minecraft:jump_strength'
  run nik zamroz g1
  [ "$status" -ne 0 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]
}
@test 'health uses safe integer-shift and saturation levels' {
  run nik --dry-run zdrowie g1
  [ "$status" -eq 0 ]; [[ $output == *'instant_health 1 10 true'* && $output == *'saturation 1 20 true'* ]]
  [[ $output != *'255'* ]]
}
@test 'human effect level I maps to amplifier zero and II to one' {
  run nik --dry-run efekt g1 sila 60
  [ "$status" -eq 0 ]; [[ $output == *'strength 60 0 true'* ]]
  run nik --dry-run efekt g1 sila 60 2
  [ "$status" -eq 0 ]; [[ $output == *'strength 60 1 true'* ]]
}
@test 'instant effects reject levels that overflow vanilla calculations' {
  run nik --dry-run efekt g1 instant_health 1 256
  [ "$status" -eq 2 ]
}
@test 'vanilla 26.3 smite on mace and efficiency on shears are supported' {
  run nik --dry-run encik g1 mace smite:5
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:smite'* ]]
  run nik --dry-run encik g1 shears efficiency:5
  [ "$status" -eq 0 ]
}
@test 'binding curse on carved pumpkin is supported by vanilla tags' {
  run nik --dry-run encik g1 carved_pumpkin binding_curse
  [ "$status" -eq 0 ]
}
@test 'lunge and new spear work' {
  run nik --dry-run encik g1 diamentowa_wlocznia lunge
  [ "$status" -eq 0 ]; [[ $output == *'diamond_spear'* && $output == *'minecraft:lunge'* ]]
}
@test 'enchanted book stores enchantments rather than applying item enchantments' {
  run nik --dry-run encik g1 enchanted_book sharpness:5
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:stored_enchantments='* ]]
}
@test 'all supported enchantment-item pairs from vanilla validate' {
  run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; NIK_COMPONENTS=modern; source "$1/lib/helpers.sh"; source "$1/lib/enchantments.sh"; while IFS=$'"'"'\t'"'"' read -r enchant item; do nik_enchanted "$item" "$enchant"; [[ $REPLY == "minecraft:$item"* ]]; done < "$1/data/enchantment-items.tsv"' _ "$ROOT"
  [ "$status" -eq 0 ]
}
@test 'all incompatible enchantment pairs from vanilla are rejected' {
  run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; NIK_COMPONENTS=modern; source "$1/lib/helpers.sh"; source "$1/lib/enchantments.sh"; while IFS=$'"'"'\t'"'"' read -r a b; do if (nik_enchanted enchanted_book "$a" "$b") >/dev/null 2>&1; then exit 1; fi; done < "$1/data/enchantment-conflicts.tsv"' _ "$ROOT"
  [ "$status" -eq 0 ]
}
@test 'new item catalogue matches whole official registry except air' {
  run python3 "$ROOT/tools/audit-items.py"
  [ "$status" -eq 0 ]; [[ $output == *'1657'* ]]
  run nik --dry-run daj g1 topolowe_deski
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:poplar_planks'* ]]
}
@test 'legacy chain ID transparently resolves to iron_chain' {
  run nik --dry-run daj g1 lancuch
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:iron_chain '* ]]
  run nik --dry-run daj g1 chain
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:iron_chain '* ]]
}
@test 'every current mob effect including nautilus and bad luck is available' {
  run nik --dry-run efekt g1 oddech_lodzika 30
  [ "$status" -eq 0 ]; [[ $output == *'breath_of_the_nautilus'* ]]
  run nik --dry-run efekt g1 pech 30
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:unluck'* ]]
}
@test 'RCON does not mistake player name Unknown for an error' {
  export MOCK_MODE=response MOCK_RESPONSE='There are 1 of a max of 20 players online: Unknown'
  run nik online
  [ "$status" -eq 0 ]
}
@test 'real server semantic failures are recognized with ANSI styling' {
  export MOCK_MODE=response MOCK_RESPONSE=$'\033[31mTarget doesn\x27t have the requested effect\033[0m'
  run nik usun g1 sila
  [ "$status" -eq 0 ]
  export MOCK_RESPONSE='Modifier nik:frozen is already present on attribute Speed for entity PlayerOne'
  run nik zapisz
  [ "$status" -ne 0 ]
}
@test 'effect no-op exception never hides offline-player errors' {
  export MOCK_MODE=response MOCK_RESPONSE='No player was found'
  run nik usun g1 sila
  [ "$status" -ne 0 ]
}
@test 'color-only server reply is not treated as success' {
  export MOCK_MODE=response MOCK_RESPONSE=$'\033[0m'
  run nik zapisz
  [ "$status" -ne 0 ]
}
@test 'reserved player shortcuts and place/player collisions rejected' {
  printf 'other\tco\tOtherNick\n' >> "$NIK_CONFIG/players.tsv"
  run nik --dry-run status
  [ "$status" -eq 2 ]
  cp "$ROOT/config.example/players.tsv" "$NIK_CONFIG/players.tsv"
  printf 'g1\t0\t64\t0\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
  run nik --dry-run status
  [ "$status" -eq 2 ]
}
@test 'set rejects inventory slots above 26 and accepts hotbar' {
  printf 'inventory.27\tdiamond\t\n' > "$NIK_CONFIG/sets/test.tsv"
  run nik --dry-run wyposaz g1 test
  [ "$status" -eq 2 ]
  printf 'hotbar.8\tdiamond\t\n' > "$NIK_CONFIG/sets/test.tsv"
  run nik --dry-run wyposaz g1 test
  [ "$status" -eq 0 ]; [[ $output == *'hotbar.8 with minecraft:diamond 1'* ]]
}
@test 'explosion explicitly ignites creeper' {
  run nik --dry-run wybuch g1
  [ "$status" -eq 0 ]; [[ $output == *'Fuse:0s,ignited:1b'* ]]
}
@test 'completion respects global dry-run and config options' {
  run bash -c 'source "$1"; COMP_WORDS=(nik --config "$NIK_CONFIG" --dry-run daj gracz1 jajo_); COMP_CWORD=$((${#COMP_WORDS[@]}-1)); _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* ]]
  run bash -c 'source "$1"; COMP_WORDS=(d --dry-run gracz1 jajo_); COMP_CWORD=3; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'jajo_creepera'* ]]
}
@test 'enchantment table uses one row with name max and description' {
  run nik encik co
  [ "$status" -eq 0 ]; [[ $output == *'NAZWA PL'* && $output == *'NAZWA EN'* && $output == *'OPIS'* ]]
  match=$(printf '%s\n' "$output" | grep 'breach ')
  [[ $match == *'buzdygan'* && $match != *'topór'* ]]
}
@test 'public packaging excludes keys nested in allowed source folders' {
  mkdir -p "$WORK/pkg/tools" "$WORK/pkg/lib" "$WORK/pkg/config" "$WORK/pkg/config.example"
  cp "$ROOT/tools/package.py" "$WORK/pkg/tools/"
  printf public > "$WORK/pkg/lib/module.sh"
  printf private > "$WORK/pkg/lib/secret.key"
  printf private > "$WORK/pkg/config/players.tsv"
  touch "$WORK/pkg/config/.gitkeep"
  run python3 "$WORK/pkg/tools/package.py" --out "$WORK/dist" --private-config "$NIK_CONFIG"
  [ "$status" -eq 0 ]
  run python3 -c 'import zipfile,sys,pathlib; p=pathlib.Path(sys.argv[1]); z=zipfile.ZipFile(p/"nik-v2-public.zip"); assert not any(n.endswith("secret.key") or n.endswith("players.tsv") for n in z.namelist()); z=zipfile.ZipFile(p/"nik-v2-private.zip"); assert len(z.namelist())==len(set(z.namelist())); assert (p/"nik-v2-private.zip").stat().st_mode & 0o777 == 0o600' "$WORK/dist"
  [ "$status" -eq 0 ]
}
@test 'narrow enchantment and effect layouts stay readable within width' {
  export NIK_WIDTH=40
  for command in encik efekt; do
    run nik "$command" co
    [ "$status" -eq 0 ]
    while IFS= read -r line; do [ "${#line}" -le 40 ]; done <<< "$output"
  done
}
@test 'catalog updater preserves descriptions and is idempotent' {
  mkdir -p "$WORK/source/tools" "$WORK/source/data"
  cp "$ROOT/tools/update-catalog.py" "$WORK/source/tools/"
  printf 'kamien\tstone\nlancuch\tchain\n' > "$WORK/source/data/items.tsv"
  : > "$WORK/source/data/item-aliases.tsv"
  : > "$WORK/source/data/item-renames.tsv"
  printf 'szybkosc\tspeed\tszybsze bieganie\n' > "$WORK/source/data/effects.tsv"
  printf '%s' '{"minecraft:item":{"entries":{"minecraft:stone":{},"minecraft:iron_chain":{},"minecraft:air":{}}},"minecraft:mob_effect":{"entries":{"minecraft:speed":{},"minecraft:unluck":{}}}}' > "$WORK/registry.json"
  printf '%s' '{"effect.minecraft.unluck":"Pech"}' > "$WORK/pl.json"
  run python3 "$WORK/source/tools/update-catalog.py" "$WORK/registry.json" "$WORK/pl.json"
  [ "$status" -eq 0 ]
  cp "$WORK/source/data/effects.tsv" "$WORK/effects-before"
  cp "$WORK/source/data/item-renames.tsv" "$WORK/renames-before"
  run python3 "$WORK/source/tools/update-catalog.py" "$WORK/registry.json" "$WORK/pl.json"
  [ "$status" -eq 0 ]
  cmp "$WORK/effects-before" "$WORK/source/data/effects.tsv"
  cmp "$WORK/renames-before" "$WORK/source/data/item-renames.tsv"
  grep -q 'szybsze bieganie' "$WORK/source/data/effects.tsv"
}

@test 'Polish enchantments resolve to canonical English IDs' {
  run nik --dry-run encik g1 diamond_sword ostrosc:5 naprawa niezniszczalnosc:3
  [ "$status" -eq 0 ]
  [[ $output == *'"minecraft:sharpness":5'* && $output == *'"minecraft:mending":1'* && $output == *'"minecraft:unbreaking":3'* ]]
}
@test 'Polish diacritics spaces case and mixed English names work' {
  run nik --dry-run encik g1 diamond_pickaxe 'Jedwabny dotyk' 'NIEZNISZCZALNOŚĆ:3' mending
  [ "$status" -eq 0 ]; [[ $output == *'"minecraft:silk_touch":1'* && $output == *'"minecraft:unbreaking":3'* ]]
}
@test 'Polish and English duplicate aliases are rejected' {
  run nik --dry-run encik g1 diamond_sword ostrosc sharpness
  [ "$status" -eq 2 ]
}
@test 'Polish enchantments retain level type and conflict validation' {
  run nik --dry-run encik g1 diamond_sword ostrosc:6
  [ "$status" -eq 2 ]
  run nik --dry-run encik g1 shield ostrosc
  [ "$status" -eq 2 ]
  run nik --dry-run encik g1 diamond_sword ostrosc pogromca_nieumarlych
  [ "$status" -eq 2 ]
}
@test 'enchantment completion supports both languages and Polish diacritics' {
  run nik __complete encik 3 ostr
  [ "$status" -eq 0 ]; [[ $output == *'ostrosc'* ]]
  run nik __complete encik 3 sharp
  [ "$status" -eq 0 ]; [[ $output == *'sharpness'* ]]
  run nik __complete encik 4 'niezniszczalność'
  [ "$status" -eq 0 ]; [ "$output" = niezniszczalnosc ]
  [ ! -e "$MOCK_CALLS" ]
}
@test 'enchantment table includes Polish and English names together' {
  run nik encik co
  [ "$status" -eq 0 ]
  match=$(printf '%s\n' "$output" | grep 'ostrosc ')
  [[ $match == *'sharpness'* && $match == *'miecz'* ]]
}
@test 'all Polish enchantment names are equivalent to English IDs' {
  run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; NIK_COMPONENTS=modern; source "$1/lib/helpers.sh"; source "$1/lib/enchantments.sh"; for name in "${!NIK_ENCHANT_NAMES[@]}"; do id=${NIK_ENCHANT_NAMES[$name]}; nik_enchanted enchanted_book "$name"; polish=$REPLY; nik_enchanted enchanted_book "$id"; [[ $REPLY == "$polish" ]]; done' _ "$ROOT"
  [ "$status" -eq 0 ]
}
@test 'Polish game mode commands target only configured player' {
  for pair in 'kreatywny creative' 'przetrwanie survival' 'obserwator spectator' 'przygodowy adventure'; do
    read -r command mode <<< "$pair"
    run nik --dry-run "$command" g1
    [ "$status" -eq 0 ]; [[ $output == *"gamemode $mode PlayerOne"* && $output != *'@a'* ]]
  done
  [ ! -e "$MOCK_CALLS" ]
}
@test 'hand enchanting accepts Polish names and never gives a new item' {
  run nik --dry-run zaklnij g1 ostrosc:5 naprawa
  [ "$status" -eq 0 ]; [[ $output == *'enchant PlayerOne minecraft:sharpness 5'* && $output == *'enchant PlayerOne minecraft:mending 1'* && $output != *'give '* ]]
}
@test 'hand enchanting validates all levels and conflicts before first write' {
  run nik zaklnij g1 naprawa ostrosc:6
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  run nik zaklnij g1 ostrosc pogromca_nieumarlych
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'hand enchanting rejects itemless and incompatible game responses' {
  export MOCK_MODE=response MOCK_RESPONSE='PlayerOne is not holding any item'
  run nik zaklnij g1 naprawa
  [ "$status" -eq 1 ]
  export MOCK_RESPONSE='Diamond Sword cannot support that enchantment'
  run nik zaklnij g1 naprawa
  [ "$status" -eq 1 ]
}
@test 'hand enchantment completion uses Polish and English' {
  run nik __complete zaklnij 2 ostr
  [ "$status" -eq 0 ]; [[ $output == *ostrosc* ]]
  run nik __complete zaklnij 3 mending
  [ "$status" -eq 0 ]; [ "$output" = mending ]
}
@test 'favorite set persists validated canonical items and counts' {
  run nik zestaw zapisz wyprawa diamentowy_miecz pochodnia=64
  [ "$status" -eq 0 ]; [ -f "$NIK_CONFIG/favorites/wyprawa.tsv" ]
  run nik --dry-run zestaw g1 wyprawa
  [ "$status" -eq 0 ]; [[ $output == *'give PlayerOne minecraft:diamond_sword 1'* && $output == *'give PlayerOne minecraft:torch 64'* && $output != *'item replace'* ]]
  run nik zestaw pokaz wyprawa
  [ "$status" -eq 0 ]; [[ $output == *'diamentowy_miecz'* && $output == *'64'* ]]
  run nik zestaw lista
  [ "$status" -eq 0 ]; [[ $output == *'wyprawa'* ]]
  [ ! -e "$MOCK_CALLS" ]
}
@test 'bad last favorite input leaves no partial configuration' {
  run nik zestaw zapisz zly diamentowy_miecz nieznany_przedmiot
  [ "$status" -eq 2 ]; [ ! -e "$NIK_CONFIG/favorites/zly.tsv" ]
  run nik --dry-run zestaw zapisz wyprawa pochodnia=64
  [ "$status" -eq 0 ]; [ ! -e "$NIK_CONFIG/favorites/wyprawa.tsv" ]
}
@test 'favorite set cannot overwrite existing set or escape config path' {
  nik zestaw zapisz wyprawa pochodnia=64
  run nik zestaw zapisz wyprawa kamien
  [ "$status" -eq 2 ]; [[ $(cat "$NIK_CONFIG/favorites/wyprawa.tsv") == *'torch'* ]]
  run nik zestaw zapisz ../escape kamien
  [ "$status" -eq 2 ]; [ ! -e "$WORK/escape.tsv" ]
}
@test 'favorite set validates every row before giving items' {
  mkdir "$NIK_CONFIG/favorites"
  printf 'torch\t64\ninvalid_item\t1\n' > "$NIK_CONFIG/favorites/zly.tsv"
  run nik zestaw g1 zly
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'typos suggest Polish enchantments items and commands' {
  run nik --dry-run encik g1 diamond_sword ostrsoc
  [ "$status" -eq 2 ]; [[ $output == *'Czy chodziło o: ostrosc?'* ]]
  run nik --dry-run daj g1 diamentowy_mieczx
  [ "$status" -eq 2 ]; [[ $output == *'Czy chodziło o: diamentowy_miecz?'* ]]
  run nik kreatwyn y
  [ "$status" -eq 2 ]; [[ $output == *'Czy chodziło o: kreatywny?'* ]]
  [ ! -e "$MOCK_CALLS" ]
}
@test 'world restore requires explicit confirmation and validates ID' {
  run nik przywroc invalid
  [ "$status" -eq 2 ]; [[ $output == *'--potwierdz'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'world backup dry run never touches Docker or creates archives' {
  run nik --dry-run kopia
  [ "$status" -eq 0 ]; [[ $output == *'archiwum świata'* ]]; [ ! -e "$MOCK_CALLS" ]; [ ! -d "$ROOT/world-backups" ]
}
@test 'new commands are available after sourcing' {
  run bash -c 'source "$1"; alias zaklnij kreatywny przetrwanie obserwator zestaw kopia przywroc; complete -p zaklnij zestaw przywroc' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *'nik kreatywny'* ]]
}

@test 'Polish options work and English options stay compatible' {
  run nik --konfiguracja "$NIK_CONFIG" --podglad kreatywny g1
  [ "$status" -eq 0 ]; [[ $output == *'[podgląd] gamemode creative PlayerOne'* ]]; [ ! -e "$MOCK_CALLS" ]
  run nik --config "$NIK_CONFIG" --dry-run przetrwanie g1
  [ "$status" -eq 0 ]; [[ $output == *'gamemode survival PlayerOne'* ]]
  run nik encik --pomoc
  [ "$status" -eq 0 ]; [[ $output == *'--potwierdz'* && $output != *'--confirm'* ]]
  run nik pomoc
  [ "$status" -eq 0 ]; [[ $output == *'--konfiguracja'* ]]
  run nik --wersja
  [ "$status" -eq 0 ]; [[ $output == *'2.1.0'* ]]
}
@test 'Polish confirmation flag authorizes a command' {
  run nik --potwierdz wyczysc g1
  [ "$status" -eq 0 ]; [[ $output == *'Command completed successfully'* ]]
}
@test 'completion understands Polish options and suggests Polish option names' {
  run bash -c 'source "$1"; COMP_WORDS=(nik --konfiguracja "$NIK_CONFIG" --podglad zaklnij g1 ostr); COMP_CWORD=6; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [[ $output == *ostrosc* ]]
  run bash -c 'source "$1"; COMP_WORDS=(nik --pot); COMP_CWORD=1; _nik_v2_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]; [ "$output" = --potwierdz ]
}
