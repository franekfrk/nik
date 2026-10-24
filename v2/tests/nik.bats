#!/usr/bin/env bats
setup() {
    ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    WORK=$(mktemp -d)
    cp -R "$ROOT/config.example" "$WORK/config"
    export NIK_CONFIG="$WORK/config" NIK_STATE="$WORK/runtime"
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
if [[ $MOCK_MODE == rules ]]; then
    command=${*: -1}; read -r verb key value <<< "$command"; key=${key#minecraft:}
    if [[ ! -e $MOCK_STATE ]]; then printf 'mob_griefing\ttrue\nfire_spread_radius_around_player\t128\ntnt_explodes\ttrue\nprojectiles_can_break_blocks\ttrue\n' > "$MOCK_STATE"; fi
    if [[ -n ${value:-} ]]; then
        if [[ ${MOCK_RULE_FAIL:-} == "$key" ]]; then printf 'Unable to set game rule\n'; exit 0; fi
        awk -F '\t' -v k="$key" -v v="$value" 'BEGIN{OFS="\t"} $1==k{$2=v} {print}' "$MOCK_STATE" > "$MOCK_STATE.tmp"
        mv "$MOCK_STATE.tmp" "$MOCK_STATE"
        printf 'Game rule %s is now set to %s\n' "$key" "$value"
    else value=$(awk -F '\t' -v k="$key" '$1==k{print $2}' "$MOCK_STATE"); printf 'Game rule %s is currently set to %s\n' "$key" "$value"; fi
    exit 0
fi
if [[ $MOCK_MODE == inventory_truncated ]]; then
    command=${*: -1}; field=${command##* }
    case $field in
      Inventory|EnderItems) printf 'PlayerOne has the following entity data: [{Slot: 0b,...\n' ;;
      'Inventory[0]'|'EnderItems[0]') printf 'PlayerOne has the following entity data: {Slot:0b,id:"minecraft:diamond_sword",count:1,components:{"minecraft:enchantments":{"minecraft:sharpness":5}}}\n' ;;
      'SelectedItem') printf 'PlayerOne has the following entity data: {components:...\n' ;;
      'SelectedItem.id') printf 'PlayerOne has the following entity data: "minecraft:diamond_sword"\n' ;;
      'SelectedItem.components."minecraft:damage"') printf 'PlayerOne has the following entity data: 0\n' ;;
      *) printf 'Found no elements matching %s\n' "$field" ;;
    esac
    exit 0
fi
if [[ $MOCK_MODE == inventory ]]; then
    printf '%s\n' 'PlayerOne has the following entity data: [{Slot: 0b, id: "minecraft:diamond_sword", count: 1, components: {"minecraft:enchantments": {"minecraft:sharpness": 5, "minecraft:mending": 1}}}, {Slot: 9b, id: "minecraft:torch", count: 64}]'
    exit 0
fi
if [[ $MOCK_MODE == travel ]]; then
    command=${*: -1}
    if [[ $command == 'data get entity '* ]]; then
        field=${command##* }
        if [[ ${MOCK_LOCATION_ERROR:-} == "$field" ]]; then printf 'No entity was found\n'; exit 0; fi
        case $field in
          Pos) printf '%s\n' 'PlayerOne has the following entity data: [12.5d, 64.0d, -9.25d]' ;;
          Dimension) printf '%s\n' 'PlayerOne has the following entity data: "minecraft:the_nether"' ;;
          Rotation) printf '%s\n' 'PlayerOne has the following entity data: [45.5f, -12.0f]' ;;
        esac
    elif [[ ${MOCK_TP_ERROR:-0} == 1 ]]; then printf 'No entity was found\n'
    else printf 'Teleported PlayerOne to 1, 64, 2\n'; fi
    exit 0
fi
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
@test 'version' { run nik --version; [ "$output" = 'NIK 2.6.2' ]; }
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
  cp "$ROOT/tools/package.py" "$ROOT/tools/release_manifest.py" "$WORK/pkg/tools/"
  printf '%s\n' '["tools/package.py","tools/release_manifest.py","tools/public-files.json","lib/module.sh","config/.gitkeep"]' > "$WORK/pkg/tools/public-files.json"
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
  [ "$status" -eq 0 ]; [[ $output == *'2.6.2'* ]]
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

@test 'where prints parsed coordinates dimension and orientation without teleport' {
  export MOCK_MODE=travel
  run nik gdzie g1
  [ "$status" -eq 0 ]; [[ $output == *'X: 12.5   Y: 64   Z: -9.25'* && $output == *'minecraft:the_nether'* && $output == *'45.5°'* ]]
  [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 3 ]; [[ $(cat "$MOCK_CALLS") != *'run tp '* ]]; [ ! -d "$NIK_STATE" ]
}
@test 'teleport captures source before changing position and return consumes point' {
  export MOCK_MODE=travel
  run nik tp g1 1 64 2
  [ "$status" -eq 0 ]; [ -f "$NIK_STATE/returns/PlayerOne.json" ]
  [ "$(stat -c %a "$NIK_STATE/returns/PlayerOne.json")" = 600 ]
  [ "$(stat -c %a "$NIK_STATE/returns")" = 700 ]
  run nik powrot g1
  [ "$status" -eq 0 ]; [[ $(cat "$MOCK_CALLS") == *'execute in minecraft:the_nether run tp PlayerOne 12.5 64 -9.25 45.5 -12'* ]]
  [ ! -e "$NIK_STATE/returns/PlayerOne.json" ]
  run nik powrot g1
  [ "$status" -eq 2 ]; [[ $output == *'Brak punktu powrotu'* ]]
}
@test 'home castle join and player teleport all record return points' {
  export MOCK_MODE=travel
  printf 'dom\t1\t64\t2\tminecraft:overworld\nzamek\t3\t70\t4\tminecraft:overworld\n' > "$NIK_CONFIG/places.tsv"
  for command in 'dom g1' 'zamek g1' 'dolacz g1 g2' 'tp g1 g2'; do
    read -r -a args <<< "$command"
    run nik "${args[@]}"
    [ "$status" -eq 0 ]; [ -f "$NIK_STATE/returns/PlayerOne.json" ]
    rm "$NIK_STATE/returns/PlayerOne.json"
  done
}
@test 'offline or malformed location aborts before teleport' {
  export MOCK_MODE=travel MOCK_LOCATION_ERROR=Dimension
  run nik tp g1 1 64 2
  [ "$status" -eq 1 ]; [[ $(cat "$MOCK_CALLS") != *'run tp '* ]]; [ ! -e "$NIK_STATE/returns/PlayerOne.json" ]
  export MOCK_MODE=ok
  run nik tp g1 1 64 2
  [ "$status" -eq 2 ]; [[ $output == *'Nie rozpoznano'* ]]; [[ $(cat "$MOCK_CALLS") != *'run tp '* ]]
}
@test 'failed teleport preserves existing return point and removes pending file' {
  export MOCK_MODE=travel
  nik tp g1 1 64 2
  old=$(cat "$NIK_STATE/returns/PlayerOne.json")
  export MOCK_TP_ERROR=1
  run nik tp g1 5 64 6
  [ "$status" -eq 1 ]; [ "$(cat "$NIK_STATE/returns/PlayerOne.json")" = "$old" ]
  run find "$NIK_STATE" -name '.pending.*'
  [ "$output" = '' ]
}
@test 'failed return preserves point and preview never consumes it' {
  export MOCK_MODE=travel
  nik tp g1 1 64 2
  rm "$MOCK_CALLS"
  run nik powrot g1 --podglad
  [ "$status" -eq 0 ]; [ -f "$NIK_STATE/returns/PlayerOne.json" ]; [ ! -e "$MOCK_CALLS" ]
  export MOCK_TP_ERROR=1
  run nik powrot g1
  [ "$status" -eq 1 ]; [ -f "$NIK_STATE/returns/PlayerOne.json" ]
}
@test 'position teleport and dad previews have no Docker or persistent side effects' {
  run nik gdzie g1 --podglad
  [ "$status" -eq 0 ]; [[ $output == *'data get entity PlayerOne Pos'* ]]
  run nik tp g1 1 64 2 --podglad
  [ "$status" -eq 0 ]
  run nik tata g1 'Cześć, Franek!' --podglad
  [ "$status" -eq 0 ]; [[ $output == *'tellraw PlayerOne'* && $output == *'[Tata ♥]'* ]]
  [ ! -e "$MOCK_CALLS" ]; [ ! -d "$NIK_STATE" ]
}
@test 'tampered return player container dimension and coordinates are rejected before RCON' {
  export MOCK_MODE=travel
  nik tp g1 1 64 2
  rm "$MOCK_CALLS"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["dimension"]="minecraft:overworld run kill @a"; open(p,"w").write(json.dumps(d))' "$NIK_STATE/returns/PlayerOne.json"
  run nik powrot g1
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'return state symlinks are rejected before reading or teleporting' {
  mkdir -p "$NIK_STATE/returns"
  ln -s "$NIK_CONFIG/players.tsv" "$NIK_STATE/returns/PlayerOne.json"
  run nik powrot g1
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'dad text stays literal and is addressed to only configured player' {
  run nik --podglad tata g1 'Cześć "Franek" \ @a {"clickEvent":{"action":"run_command","value":"/kill @a"}}'
  [ "$status" -eq 0 ]; [[ $output == *'tellraw PlayerOne '* && $output != *'tellraw @a '* ]]
  payload=${output#*tellraw PlayerOne }
  run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d[1]["text"]=="[Tata ♥] "; assert set(d[2])=={"text","color","bold"}; assert "clickEvent" in d[2]["text"]' "$payload"
  [ "$status" -eq 0 ]
}
@test 'dad message rejects controls empty oversized text and unknown targets' {
  for message in '' '   ' $'hello\nworld' $'escape\033[31m'; do
    run nik tata g1 "$message"
    [ "$status" -eq 2 ]
  done
  long=$(printf '%0513d' 0)
  run nik tata g1 "$long"
  [ "$status" -eq 2 ]
  run nik tata nobody Czesc
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'silent vanilla tellraw succeeds while offline and transport errors fail' {
  export MOCK_MODE=empty
  run nik tata g1 Czesc
  [ "$status" -eq 0 ]; [[ $output == *'Wysłano wiadomość od Taty'* ]]
  export MOCK_MODE=response MOCK_RESPONSE='No player was found'
  run nik tata g1 Czesc
  [ "$status" -eq 1 ]
  export MOCK_MODE=transport
  run nik tata g1 Czesc
  [ "$status" -eq 7 ]
}
@test 'new travel and message aliases and player completions are installed' {
  run bash -c 'source "$1"; alias gdzie powrot tata wiadomosc; complete -p gdzie powrot tata wiadomosc' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]
  for command in gdzie powrot tata wiadomosc; do
    run nik __complete "$command" 1 g
    [ "$status" -eq 0 ]; [[ $output == *'g1'* ]]
  done
}

@test 'point captures actual coordinates and dimension without teleporting' {
  export MOCK_MODE=travel
  run nik punkt g1 baza
  [ "$status" -eq 0 ]; [[ $output == *'Zapisano punkt: baza'* && $output == *'tp g1 baza'* ]]
  [[ $(cat "$NIK_CONFIG/places.tsv") == *$'baza\t12.5\t64\t-9.25\tminecraft:the_nether'* ]]
  [[ $(cat "$MOCK_CALLS") != *'run tp '* ]]; [ ! -d "$NIK_STATE" ]
  run nik tp g1 baza --podglad
  [ "$status" -eq 0 ]; [[ $output == *'execute in minecraft:the_nether run tp PlayerOne 12.5 64 -9.25'* ]]
}
@test 'point rejects collisions invalid names and offline players without config writes' {
  before=$(cat "$NIK_CONFIG/places.tsv")
  run nik punkt g1 g2
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  run nik punkt g1 '../escape'
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  export MOCK_MODE=travel MOCK_LOCATION_ERROR=Pos
  run nik punkt g1 baza
  [ "$status" -eq 1 ]; [ "$(cat "$NIK_CONFIG/places.tsv")" = "$before" ]
}
@test 'point preview and existing point do not access Docker or overwrite' {
  run nik punkt g1 baza --podglad
  [ "$status" -eq 0 ]; [[ $(cat "$NIK_CONFIG/places.tsv") != *'baza'* ]]; [ ! -e "$MOCK_CALLS" ]
  printf 'baza\t1\t64\t2\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
  run nik punkt g1 baza
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'inventory displays Polish names slots counts and enchantments without game writes' {
  export MOCK_MODE=inventory
  run nik plecak g1
  [ "$status" -eq 0 ]; [[ $output == *'PLECAK GRACZA'* && $output == *'diamentowy_miecz'* && $output == *'pochodnia'* && $output == *'ostrosc: 5'* && $output == *'naprawa: 1'* && $output == *'64'* ]]
  [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]; [[ $(cat "$MOCK_CALLS") == *'data get entity PlayerOne Inventory'* ]]
}
@test 'empty inventory and malformed or offline replies are handled clearly' {
  export MOCK_MODE=response MOCK_RESPONSE='PlayerOne has the following entity data: []'
  run nik plecak g1
  [ "$status" -eq 0 ]; [[ $output == *'puste'* ]]
  export MOCK_RESPONSE='PlayerOne has the following entity data: [{Slot:0b,id:'
  run nik plecak g1
  [ "$status" -eq 2 ]; [[ $output != *'Traceback'* ]]
  export MOCK_RESPONSE='No entity was found'
  run nik plecak g1
  [ "$status" -eq 1 ]
}
@test 'inventory and title previews have no Docker side effects' {
  run nik plecak g1 --podglad
  [ "$status" -eq 0 ]; [[ $output == *'data get entity PlayerOne Inventory'* ]]
  run nik napis g1 'Brawo! ♥' --podglad
  [ "$status" -eq 0 ]; [[ $output == *'title PlayerOne times 10 80 20'* && $output == *'Od Taty ♥'* && $output == *'"text":"Brawo! ♥"'* ]]
  [ ! -e "$MOCK_CALLS" ]
}
@test 'title validates the whole text before setting times and stops after game errors' {
  run nik napis g1 $'Bad\nmessage'
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  export MOCK_MODE=semantic
  run nik napis g1 Brawo
  [ "$status" -eq 1 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]
}
@test 'title text and message-looking flags remain literal without clickable actions' {
  run nik napis g1 '{"clickEvent":{"action":"run_command","value":"/kill @a"}}' --podglad
  [ "$status" -eq 0 ]
  payload=${output##*title PlayerOne title }
  run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert set(d)=={"text","color","bold"}; assert "clickEvent" in d["text"]' "$payload"
  [ "$status" -eq 0 ]
  run nik tata g1 -- --title
  [ "$status" -eq 0 ]
  [[ $(cat "$MOCK_CALLS") == *'[Tata ♥]'* && $(cat "$MOCK_CALLS") == *'"text":"--title"'* ]]
}
@test 'summon supports Polish English aliases and namespace without giving eggs' {
  for creature in krowa cow minecraft:cow; do
    run nik przywolaj g1 "$creature" --podglad
    [ "$status" -eq 0 ]; [[ $output == *'execute at PlayerOne run summon minecraft:cow ~2 ~ ~'* && $output != *'give '* ]]
  done
  run nik przywolaj g1 golem --podglad
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:iron_golem'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'summon forbids injection and requires explicit confirmation for bosses' {
  run nik przywolaj g1 'cow {Passengers:[]}'
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  run nik przywolaj g1 smok
  [ "$status" -eq 2 ]; [[ $output == *'--potwierdz'* ]]; [ ! -e "$MOCK_CALLS" ]
  run nik przywolaj g1 wither --potwierdz --podglad
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:wither'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'creature list and completion support Polish and English without Docker' {
  run nik przywolaj co
  [ "$status" -eq 0 ]; [[ $output == *'STWORZENIA'* && $output == *'krowa'* && $output == *'cow'* ]]
  run nik __complete przywolaj 2 kro
  [ "$status" -eq 0 ]; [[ $output == *'krowa'* ]]
  run nik __complete przywolaj 2 cow
  [ "$status" -eq 0 ]; [[ $output == *'cow'* ]]
  [ ! -e "$MOCK_CALLS" ]
}
@test 'all creature names and aliases resolve to their registry IDs' {
  run bash -c 'set -Eeuo pipefail; NIK_ROOT=$1; source "$1/lib/helpers.sh"; source "$1/lib/adventures.sh"; for name in "${!NIK_CREATURES[@]}"; do nik_creature "$name"; [[ $REPLY == "${NIK_CREATURES[$name]}" ]]; id=$REPLY; nik_creature "$id"; [[ $REPLY == "$id" ]]; done; for name in "${!NIK_CREATURE_ALIASES[@]}"; do nik_creature "$name"; [[ $REPLY == "${NIK_CREATURE_ALIASES[$name]}" ]]; done' _ "$ROOT"
  [ "$status" -eq 0 ]
}
@test 'new adventure aliases and completion are available after sourcing' {
  run bash -c 'source "$1"; alias punkt plecak napis przywolaj; complete -p punkt plecak napis przywolaj' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]
}
@test 'omitted empty Inventory path is treated as an empty backpack only' {
  export MOCK_MODE=response MOCK_RESPONSE='Found no elements matching Inventory'
  run nik plecak g1
  [ "$status" -eq 0 ]; [[ $output == *'puste'* ]]
  run nik gdzie g1
  [ "$status" -eq 1 ]
}
@test 'narrow inventory output respects terminal width and color settings' {
  export MOCK_MODE=inventory NIK_WIDTH=40
  run nik plecak g1
  [ "$status" -eq 0 ]
  while IFS= read -r line; do [ "${#line}" -le 40 ]; done <<< "$output"
  export NIK_COLOR=always
  run nik plecak g1
  [ "$status" -eq 0 ]; [[ $output == *$'\033['* ]]
}
@test 'duration suffixes normalize seconds minutes hours and old integer input' {
  for pair in '30s 30' '10m 600' '1h 3600' '008 8'; do
    read -r input seconds <<< "$pair"
    run nik efekt g1 sila "$input" --podglad
    [ "$status" -eq 0 ]; [[ $output == *"minecraft:strength $seconds 0"* ]]
    run nik pogoda slonce "$input" --podglad
    [ "$status" -eq 0 ]; [[ $output == *"weather clear ${seconds}s"* ]]
  done
  [ ! -e "$MOCK_CALLS" ]
}
@test 'duration invalid suffixes overflow zero and injected input are rejected' {
  for input in 0 0m 99999999h 1.5h 1d '1m run kill @a'; do
    run nik pogoda slonce "$input"
    [ "$status" -eq 2 ]
    run nik efekt g1 sila "$input"
    [ "$status" -eq 2 ]
  done
  [ ! -e "$MOCK_CALLS" ]
}
@test 'rescue validates destination before effects and previews full plan' {
  run nik ratunek g1
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  printf 'baza\t1\t64\t2\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
  run nik ratunek g1 baza --podglad
  [ "$status" -eq 0 ]; [[ $output == *'minecraft:fire_resistance 30 0'* && $output == *'run tp PlayerOne'* && $output == *'instant_health'* ]]
  [ ! -e "$MOCK_CALLS" ]
}
@test 'repair only changes damage in place and skips undamaged item' {
  export MOCK_MODE=response MOCK_RESPONSE='PlayerOne has the following entity data: {id:"minecraft:diamond_sword",count:1,components:{"minecraft:damage":500,"minecraft:enchantments":{"minecraft:sharpness":5}}}'
  run nik napraw g1
  [ "$status" -eq 0 ]; [[ $(cat "$MOCK_CALLS") == *'item modify entity PlayerOne weapon.mainhand {type:"minecraft:set_damage",damage:1.0,add:false}'* && $(cat "$MOCK_CALLS") != *'item replace'* && $(cat "$MOCK_CALLS") != *'give '* ]]
  rm "$MOCK_CALLS"
  export MOCK_RESPONSE='PlayerOne has the following entity data: {id:"minecraft:stone",count:64}'
  run nik napraw g1
  [ "$status" -eq 0 ]; [[ $(cat "$MOCK_CALLS") != *'item modify'* && $output == *'nie ma zapisanych uszkodzeń'* ]]
}
@test 'repair and ender previews do not query or mutate game' {
  run nik napraw g1 --podglad
  [ "$status" -eq 0 ]; [[ $output == *'item modify'* ]]
  run nik ender g1 --podglad
  [ "$status" -eq 0 ]; [[ $output == *'EnderItems'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'ender inventory uses its own slot labels and handles omitted empty list' {
  export MOCK_MODE=response MOCK_RESPONSE='PlayerOne has the following entity data: [{Slot:0b,id:"minecraft:diamond",count:4},{Slot:26b,id:"minecraft:torch",count:64}]'
  run nik ender g1
  [ "$status" -eq 0 ]; [[ $output == *'SKRZYNIA ENDERA'* && $output == *'slot 27'* && $output != *'pasek 1'* ]]
  export MOCK_RESPONSE='Found no elements matching EnderItems'
  run nik ender g1
  [ "$status" -eq 0 ]; [[ $output == *'pusta'* ]]
}
@test 'point list and confirmed deletion preserve other places' {
  printf 'baza\t1\t64\t2\tminecraft:overworld\ndruga\t3\t70\t4\tminecraft:the_nether\n' >> "$NIK_CONFIG/places.tsv"
  run nik punkt lista
  [ "$status" -eq 0 ]; [[ $output == *'ZAPISANE MIEJSCA'* && $output == *'druga'* ]]
  run nik punkt usun druga
  [ "$status" -eq 2 ]; [[ $(cat "$NIK_CONFIG/places.tsv") == *'druga'* ]]
  run nik punkt usun druga --podglad
  [ "$status" -eq 0 ]; [[ $(cat "$NIK_CONFIG/places.tsv") == *'druga'* ]]
  run nik punkt usun druga --potwierdz
  [ "$status" -eq 0 ]; [[ $(cat "$NIK_CONFIG/places.tsv") != *'druga'* && $(cat "$NIK_CONFIG/places.tsv") == *'baza'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'fireworks are targeted visual particles and sounds without explosive entities' {
  run nik fajerwerki g1 --podglad
  [ "$status" -eq 0 ]; [[ $output == *'particle minecraft:firework'* && $output == *'particle minecraft:dust'* && $output == *'playsound'* && $output != *'summon'* && $output != *'@a'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'quest creates a private in-game book with literal text and completion state' {
  run nik zadanie g1 'Zbuduj latarnię ♥'
  [ "$status" -eq 0 ]; [ -f "$NIK_CONFIG/quests/PlayerOne.json" ]; [ "$(stat -c %a "$NIK_CONFIG/quests/PlayerOne.json")" = 600 ]
  [[ $(cat "$MOCK_CALLS") == *'give PlayerOne minecraft:written_book'* && $(cat "$MOCK_CALLS") == *'Zadanie od Taty'* ]]
  run nik zadanie g1
  [ "$status" -eq 0 ]; [[ $output == *'Zbuduj latarnię ♥'* && $output == *'aktywne'* ]]
  run nik zadanie g1 'Nadpisz aktywne'
  [ "$status" -eq 2 ]
  run nik zadanie g1 gotowe
  [ "$status" -eq 0 ]
  run nik zadanie g1 pokaz
  [ "$status" -eq 0 ]; [[ $output == *'gotowe'* ]]
  run nik zadanie g1 ksiazka --podglad
  [ "$status" -eq 0 ]; [[ $output == *'Status: gotowe'* ]]
}
@test 'quest rejects bad text and failed give leaves no saved active task' {
  run nik zadanie g1 $'bad\ntext'
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]; [ ! -e "$NIK_CONFIG/quests/PlayerOne.json" ]
  export MOCK_MODE=semantic
  run nik zadanie g1 'Zbuduj domek'
  [ "$status" -eq 1 ]; [ ! -e "$NIK_CONFIG/quests/PlayerOne.json" ]
}
@test 'quest preview has no persistent writes and deletion requires confirmation' {
  run nik zadanie g1 'Zbuduj domek' --podglad
  [ "$status" -eq 0 ]; [ ! -e "$NIK_CONFIG/quests" ]; [ ! -e "$MOCK_CALLS" ]
  nik zadanie g1 'Zbuduj domek'
  run nik zadanie g1 usun
  [ "$status" -eq 2 ]; [ -f "$NIK_CONFIG/quests/PlayerOne.json" ]
  run nik zadanie g1 usun --potwierdz
  [ "$status" -eq 0 ]; [ ! -f "$NIK_CONFIG/quests/PlayerOne.json" ]
}
@test 'protection refuses unconfirmed world mutations and preview avoids Docker' {
  run nik ochrona budowanie
  [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
  run nik ochrona budowanie --podglad
  [ "$status" -eq 0 ]; [[ $output == *'fire_spread_radius_around_player 0'* && $output == *'mob_griefing false'* && $output == *'tnt_explodes false'* ]]; [ ! -e "$MOCK_CALLS" ]; [ ! -d "$NIK_STATE" ]
}
@test 'new help and status panels fit a narrow terminal and retain rainbow footer' {
  export NIK_WIDTH=40 NIK_COLOR=never
  for command in help 'status --podglad'; do
    read -r -a args <<< "$command"
    run nik "${args[@]}"
    [ "$status" -eq 0 ]
    while IFS= read -r line; do [ "${#line}" -le 40 ]; done <<< "$output"
  done
  run nik help
  [[ $output == *'PRZEDMIOTY I EKWIPUNEK'* && $output == *'OD TATY DLA FRANKA'* && $output == *'┌'* && $output == *'Dla Franka ♥ Tata'* ]]
}
@test 'family command aliases and contextual completions are installed' {
  run bash -c 'source "$1"; alias ratunek napraw ender fajerwerki zadanie ochrona; complete -p ochrona zadanie ratunek' _ "$ROOT/nik.sh"
  [ "$status" -eq 0 ]
  run nik __complete ochrona 1 bud
  [ "$status" -eq 0 ]; [[ $output == *'budowanie'* ]]
  run nik __complete zadanie 2 ksia
  [ "$status" -eq 0 ]; [[ $output == *'ksiazka'* ]]
  printf 'baza\t1\t64\t2\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
  run nik __complete ratunek 2 baz
  [ "$status" -eq 0 ]; [[ $output == *'baza'* ]]
}

@test 'protection saves exact old rules and restores them after changing the profile' {
  export MOCK_MODE=rules
  run nik ochrona budowanie --potwierdz
  [ "$status" -eq 0 ]; [ -f "$NIK_STATE/protection/minecraft.json" ]
  [[ $(cat "$MOCK_STATE") == *$'fire_spread_radius_around_player\t0'* ]]
  run nik ochrona status
  [ "$status" -eq 0 ]; [[ $output == *'Niszczenie przez moby: wyłączone'* ]]
  run nik ochrona budowanie --potwierdz
  [ "$status" -eq 2 ]
  run nik ochrona wylacz --potwierdz
  [ "$status" -eq 0 ]; [ ! -e "$NIK_STATE/protection/minecraft.json" ]
  [[ $(cat "$MOCK_STATE") == *$'fire_spread_radius_around_player\t128'* && $(cat "$MOCK_STATE") == *$'mob_griefing\ttrue'* ]]
}
@test 'partially failed protection preserves originals and can be recovered' {
  export MOCK_MODE=rules MOCK_RULE_FAIL=tnt_explodes
  run nik ochrona budowanie --potwierdz
  [ "$status" -eq 1 ]; [ -f "$NIK_STATE/protection/minecraft.json" ]
  unset MOCK_RULE_FAIL
  run nik ochrona wylacz --potwierdz
  [ "$status" -eq 0 ]; [[ $(cat "$MOCK_STATE") == *$'mob_griefing\ttrue'* && $(cat "$MOCK_STATE") == *$'fire_spread_radius_around_player\t128'* ]]
}
@test 'rescue heals before teleport and removes the movement lock after reaching safety' {
  printf 'baza\t1\t64\t2\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
  run nik ratunek g1 baza --podglad
  [ "$status" -eq 0 ]
  health=$(printf '%s\n' "$output" | awk '/instant_health/{print NR}')
  tp=$(printf '%s\n' "$output" | awk '/run tp PlayerOne/{print NR}')
  thaw=$(printf '%s\n' "$output" | awk '/movement_speed modifier remove/{print NR}')
  [ "$health" -lt "$tp" ]; [ "$tp" -lt "$thaw" ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'new commands registered and shell shortcuts' {
    run nik polecenia
    [ "$status" -eq 0 ]; for command in prowadz odliczanie losuj nagroda przepis menu; do [[ $output == *"$command"* ]]; done
    run bash -c 'source "$1"; alias prowadz odliczanie losuj nagroda przepis' _ "$ROOT/nik.sh"
    [ "$status" -eq 0 ]
}
@test 'guidance preview has no reads writes Docker or sleep' {
    printf 'baza\t100\t64\t200\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
    run nik prowadz g1 baza 10m --podglad
    [ "$status" -eq 0 ]; [[ $output == *'actionbar'* && $output == *'600 s'* ]]; [ ! -e "$MOCK_CALLS" ]; [ ! -d "$NIK_STATE" ]
}
@test 'guidance rejects missing point and excessive duration' {
    run nik prowadz g1 missing --podglad; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    printf 'baza\t100\t64\t200\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
    run nik prowadz g1 baza 11m --podglad; [ "$status" -eq 2 ]
}
@test 'guidance checks dimension before sending HUD' {
    export MOCK_MODE=travel
    printf 'baza\t100\t64\t200\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
    run nik prowadz g1 baza 1s; [ "$status" -eq 2 ]; [[ $output == *'innym wymiarze'* ]]; ! grep -q actionbar "$MOCK_CALLS"
}
@test 'guidance reaches nearby target with height information' {
    export MOCK_MODE=travel
    printf 'baza\t12.5\t80\t-9.25\tminecraft:the_nether\n' >> "$NIK_CONFIG/places.tsv"
    run nik prowadz g1 baza; [ "$status" -eq 0 ]; grep -q actionbar "$MOCK_CALLS"; [[ $output == *'pobliżu'* ]]
}
@test 'guidance transport failure stops without HUD' {
    export MOCK_MODE=transport
    printf 'baza\t100\t64\t200\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
    run nik prowadz g1 baza 1s; [ "$status" -eq 7 ]; ! grep -q actionbar "$MOCK_CALLS"
}
@test 'countdown preview literal title and no sleeps or Docker' {
    run nik odliczanie g1 3 'Brawo "Franek" ♥' --podglad
    [ "$status" -eq 0 ]; [[ $output == *'"text":"3"'* && $output == *'"text":"1"'* && $output == *'aqua'* ]]; [ ! -e "$MOCK_CALLS" ]
}
@test 'countdown validates all input before first mutation' {
    run nik odliczanie g1 61; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    run nik odliczanie g1 2 $'hello\nworld'; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'countdown game failure stops early' {
    export MOCK_MODE=semantic
    run nik odliczanie g1 2; [ "$status" -ne 0 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]
}
@test 'random challenge preview does not save quest' {
    printf 'Własne wyzwanie ♥\n' > "$NIK_CONFIG/challenges.txt"
    run nik losuj g1 --podglad; [ "$status" -eq 0 ]; [[ $output == *'Własne wyzwanie ♥'* ]]; [ ! -d "$NIK_CONFIG/quests" ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'random challenge persists valid book and refuses active overwrite' {
    printf 'Własne wyzwanie ♥\n' > "$NIK_CONFIG/challenges.txt"
    run nik losuj g1; [ "$status" -eq 0 ]; [ -f "$NIK_CONFIG/quests/PlayerOne.json" ]; grep -q written_book "$MOCK_CALLS"
    run nik losuj g1; [ "$status" -eq 2 ]
}
@test 'invalid challenge list causes no game action' {
    printf '\033[31mBad\n' > "$NIK_CONFIG/challenges.txt"
    run nik losuj g1; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'reward presets preview title and complete contents' {
    run nik nagroda g1 budowniczy --podglad; [ "$status" -eq 0 ]; [[ $output == *'minecraft:diamond 3'* && $output == *'minecraft:oak_planks 64'* && $output == *'Brawo!'* ]]; [ ! -e "$MOCK_CALLS" ]
    run nik nagroda lista; [ "$status" -eq 0 ]; [[ $output == *'odkrywca'* ]]
}
@test 'private reward overrides default and validates whole preset first' {
    mkdir "$NIK_CONFIG/rewards"; printf 'diamond\t7\n' > "$NIK_CONFIG/rewards/budowniczy.tsv"
    run nik nagroda g1 budowniczy --podglad; [ "$status" -eq 0 ]; [[ $output == *'diamond 7'* && $output != *'oak_planks'* ]]
    printf 'diamond\t7\nunknown\t1\n' > "$NIK_CONFIG/rewards/budowniczy.tsv"
    run nik nagroda g1 budowniczy; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'reward rejects paths and symlinks' {
    run nik nagroda g1 ../secret; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    mkdir "$NIK_CONFIG/rewards"; ln -s "$ROOT/data/rewards/budowniczy.tsv" "$NIK_CONFIG/rewards/test.tsv"
    run nik nagroda g1 test; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'reward stops at first failed give' {
    export MOCK_MODE=semantic
    run nik nagroda g1 budowniczy; [ "$status" -ne 0 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]
}
@test 'recipe supports Polish aliases and vanilla grid without Docker' {
    run nik przepis pochodnia; [ "$status" -eq 0 ]; [[ $output == *'wynik: 4 szt.'* && $output == *'patyk'* && $output == *'wegiel'* ]]; [ ! -e "$MOCK_CALLS" ]
    run nik przepis netherite_sword; [ "$status" -eq 0 ]; [[ $output == *'kowalski'* && $output == *'Szablon:'* ]]
}
@test 'recipes show alternatives and non craftable explanation' {
    run nik przepis oak_planks; [ "$status" -eq 0 ]; [[ $output == *'dowolny układ'* ]]
    run nik przepis dragon_egg; [ "$status" -eq 0 ]; [[ $output == *'Brak stałej receptury'* ]]
}
@test 'new completion includes recipes points and private rewards' {
    run nik __complete przepis 1 poch; [ "$status" -eq 0 ]; [[ $output == *'pochodnia'* ]]
    printf 'baza\t1\t64\t2\tminecraft:overworld\n' >> "$NIK_CONFIG/places.tsv"
    run nik __complete prowadz 2 ba; [ "$status" -eq 0 ]; [[ $output == *'baza'* ]]
    run nik __complete nagroda 2 bud; [ "$status" -eq 0 ]; [[ $output == *'budowniczy'* ]]
}
@test 'menu requires terminal and help remains available' {
    run nik menu; [ "$status" -eq 2 ]; [[ $output == *'wymaga terminala'* ]]; [ ! -e "$MOCK_CALLS" ]
    run nik menu --pomoc; [ "$status" -eq 0 ]; [[ $output == *'wybierz gracza'* ]]
}
@test 'one second countdown executes full title sequence in order' {
    run nik odliczanie g1 1 'Start ♥'; [ "$status" -eq 0 ]
    [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 5 ]
    grep '^exec ' "$MOCK_CALLS" | tail -1 | grep -q 'Start ♥'
}
@test 'strict mode includes inheritance inside command substitutions' {
    mkdir "$WORK/extensions"
    cat > "$WORK/extensions/probe.sh" <<'EXT'
probe_handler() { local value; value=$(false; printf 'MASKED FAILURE'); printf '%s' "$value"; }
nik_register probe probe_handler 0 probe 'Probe strict mode'
EXT
    run nik --rozszerzenia "$WORK/extensions" probe
    [ "$status" -eq 1 ]; [[ $output != *'MASKED FAILURE'* ]]
}
@test 'source preserves shopt options traps and caller flags' {
    run bash -c 'set +e; shopt -u inherit_errexit; trap "true" ERR; before=$(set +o); shopts=$(shopt -p); traps=$(trap -p); source "$1"; [[ $(set +o) == "$before" && $(shopt -p) == "$shopts" && $(trap -p) == "$traps" ]]' _ "$ROOT/nik.sh"
    [ "$status" -eq 0 ]
}
@test 'registry rejects invalid flags and malformed usage before config or Docker' {
    mkdir "$WORK/extensions"
    printf 'nik_register broken nik_cmd_give garbage "broken GRACZ" "Opis"\n' > "$WORK/extensions/broken.sh"
    run nik --rozszerzenia "$WORK/extensions" commands; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    printf 'nik_register broken nik_cmd_give 0 "other GRACZ" "Opis"\n' > "$WORK/extensions/broken.sh"
    run nik --rozszerzenia "$WORK/extensions" help; [ "$status" -eq 2 ]
}
@test 'registry revalidates metadata after trusted extensions' {
    mkdir "$WORK/extensions"
    printf 'NIK_DESTRUCTIVE[daj]=invalid\n' > "$WORK/extensions/broken.sh"
    run nik --rozszerzenia "$WORK/extensions" commands; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'all shell command shortcuts dispatch through registered commands' {
    run bash -c 'source "$1"; declare -A commands=(); count=0; while read -r command; do commands[$command]=1; done < <(nik polecenia); while read -r _ definition; do body=${definition#*=}; body=${body:1:-1}; case $body in "nik "*) target=${body#nik }; target=${target%% *}; [[ -v commands[$target] ]] || exit 1; count=$((count+1));; esac; done < <(alias); ((count>=40))' _ "$ROOT/nik.sh"
    [ "$status" -eq 0 ]
}
@test 'typed data for players named Unknown and Cannot are not game errors' {
    printf 'unknown\tu\tunknown\ncannot\tc\tcannot\n' >> "$NIK_CONFIG/players.tsv"
    export MOCK_MODE=response
    export MOCK_RESPONSE='Unknown has the following entity data: []'
    run nik plecak u; [ "$status" -eq 0 ]; [[ $output == *'puste'* ]]
    export MOCK_RESPONSE='Cannot has the following entity data: []'
    run nik ender c; [ "$status" -eq 0 ]; [[ $output == *'pusta'* ]]
}
@test 'audit log and lock are private before mutation' {
    run nik zapisz; [ "$status" -eq 0 ]
    [ "$(stat -c %a "$WORK/log/nik.log")" = 600 ]; [ "$(stat -c %a "$WORK/log/nik.log.lock")" = 600 ]
}
@test 'audit symlink is rejected without truncating target or calling Docker' {
    mkdir "$WORK/log"; printf 'must stay intact' > "$WORK/target"
    ln -s "$WORK/target" "$WORK/log/nik.log.lock"
    run nik zapisz; [ "$status" -ne 0 ]; [ "$(cat "$WORK/target")" = 'must stay intact' ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'busy data lock times out without changing saved places' {
    printf 'TIMEOUT=1\n' >> "$NIK_CONFIG/config.env"
    cp "$NIK_CONFIG/places.tsv" "$WORK/before"
    exec 7> "$NIK_CONFIG/places.lock"; flock -x 7
    run nik miejsce dodaj baza 1 64 2 minecraft:overworld
    [ "$status" -eq 75 ]; cmp "$WORK/before" "$NIK_CONFIG/places.tsv"
    flock -u 7; exec 7>&-
}
@test 'Docker ignoring TERM is forcibly bounded' {
    printf 'TIMEOUT=1\n' >> "$NIK_CONFIG/config.env"
    cat > "$WORK/bin/docker" <<'MOCK'
#!/usr/bin/env bash
trap '' TERM
while :; do sleep 0.1; done
MOCK
    chmod +x "$WORK/bin/docker"
    local started=$SECONDS
    run nik zapisz
    [ "$status" -eq 137 ]; ((SECONDS-started < 7))
}
@test 'failed audit timestamp stops before Docker and log text cannot forge rows' {
    cat > "$WORK/bin/date" <<'MOCK'
#!/usr/bin/env bash
exit 9
MOCK
    chmod +x "$WORK/bin/date"
    run nik zapisz; [ "$status" -ne 0 ]; [ ! -e "$MOCK_CALLS" ]
    rm "$WORK/bin/date"
    run bash -c 'source "$1/lib/helpers.sh"; NIK_LOG=$2; NIK_TIMEOUT=1; nik_log START $'"'"'first\nforged\tfield\r'"'"'' _ "$ROOT" "$WORK/escaped.log"
    [ "$status" -eq 0 ]; [ "$(wc -l < "$WORK/escaped.log")" -eq 1 ]
}
@test 'summon default remains one and explicit six emits six commands' {
    run nik przywolaj g1 krowa --podglad; [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'run summon minecraft:cow')" -eq 1 ]
    run nik przywolaj g1 krowa 6 --podglad; [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'run summon minecraft:cow')" -eq 6 ]; [ ! -e "$MOCK_CALLS" ]
}
@test 'invalid summon counts including literal x cause no game operation' {
    for count in x 0 65 -1 1.5 999999999999999999999 '6 run kill @a'; do
        run nik przywolaj g1 krowa "$count"; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    done
}
@test 'summon count accepts leading zeros and does not bypass boss confirmation' {
    run nik przywolaj g1 cow 006 --podglad; [ "$status" -eq 0 ]; [ "$(printf '%s\n' "$output" | grep -c 'run summon minecraft:cow')" -eq 6 ]
    run nik przywolaj g1 wither 2; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    run nik przywolaj g1 wither 2 --potwierdz; [ "$status" -eq 0 ]; [ "$(grep -c 'run summon minecraft:wither' "$MOCK_CALLS")" -eq 2 ]
}
@test 'summon sequence stops immediately when game rejects the command' {
    export MOCK_MODE=semantic
    run nik przywolaj g1 krowa 6; [ "$status" -ne 0 ]; [ "$(grep -c '^exec ' "$MOCK_CALLS")" -eq 1 ]
}
@test 'summon list remains argument checked and count completion is available' {
    run nik przywolaj co 6; [ "$status" -eq 2 ]; [ ! -e "$MOCK_CALLS" ]
    run nik __complete przywolaj 3 6; [ "$status" -eq 0 ]; [[ $output == *'64'* ]]
}

@test 'truncated inventory and ender are read in smaller fields without writes' {
  export MOCK_MODE=inventory_truncated
  for command in plecak ender; do
    run nik "$command" g1
    [ "$status" -eq 0 ]; [[ $output == *'diamentowy_miecz'* && $output == *'ostrosc: 5'* ]]
  done
  ! grep '^exec ' "$MOCK_CALLS" | grep -v 'rcon-cli data get entity PlayerOne '
}
@test 'truncated held item reads scalar damage and never repairs an undamaged item' {
  export MOCK_MODE=inventory_truncated
  run nik napraw g1
  [ "$status" -eq 0 ]; [[ $output == *'nie ma zapisanych uszkodzeń'* ]]
  ! grep -q 'item modify' "$MOCK_CALLS"
}
