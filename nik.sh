#!/bin/bash

# ==================================================
# Naczelny Inspektorat Kreeperowy (NIK)
# RCON CLI
# ==================================================
#
# UWAGA: Ten skrypt trzeba SOURCE'OWAĆ, nie uruchamiać:
#   source nik.sh
# Funkcje, aliasy i bash completion działają tylko
# w bieżącej sesji shella po source'owaniu.
# ==================================================

MC_CONTAINER="${MC_CONTAINER:-minecraft}"
MC_LOG="${MC_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/nik/nik.log}"

# Ostrzeżenie jeśli ktoś uruchamia skrypt zamiast source'ować
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "UWAGA: Ten skrypt trzeba source'ować, nie uruchamiać bezpośrednio!"
    echo "Użyj: source ${BASH_SOURCE[0]}"
    exit 1
fi


# ==================================================
# KOLORY
# ==================================================

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"


# ==================================================
# SPRAWDZANIE SERWERA
# ==================================================

mc_check() {

    if ! docker ps --format '{{.Names}}' | grep -q "^${MC_CONTAINER}$"; then
        echo -e "${RED}Minecraft nie działa!${NC}"
        return 1
    fi
}


# ==================================================
# LOGOWANIE
# ==================================================

mc_log() {

    local funkcja="$1"
    shift

    mkdir -p -- "$(dirname -- "$MC_LOG")" || return 1

    printf "%s | %s | %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$funkcja" \
        "$*" \
        >> "$MC_LOG"
}


# ==================================================
# ROTACJA LOGÓW (max 30 dni)
# ==================================================
#
# Usuwa z pliku logu wpisy starsze niż MC_LOG_DNI dni.
# Wywoływana automatycznie raz przy każdym source'owaniu
# skryptu - przy sourcowaniu w .bashrc to wystarczająco
# częsty rytm, żeby log nigdy nie urósł w nieskończoność.

MC_LOG_DNI="${MC_LOG_DNI:-30}"

mc_log_rotacja() {

    [[ -f "$MC_LOG" ]] || return 0

    local cutoff

    # GNU date (Linux); fallback na BSD date (macOS) na wszelki wypadek
    cutoff=$(date -d "-${MC_LOG_DNI} days" '+%Y-%m-%d' 2>/dev/null) \
        || cutoff=$(date -v-"${MC_LOG_DNI}"d '+%Y-%m-%d' 2>/dev/null)

    [[ -z "$cutoff" ]] && return 0

    local tmp
    tmp=$(mktemp) || return 0

    awk -v cutoff="$cutoff" '{ if (substr($1,1,10) >= cutoff) print }' "$MC_LOG" > "$tmp" \
        && mv "$tmp" "$MC_LOG" \
        || rm -f "$tmp"
}


# ==================================================
# FUNKCJA POMOCNICZA RCON
# ==================================================
#
# Wysyła pojedynczą komendę do serwera przez rcon-cli
# i loguje ją. Wywołująca funkcja powinna wcześniej
# sama zawołać mc_check.
#
# Użycie: rcon "time set day"

rcon() {

    local cmd="$1"

    mc_log "rcon" "$cmd"

    docker exec "$MC_CONTAINER" rcon-cli "$cmd"
}


# ==================================================
# GRACZE
# ==================================================

# Prywatne ustawienia są ładowane z pliku wykluczonego z Gita.
# Skopiuj nik.local.example.sh do nik.local.sh i uzupełnij lokalnie.
declare -a MC_GRACZE=()
declare -A MC_GRACZE_SKROTY=()
declare -A MC_GRACZE_NICKI=()
MC_DOM_X="${MC_DOM_X:-}"
MC_DOM_Y="${MC_DOM_Y:-}"
MC_DOM_Z="${MC_DOM_Z:-}"
MC_ZAMEK_X="${MC_ZAMEK_X:-}"
MC_ZAMEK_Y="${MC_ZAMEK_Y:-}"
MC_ZAMEK_Z="${MC_ZAMEK_Z:-}"

_mc_katalog=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$_mc_katalog/nik.local.sh" ]]; then
    source "$_mc_katalog/nik.local.sh"
fi
unset _mc_katalog

gracz_nick() {
    local wejscie="${1,,}" gracz nick
    [[ -n "$wejscie" ]] || return 1
    for gracz in "${MC_GRACZE[@]}"; do
        if [[ "$wejscie" == "${gracz,,}" || "$wejscie" == "${MC_GRACZE_SKROTY[$gracz]:-}" ]]; then
            nick="${MC_GRACZE_NICKI[$gracz]:-}"
            [[ "$nick" =~ ^\.?[a-zA-Z0-9_]{1,16}$ ]] || return 1
            printf '%s\n' "$nick"
            return 0
        fi
    done
    return 1
}


gracz_lista() {

    echo "
Dostępni gracze:
"

    local g
    for g in "${MC_GRACZE[@]}"; do
        printf "  %s  (skrót: %s)\n" "$g" "${MC_GRACZE_SKROTY[$g]}"
    done

    echo ""
}


# ==================================================
# WALIDACJA ITEMÓW
# ==================================================
#
# Dopuszcza tylko znaki a-z 0-9 _ oraz opcjonalny
# prefiks namespace (np. minecraft:diamond).
# Blokuje wstrzykiwanie NBT/enchantów typu:
#   diamond_sword}{Enchantments:[...]}
#
# Zwraca 0 (sukces) jeśli item wygląda bezpiecznie.

item_waliduj() {

    local item="$1"

    if [[ -z "$item" ]]; then
        return 1
    fi

    # dozwolone: małe litery, cyfry, podkreślnik,
    # opcjonalny jeden dwukropek jako separator namespace
    if [[ ! "$item" =~ ^([a-z0-9_]+:)?[a-z0-9_]+$ ]]; then
        return 1
    fi

    return 0
}


# ==================================================
# SŁOWNIK PRZEDMIOTÓW (PL -> ID Minecraft)
# ==================================================
#
# Pełna lista wszystkich przedmiotów dostępnych w komendzie /give
# (Minecraft 1.21.4, 1384 pozycje), wygenerowana z oficjalnych plików
# językowych gry (en_us.json / pl_pl.json) i realnej listy ID itemów.
# Klucze bez polskich znaków diakrytycznych, małe litery,
# podkreślniki zamiast spacji (ułatwia wpisywanie i wyszukiwanie).
# Kolizje nazw (kilka itemów o tej samej polskiej nazwie) rozwiązane
# przez dopisanie angielskiego ID jako sufiksu klucza.

declare -A PRZEDMIOTY=(

    [akacjowa_furtka]="acacia_fence_gate"
    [akacjowa_klapa]="acacia_trapdoor"
    [akacjowa_lodka]="acacia_boat"
    [akacjowa_lodka_ze_skrzynia]="acacia_chest_boat"
    [akacjowa_plyta]="acacia_slab"
    [akacjowa_plytka_naciskowa]="acacia_pressure_plate"
    [akacjowa_podwieszana_tabliczka]="acacia_hanging_sign"
    [akacjowa_tabliczka]="acacia_sign"
    [akacjowe_deski]="acacia_planks"
    [akacjowe_drewno]="acacia_wood"
    [akacjowe_drzwi]="acacia_door"
    [akacjowe_liscie]="acacia_leaves"
    [akacjowe_schody]="acacia_stairs"
    [akacjowy_pien]="acacia_log"
    [akacjowy_plot]="acacia_fence"
    [akacjowy_przycisk]="acacia_button"
    [andezyt]="andesite"
    [andezytowa_plyta]="andesite_slab"
    [andezytowe_schody]="andesite_stairs"
    [andezytowy_murek]="andesite_wall"
    [arbuz]="melon"
    [azalia]="azalea"
    [bambus]="bamboo"
    [bambusowa_furtka]="bamboo_fence_gate"
    [bambusowa_klapa]="bamboo_trapdoor"
    [bambusowa_mozaika]="bamboo_mosaic"
    [bambusowa_mozaikowa_plyta]="bamboo_mosaic_slab"
    [bambusowa_plyta]="bamboo_slab"
    [bambusowa_plytka_naciskowa]="bamboo_pressure_plate"
    [bambusowa_podwieszana_tabliczka]="bamboo_hanging_sign"
    [bambusowa_tabliczka]="bamboo_sign"
    [bambusowa_tratwa]="bamboo_raft"
    [bambusowa_tratwa_ze_skrzynia]="bamboo_chest_raft"
    [bambusowe_deski]="bamboo_planks"
    [bambusowe_drzwi]="bamboo_door"
    [bambusowe_mozaikowe_schody]="bamboo_mosaic_stairs"
    [bambusowe_schody]="bamboo_stairs"
    [bambusowy_plot]="bamboo_fence"
    [bambusowy_przycisk]="bamboo_button"
    [bariera]="barrier"
    [barszcz_czerwony]="beetroot_soup"
    [bazalt]="basalt"
    [beczka]="barrel"
    [bez]="lilac"
    [biala_glazurowana_terakota]="white_glazed_terracotta"
    [biala_sakwa]="white_bundle"
    [biala_shulkerowa_skrzynia]="white_shulker_box"
    [biala_swieca]="white_candle"
    [biala_szyba]="white_stained_glass_pane"
    [biala_terakota]="white_terracotta"
    [biala_welna]="white_wool"
    [biale_lozko]="white_bed"
    [biale_szklo]="white_stained_glass"
    [bialy_barwnik]="white_dye"
    [bialy_beton]="white_concrete"
    [bialy_cement]="white_concrete_powder"
    [bialy_dywan]="white_carpet"
    [bialy_sztandar]="white_banner"
    [bialy_tulipan]="white_tulip"
    [biblioteczka]="bookshelf"
    [bielica]="podzol"
    [bladodebowa_furtka]="pale_oak_fence_gate"
    [bladodebowa_klapa]="pale_oak_trapdoor"
    [bladodebowa_lodka]="pale_oak_boat"
    [bladodebowa_lodka_ze_skrzynia]="pale_oak_chest_boat"
    [bladodebowa_plyta]="pale_oak_slab"
    [bladodebowa_plytka_naciskowa]="pale_oak_pressure_plate"
    [bladodebowa_podwieszana_tabliczka]="pale_oak_hanging_sign"
    [bladodebowa_tabliczka]="pale_oak_sign"
    [bladodebowe_deski]="pale_oak_planks"
    [bladodebowe_drzwi]="pale_oak_door"
    [bladodebowe_schody]="pale_oak_stairs"
    [bladodebowy_pien]="pale_oak_log"
    [bladodebowy_plot]="pale_oak_fence"
    [bladodebowy_przycisk]="pale_oak_button"
    [blekitna_glazurowana_terakota]="cyan_glazed_terracotta"
    [blekitna_sakwa]="cyan_bundle"
    [blekitna_shulkerowa_skrzynia]="cyan_shulker_box"
    [blekitna_swieca]="cyan_candle"
    [blekitna_szyba]="cyan_stained_glass_pane"
    [blekitna_terakota]="cyan_terracotta"
    [blekitna_welna]="cyan_wool"
    [blekitne_lozko]="cyan_bed"
    [blekitne_szklo]="cyan_stained_glass"
    [blekitny_barwnik]="cyan_dye"
    [blekitny_beton]="cyan_concrete"
    [blekitny_cement]="cyan_concrete_powder"
    [blekitny_dywan]="cyan_carpet"
    [blekitny_sztandar]="cyan_banner"
    [blok_ametystu]="amethyst_block"
    [blok_bambusu]="bamboo_block"
    [blok_bladego_mchu]="pale_moss_block"
    [blok_borowika]="brown_mushroom_block"
    [blok_diamentu]="diamond_block"
    [blok_dzwiekowy]="note_block"
    [blok_konstrukcyjny]="jigsaw"
    [blok_koralowca_babelkowatego]="bubble_coral_block"
    [blok_koralowca_mozgowatego]="brain_coral_block"
    [blok_koralowca_ognistego]="fire_coral_block"
    [blok_koralowca_rogatego]="horn_coral_block"
    [blok_koralowca_rurkowatego]="tube_coral_block"
    [blok_kosci]="bone_block"
    [blok_kwarcu]="quartz_block"
    [blok_lazurytu]="lapis_block"
    [blok_magmy]="magma_block"
    [blok_martwego_koralowca_babelkowatego]="dead_bubble_coral_block"
    [blok_martwego_koralowca_mozgowatego]="dead_brain_coral_block"
    [blok_martwego_koralowca_ognistego]="dead_fire_coral_block"
    [blok_martwego_koralowca_rogatego]="dead_horn_coral_block"
    [blok_martwego_koralowca_rurkowatego]="dead_tube_coral_block"
    [blok_mchu]="moss_block"
    [blok_miedzi]="copper_block"
    [blok_miodu]="honey_block"
    [blok_muchomora]="red_mushroom_block"
    [blok_nacieku]="dripstone_block"
    [blok_netherowych_brodawek]="nether_wart_block"
    [blok_netherytu]="netherite_block"
    [blok_ociosanego_bambusu]="stripped_bamboo_block"
    [blok_plastra_miodu]="honeycomb_block"
    [blok_polecen]="command_block"
    [blok_purpuru]="purpur_block"
    [blok_redstone]="redstone_block"
    [blok_rudy_miedzi]="raw_copper_block"
    [blok_rudy_zelaza]="raw_iron_block"
    [blok_sniegu]="snow_block"
    [blok_spaczonych_brodawek]="warped_wart_block"
    [blok_struktur]="structure_block"
    [blok_surowego_zlota]="raw_gold_block"
    [blok_suszonych_wodorostow]="dried_kelp_block"
    [blok_szlamu]="slime_block"
    [blok_szmaragdu]="emerald_block"
    [blok_trawy]="grass_block"
    [blok_wegla]="coal_block"
    [blok_zelaza]="iron_block"
    [blok_zlota]="gold_block"
    [blok_zywicy]="resin_block"
    [blona_fantoma]="phantom_membrane"
    [blotna_ceglana_plyta]="mud_brick_slab"
    [blotne_ceglane_schody]="mud_brick_stairs"
    [blotne_cegly]="mud_bricks"
    [blotny_ceglany_murek]="mud_brick_wall"
    [bloto]="mud"
    [borowik]="brown_mushroom"
    [brazowa_glazurowana_terakota]="brown_glazed_terracotta"
    [brazowa_sakwa]="brown_bundle"
    [brazowa_shulkerowa_skrzynia]="brown_shulker_box"
    [brazowa_swieca]="brown_candle"
    [brazowa_szyba]="brown_stained_glass_pane"
    [brazowa_terakota]="brown_terracotta"
    [brazowa_welna]="brown_wool"
    [brazowe_lozko]="brown_bed"
    [brazowe_szklo]="brown_stained_glass"
    [brazowy_barwnik]="brown_dye"
    [brazowy_beton]="brown_concrete"
    [brazowy_cement]="brown_concrete_powder"
    [brazowy_dywan]="brown_carpet"
    [brazowy_sztandar]="brown_banner"
    [bruk]="cobblestone"
    [brukowa_plyta]="cobblestone_slab"
    [brukowe_schody]="cobblestone_stairs"
    [brukowy_murek]="cobblestone_wall"
    [brylka_zelaza]="iron_nugget"
    [brylka_zlota]="gold_nugget"
    [brzozowa_furtka]="birch_fence_gate"
    [brzozowa_klapa]="birch_trapdoor"
    [brzozowa_lodka]="birch_boat"
    [brzozowa_lodka_ze_skrzynia]="birch_chest_boat"
    [brzozowa_plyta]="birch_slab"
    [brzozowa_plytka_naciskowa]="birch_pressure_plate"
    [brzozowa_podwieszana_tabliczka]="birch_hanging_sign"
    [brzozowa_tabliczka]="birch_sign"
    [brzozowe_deski]="birch_planks"
    [brzozowe_drewno]="birch_wood"
    [brzozowe_drzwi]="birch_door"
    [brzozowe_liscie]="birch_leaves"
    [brzozowe_schody]="birch_stairs"
    [brzozowy_pien]="birch_log"
    [brzozowy_plot]="birch_fence"
    [brzozowy_przycisk]="birch_button"
    [burak]="beetroot"
    [butelka_miodu]="honey_bottle"
    [buzdygan]="mace"
    [cegla]="brick"
    [ceglana_plyta]="brick_slab"
    [ceglane_schody]="brick_stairs"
    [ceglany_murek]="brick_wall"
    [cegly]="bricks"
    [chaber]="cornflower"
    [chleb]="bread"
    [ciastko]="cookie"
    [ciasto]="cake"
    [ciemna_pryzmarynowa_plyta]="dark_prismarine_slab"
    [ciemne_pryzmarynowe_schody]="dark_prismarine_stairs"
    [ciemnodebowa_furtka]="dark_oak_fence_gate"
    [ciemnodebowa_klapa]="dark_oak_trapdoor"
    [ciemnodebowa_lodka]="dark_oak_boat"
    [ciemnodebowa_lodka_ze_skrzynia]="dark_oak_chest_boat"
    [ciemnodebowa_plyta]="dark_oak_slab"
    [ciemnodebowa_plytka_naciskowa]="dark_oak_pressure_plate"
    [ciemnodebowa_podwieszana_tabliczka]="dark_oak_hanging_sign"
    [ciemnodebowa_tabliczka]="dark_oak_sign"
    [ciemnodebowe_deski]="dark_oak_planks"
    [ciemnodebowe_drewno]="dark_oak_wood"
    [ciemnodebowe_drzwi]="dark_oak_door"
    [ciemnodebowe_liscie]="dark_oak_leaves"
    [ciemnodebowe_schody]="dark_oak_stairs"
    [ciemnodebowy_pien]="dark_oak_log"
    [ciemnodebowy_plot]="dark_oak_fence"
    [ciemnodebowy_przycisk]="dark_oak_button"
    [ciemny_pryzmaryn]="dark_prismarine"
    [ciezka_wagowa_plytka_naciskowa]="heavy_weighted_pressure_plate"
    [ciezki_rdzen]="heavy_core"
    [cukier]="sugar"
    [czarna_glazurowana_terakota]="black_glazed_terracotta"
    [czarna_sakwa]="black_bundle"
    [czarna_shulkerowa_skrzynia]="black_shulker_box"
    [czarna_swieca]="black_candle"
    [czarna_szyba]="black_stained_glass_pane"
    [czarna_terakota]="black_terracotta"
    [czarna_welna]="black_wool"
    [czarne_lozko]="black_bed"
    [czarne_szklo]="black_stained_glass"
    [czarny_barwnik]="black_dye"
    [czarny_beton]="black_concrete"
    [czarny_cement]="black_concrete_powder"
    [czarny_dywan]="black_carpet"
    [czarny_sztandar]="black_banner"
    [czaszka_szkieleta]="skeleton_skull"
    [czaszka_witherowego_szkieleta]="wither_skeleton_skull"
    [czernit]="blackstone"
    [czernitowa_plyta]="blackstone_slab"
    [czernitowe_schody]="blackstone_stairs"
    [czernitowy_murek]="blackstone_wall"
    [czerwona_glazurowana_terakota]="red_glazed_terracotta"
    [czerwona_netherowa_ceglana_plyta]="red_nether_brick_slab"
    [czerwona_piaskowcowa_plyta]="red_sandstone_slab"
    [czerwona_sakwa]="red_bundle"
    [czerwona_shulkerowa_skrzynia]="red_shulker_box"
    [czerwona_swieca]="red_candle"
    [czerwona_szyba]="red_stained_glass_pane"
    [czerwona_terakota]="red_terracotta"
    [czerwona_welna]="red_wool"
    [czerwone_lozko]="red_bed"
    [czerwone_netherowe_ceglane_schody]="red_nether_brick_stairs"
    [czerwone_netherowe_cegly]="red_nether_bricks"
    [czerwone_piaskowcowe_schody]="red_sandstone_stairs"
    [czerwone_szklo]="red_stained_glass"
    [czerwony_barwnik]="red_dye"
    [czerwony_beton]="red_concrete"
    [czerwony_cement]="red_concrete_powder"
    [czerwony_dywan]="red_carpet"
    [czerwony_netherowy_ceglany_murek]="red_nether_brick_wall"
    [czerwony_piasek]="red_sand"
    [czerwony_piaskowcowy_murek]="red_sandstone_wall"
    [czerwony_piaskowiec]="red_sandstone"
    [czerwony_sztandar]="red_banner"
    [czerwony_tulipan]="red_tulip"
    [czosnek]="allium"
    [debowa_furtka]="oak_fence_gate"
    [debowa_klapa]="oak_trapdoor"
    [debowa_lodka]="oak_boat"
    [debowa_lodka_ze_skrzynia]="oak_chest_boat"
    [debowa_plyta]="oak_slab"
    [debowa_plytka_naciskowa]="oak_pressure_plate"
    [debowa_podwieszana_tabliczka]="oak_hanging_sign"
    [debowa_tabliczka]="oak_sign"
    [debowe_deski]="oak_planks"
    [debowe_drewno]="oak_wood"
    [debowe_drzwi]="oak_door"
    [debowe_liscie]="oak_leaves"
    [debowe_schody]="oak_stairs"
    [debowy_pien]="oak_log"
    [debowy_plot]="oak_fence"
    [debowy_przycisk]="oak_button"
    [dekorowany_garniec]="decorated_pot"
    [detektor]="observer"
    [detektor_swiatla_dziennego]="daylight_detector"
    [diament]="diamond"
    [diamentowa_lopata]="diamond_shovel"
    [diamentowa_motyka]="diamond_hoe"
    [diamentowa_siekiera]="diamond_axe"
    [diamentowa_zbroja_konska]="diamond_horse_armor"
    [diamentowe_buty]="diamond_boots"
    [diamentowe_nogawice]="diamond_leggings"
    [diamentowy_helm]="diamond_helmet"
    [diamentowy_kilof]="diamond_pickaxe"
    [diamentowy_miecz]="diamond_sword"
    [diamentowy_napiersnik]="diamond_chestplate"
    [dioryt]="diorite"
    [diorytowa_plyta]="diorite_slab"
    [diorytowe_schody]="diorite_stairs"
    [diorytowy_murek]="diorite_wall"
    [doniczka]="flower_pot"
    [dozownik]="dispenser"
    [drabina]="ladder"
    [drewniana_lopata]="wooden_shovel"
    [drewniana_motyka]="wooden_hoe"
    [drewniana_siekiera]="wooden_axe"
    [drewniany_kilof]="wooden_pickaxe"
    [drewniany_miecz]="wooden_sword"
    [drewno_bladego_debu]="pale_oak_wood"
    [duza_paproc]="large_fern"
    [duzy_zarodek_ametystu]="large_amethyst_bud"
    [dynia]="pumpkin"
    [dzbanecznik]="pitcher_plant"
    [dzwignia]="lever"
    [dzwon]="bell"
    [elytry]="elytra"
    [enderperla]="ender_pearl"
    [endowa_kamienna_ceglana_plyta]="end_stone_brick_slab"
    [endowe_kamienne_ceglane_schody]="end_stone_brick_stairs"
    [endowe_kamienne_cegly]="end_stone_bricks"
    [endowy_kamienny_ceglany_murek]="end_stone_brick_wall"
    [endowy_slupek]="end_rod"
    [fajerwerk]="firework_rocket"
    [fioletowa_glazurowana_terakota]="purple_glazed_terracotta"
    [fioletowa_sakwa]="purple_bundle"
    [fioletowa_shulkerowa_skrzynia]="purple_shulker_box"
    [fioletowa_swieca]="purple_candle"
    [fioletowa_szyba]="purple_stained_glass_pane"
    [fioletowa_terakota]="purple_terracotta"
    [fioletowa_welna]="purple_wool"
    [fioletowe_lozko]="purple_bed"
    [fioletowe_szklo]="purple_stained_glass"
    [fioletowy_barwnik]="purple_dye"
    [fioletowy_beton]="purple_concrete"
    [fioletowy_cement]="purple_concrete_powder"
    [fioletowy_dywan]="purple_carpet"
    [fioletowy_sztandar]="purple_banner"
    [fragment_plyty]="disc_fragment_5"
    [gabka]="sponge"
    [gladka_czerwona_piaskowcowa_plyta]="smooth_red_sandstone_slab"
    [gladka_kamienna_plyta]="smooth_stone_slab"
    [gladka_kwarcowa_plyta]="smooth_quartz_slab"
    [gladka_piaskowcowa_plyta]="smooth_sandstone_slab"
    [gladki_bazalt]="smooth_basalt"
    [gladki_blok_kwarcu]="smooth_quartz"
    [gladki_czerwony_piaskowiec]="smooth_red_sandstone"
    [gladki_kamien]="smooth_stone"
    [gladki_piaskowiec]="smooth_sandstone"
    [gladkie_czerwone_piaskowcowe_schody]="smooth_red_sandstone_stairs"
    [gladkie_kwarcowe_schody]="smooth_quartz_stairs"
    [gladkie_piaskowcowe_schody]="smooth_sandstone_stairs"
    [gleba_dusz]="soul_soil"
    [glina]="clay"
    [glowa_creepera]="creeper_head"
    [glowa_gracza]="player_head"
    [glowa_piglina]="piglin_head"
    [glowa_smoka]="dragon_head"
    [glowa_zombie]="zombie_head"
    [gniazdo_pszczol]="bee_nest"
    [granit]="granite"
    [granitowa_plyta]="granite_slab"
    [granitowe_schody]="granite_stairs"
    [granitowy_murek]="granite_wall"
    [gruda_zywicy]="resin_clump"
    [grzybnia]="mycelium"
    [gwiazdka_pirotechniczna]="firework_star"
    [houstonia_blekitna]="azure_bluet"
    [iskrzyluda]="sea_pickle"
    [jablko]="apple"
    [jajko]="egg"
    [jajo_niuchacza]="sniffer_egg"
    [jajo_przyzywajace_aksolotla]="axolotl_spawn_egg"
    [jajo_przyzywajace_bagniaka]="bogged_spawn_egg"
    [jajo_przyzywajace_creepera]="creeper_spawn_egg"
    [jajo_przyzywajace_delfina]="dolphin_spawn_egg"
    [jajo_przyzywajace_dewastatora]="ravager_spawn_egg"
    [jajo_przyzywajace_dorsza]="cod_spawn_egg"
    [jajo_przyzywajace_dreczyciela]="vex_spawn_egg"
    [jajo_przyzywajace_endermana]="enderman_spawn_egg"
    [jajo_przyzywajace_endermita]="endermite_spawn_egg"
    [jajo_przyzywajace_fantoma]="phantom_spawn_egg"
    [jajo_przyzywajace_ghasta]="ghast_spawn_egg"
    [jajo_przyzywajace_hoglina]="hoglin_spawn_egg"
    [jajo_przyzywajace_kalamarnice]="squid_spawn_egg"
    [jajo_przyzywajace_kijanke]="tadpole_spawn_egg"
    [jajo_przyzywajace_konia]="horse_spawn_egg"
    [jajo_przyzywajace_konia_szkieleta]="skeleton_horse_spawn_egg"
    [jajo_przyzywajace_konia_zombie]="zombie_horse_spawn_egg"
    [jajo_przyzywajace_kostke_magmy]="magma_cube_spawn_egg"
    [jajo_przyzywajace_kota]="cat_spawn_egg"
    [jajo_przyzywajace_koze]="goat_spawn_egg"
    [jajo_przyzywajace_krolika]="rabbit_spawn_egg"
    [jajo_przyzywajace_krowe]="cow_spawn_egg"
    [jajo_przyzywajace_kure]="chicken_spawn_egg"
    [jajo_przyzywajace_lame]="llama_spawn_egg"
    [jajo_przyzywajace_lame_handlarza]="trader_llama_spawn_egg"
    [jajo_przyzywajace_lisa]="fox_spawn_egg"
    [jajo_przyzywajace_lososia]="salmon_spawn_egg"
    [jajo_przyzywajace_magmolaza]="strider_spawn_egg"
    [jajo_przyzywajace_mooshrooma]="mooshroom_spawn_egg"
    [jajo_przyzywajace_mula]="mule_spawn_egg"
    [jajo_przyzywajace_nadzorce]="warden_spawn_egg"
    [jajo_przyzywajace_niedzwiedzia_polarnego]="polar_bear_spawn_egg"
    [jajo_przyzywajace_nietoperza]="bat_spawn_egg"
    [jajo_przyzywajace_niuchacza]="sniffer_spawn_egg"
    [jajo_przyzywajace_obronce]="vindicator_spawn_egg"
    [jajo_przyzywajace_ocelota]="ocelot_spawn_egg"
    [jajo_przyzywajace_osadnika]="villager_spawn_egg"
    [jajo_przyzywajace_osadnika_zombie]="zombie_villager_spawn_egg"
    [jajo_przyzywajace_osla]="donkey_spawn_egg"
    [jajo_przyzywajace_otuszka]="allay_spawn_egg"
    [jajo_przyzywajace_owce]="sheep_spawn_egg"
    [jajo_przyzywajace_pajaka]="spider_spawn_egg"
    [jajo_przyzywajace_pajaka_jaskiniowego]="cave_spider_spawn_egg"
    [jajo_przyzywajace_pancernika]="armadillo_spawn_egg"
    [jajo_przyzywajace_pande]="panda_spawn_egg"
    [jajo_przyzywajace_papuge]="parrot_spawn_egg"
    [jajo_przyzywajace_piglina]="piglin_spawn_egg"
    [jajo_przyzywajace_piglina_okrutnika]="piglin_brute_spawn_egg"
    [jajo_przyzywajace_plomyka]="blaze_spawn_egg"
    [jajo_przyzywajace_posucha]="husk_spawn_egg"
    [jajo_przyzywajace_prastraznika]="elder_guardian_spawn_egg"
    [jajo_przyzywajace_przywolywacza]="evoker_spawn_egg"
    [jajo_przyzywajace_pszczole]="bee_spawn_egg"
    [jajo_przyzywajace_rozbojnika]="pillager_spawn_egg"
    [jajo_przyzywajace_rozdymke]="pufferfish_spawn_egg"
    [jajo_przyzywajace_rybe_tropikalna]="tropical_fish_spawn_egg"
    [jajo_przyzywajace_rybika_cukrowego]="silverfish_spawn_egg"
    [jajo_przyzywajace_shulkera]="shulker_spawn_egg"
    [jajo_przyzywajace_smoka_endu]="ender_dragon_spawn_egg"
    [jajo_przyzywajace_snieznego_golema]="snow_golem_spawn_egg"
    [jajo_przyzywajace_straznika]="guardian_spawn_egg"
    [jajo_przyzywajace_swiecaca_kalamarnice]="glow_squid_spawn_egg"
    [jajo_przyzywajace_swinie]="pig_spawn_egg"
    [jajo_przyzywajace_szkieleta]="skeleton_spawn_egg"
    [jajo_przyzywajace_szlama]="slime_spawn_egg"
    [jajo_przyzywajace_trzeszcza]="creaking_spawn_egg"
    [jajo_przyzywajace_tulacza]="stray_spawn_egg"
    [jajo_przyzywajace_utopca]="drowned_spawn_egg"
    [jajo_przyzywajace_wedrownego_handlarza]="wandering_trader_spawn_egg"
    [jajo_przyzywajace_wichrzyka]="breeze_spawn_egg"
    [jajo_przyzywajace_wiedzme]="witch_spawn_egg"
    [jajo_przyzywajace_wielblada]="camel_spawn_egg"
    [jajo_przyzywajace_wilka]="wolf_spawn_egg"
    [jajo_przyzywajace_withera]="wither_spawn_egg"
    [jajo_przyzywajace_witherowego_szkieleta]="wither_skeleton_spawn_egg"
    [jajo_przyzywajace_zabe]="frog_spawn_egg"
    [jajo_przyzywajace_zelaznego_golema]="iron_golem_spawn_egg"
    [jajo_przyzywajace_zoglina]="zoglin_spawn_egg"
    [jajo_przyzywajace_zolwia]="turtle_spawn_egg"
    [jajo_przyzywajace_zombie]="zombie_spawn_egg"
    [jajo_przyzywajace_zzombifikowanego_piglina]="zombified_piglin_spawn_egg"
    [jasnoglaz]="glowstone"
    [jasnoniebieska_glazurowana_terakota]="light_blue_glazed_terracotta"
    [jasnoniebieska_sakwa]="light_blue_bundle"
    [jasnoniebieska_shulkerowa_skrzynia]="light_blue_shulker_box"
    [jasnoniebieska_swieca]="light_blue_candle"
    [jasnoniebieska_szyba]="light_blue_stained_glass_pane"
    [jasnoniebieska_terakota]="light_blue_terracotta"
    [jasnoniebieska_welna]="light_blue_wool"
    [jasnoniebieski_barwnik]="light_blue_dye"
    [jasnoniebieski_beton]="light_blue_concrete"
    [jasnoniebieski_cement]="light_blue_concrete_powder"
    [jasnoniebieski_dywan]="light_blue_carpet"
    [jasnoniebieski_sztandar]="light_blue_banner"
    [jasnoniebieskie_lozko]="light_blue_bed"
    [jasnoniebieskie_szklo]="light_blue_stained_glass"
    [jasnopyl]="glowstone_dust"
    [jasnoszara_glazurowana_terakota]="light_gray_glazed_terracotta"
    [jasnoszara_sakwa]="light_gray_bundle"
    [jasnoszara_shulkerowa_skrzynia]="light_gray_shulker_box"
    [jasnoszara_swieca]="light_gray_candle"
    [jasnoszara_szyba]="light_gray_stained_glass_pane"
    [jasnoszara_terakota]="light_gray_terracotta"
    [jasnoszara_welna]="light_gray_wool"
    [jasnoszare_lozko]="light_gray_bed"
    [jasnoszare_szklo]="light_gray_stained_glass"
    [jasnoszary_barwnik]="light_gray_dye"
    [jasnoszary_beton]="light_gray_concrete"
    [jasnoszary_cement]="light_gray_concrete_powder"
    [jasnoszary_dywan]="light_gray_carpet"
    [jasnoszary_sztandar]="light_gray_banner"
    [jasnozielona_glazurowana_terakota]="lime_glazed_terracotta"
    [jasnozielona_sakwa]="lime_bundle"
    [jasnozielona_shulkerowa_skrzynia]="lime_shulker_box"
    [jasnozielona_swieca]="lime_candle"
    [jasnozielona_szyba]="lime_stained_glass_pane"
    [jasnozielona_terakota]="lime_terracotta"
    [jasnozielona_welna]="lime_wool"
    [jasnozielone_lozko]="lime_bed"
    [jasnozielone_szklo]="lime_stained_glass"
    [jasnozielony_barwnik]="lime_dye"
    [jasnozielony_beton]="lime_concrete"
    [jasnozielony_cement]="lime_concrete_powder"
    [jasnozielony_dywan]="lime_carpet"
    [jasnozielony_sztandar]="lime_banner"
    [kaktus]="cactus"
    [kalcyt]="calcite"
    [kamien]="stone"
    [kamien_endu]="end_stone"
    [kamien_szlifierski]="grindstone"
    [kamienna_ceglana_plyta]="stone_brick_slab"
    [kamienna_lopata]="stone_shovel"
    [kamienna_motyka]="stone_hoe"
    [kamienna_plyta]="stone_slab"
    [kamienna_plytka_naciskowa]="stone_pressure_plate"
    [kamienna_siekiera]="stone_axe"
    [kamienne_ceglane_schody]="stone_brick_stairs"
    [kamienne_cegly]="stone_bricks"
    [kamienne_schody]="stone_stairs"
    [kamienny_ceglany_murek]="stone_brick_wall"
    [kamienny_kilof]="stone_pickaxe"
    [kamienny_miecz]="stone_sword"
    [kamienny_przycisk]="stone_button"
    [karmazynowa_glazurowana_terakota]="magenta_glazed_terracotta"
    [karmazynowa_sakwa]="magenta_bundle"
    [karmazynowa_shulkerowa_skrzynia]="magenta_shulker_box"
    [karmazynowa_swieca]="magenta_candle"
    [karmazynowa_szyba]="magenta_stained_glass_pane"
    [karmazynowa_terakota]="magenta_terracotta"
    [karmazynowa_welna]="magenta_wool"
    [karmazynowe_lozko]="magenta_bed"
    [karmazynowe_szklo]="magenta_stained_glass"
    [karmazynowy_barwnik]="magenta_dye"
    [karmazynowy_beton]="magenta_concrete"
    [karmazynowy_cement]="magenta_concrete_powder"
    [karmazynowy_dywan]="magenta_carpet"
    [karmazynowy_sztandar]="magenta_banner"
    [kawalek_arbuza]="melon_slice"
    [kawalek_lsniacego_arbuza]="glistering_melon_slice"
    [kielkujacy_ametyst]="budding_amethyst"
    [klucz_proby]="trial_key"
    [kociol]="cauldron"
    [kolcze_buty]="chainmail_boots"
    [kolcze_nogawice]="chainmail_leggings"
    [kolczy_helm]="chainmail_helmet"
    [kolczy_napiersnik]="chainmail_chestplate"
    [komparator_redstone]="comparator"
    [kompas]="compass"
    [kompas_powrotny]="recovery_compass"
    [kompostownik]="composter"
    [konwalia]="lily_of_the_valley"
    [koralowiec_babelkowaty]="bubble_coral"
    [koralowiec_mozgowaty]="brain_coral"
    [koralowiec_ognisty]="fire_coral"
    [koralowiec_rogaty]="horn_coral"
    [koralowiec_rurkowaty]="tube_coral"
    [kosc]="bone"
    [kotwica_odrodzenia]="respawn_anchor"
    [kowadlo]="anvil"
    [kozi_rog]="goat_horn"
    [krolicza_lapka]="rabbit_foot"
    [krolicza_skora]="rabbit_hide"
    [krosno]="loom"
    [krysztal_endu]="end_crystal"
    [krysztaly_pryzmarynu]="prismarine_crystals"
    [krzemien]="flint"
    [krzesiwo]="flint_and_steel"
    [krzew_rozy]="rose_bush"
    [ksiazka]="book"
    [ksiazka_z_piorem]="writable_book"
    [ksiega_wiedzy]="knowledge_book"
    [kula_szlamu]="slime_ball"
    [kulka_gliny]="clay_ball"
    [kusza]="crossbow"
    [kwarcowa_plyta]="quartz_slab"
    [kwarcowe_cegly]="quartz_bricks"
    [kwarcowe_schody]="quartz_stairs"
    [kwarcowy_filar]="quartz_pillar"
    [kwiat_refrenusu]="chorus_flower"
    [kwitnaca_azalia]="flowering_azalea"
    [kwitnace_liscie_azalii]="flowering_azalea_leaves"
    [lampa_redstone]="redstone_lamp"
    [lancuch]="chain"
    [lancuchowy_blok_polecen]="chain_command_block"
    [latarenka]="lantern"
    [latarenka_dusz]="soul_lantern"
    [latarnia_dyniowa]="jack_o_lantern"
    [latarnia_morska]="sea_lantern"
    [lazuryt]="lapis_lazuli"
    [lej]="hopper"
    [lekka_wagowa_plytka_naciskowa]="light_weighted_pressure_plate"
    [lepki_tlok]="sticky_piston"
    [lilia_wodna]="lily_pad"
    [liscie_azalii]="azalea_leaves"
    [liscie_bladego_debu]="pale_oak_leaves"
    [lod]="ice"
    [lodyga_refrenusu]="chorus_plant"
    [luk]="bow"
    [luneta]="spyglass"
    [lupek]="deepslate"
    [lupkowa_brukowa_plyta]="cobbled_deepslate_slab"
    [lupkowa_ceglana_plyta]="deepslate_brick_slab"
    [lupkowa_kafelkowa_plyta]="deepslate_tile_slab"
    [lupkowe_brukowe_schody]="cobbled_deepslate_stairs"
    [lupkowe_ceglane_schody]="deepslate_brick_stairs"
    [lupkowe_cegly]="deepslate_bricks"
    [lupkowe_kafelki]="deepslate_tiles"
    [lupkowe_kafelkowe_schody]="deepslate_tile_stairs"
    [lupkowe_zloze_diamentu]="deepslate_diamond_ore"
    [lupkowe_zloze_lazurytu]="deepslate_lapis_ore"
    [lupkowe_zloze_miedzi]="deepslate_copper_ore"
    [lupkowe_zloze_redstone]="deepslate_redstone_ore"
    [lupkowe_zloze_szmaragdu]="deepslate_emerald_ore"
    [lupkowe_zloze_wegla]="deepslate_coal_ore"
    [lupkowe_zloze_zelaza]="deepslate_iron_ore"
    [lupkowe_zloze_zlota]="deepslate_gold_ore"
    [lupkowy_bruk]="cobbled_deepslate"
    [lupkowy_brukowy_murek]="cobbled_deepslate_wall"
    [lupkowy_ceglany_murek]="deepslate_brick_wall"
    [lupkowy_kafelkowy_murek]="deepslate_tile_wall"
    [lza_ghasta]="ghast_tear"
    [maczka_kostna]="bone_meal"
    [magiczna_latarnia]="beacon"
    [magmowy_krem]="magma_cream"
    [magnetyt]="lodestone"
    [mak]="poppy"
    [maly_spadkolisc]="small_dripleaf"
    [maly_zarodek_ametystu]="small_amethyst_bud"
    [mapa]="filled_map"
    [marchewka]="carrot"
    [marchewka_na_patyku]="carrot_on_a_stick"
    [margaretka]="oxeye_daisy"
    [martwy_koralowiec_babelkowy]="dead_bubble_coral"
    [martwy_koralowiec_mozgowaty]="dead_brain_coral"
    [martwy_koralowiec_ognisty]="dead_fire_coral"
    [martwy_koralowiec_rogaty]="dead_horn_coral"
    [martwy_koralowiec_rurkowaty]="dead_tube_coral"
    [martwy_wachlarz_koralowca_babelkowatego]="dead_bubble_coral_fan"
    [martwy_wachlarz_koralowca_mozgowatego]="dead_brain_coral_fan"
    [martwy_wachlarz_koralowca_ognistego]="dead_fire_coral_fan"
    [martwy_wachlarz_koralowca_rogatego]="dead_horn_coral_fan"
    [martwy_wachlarz_koralowca_rurkowatego]="dead_tube_coral_fan"
    [miedziana_klapa]="copper_trapdoor"
    [miedziana_krata]="copper_grate"
    [miedziana_lampa]="copper_bulb"
    [miedziane_drzwi]="copper_door"
    [mikstura]="potion"
    [mikstura_miotana]="splash_potion"
    [miska]="bowl"
    [mlecz]="dandelion"
    [mokra_gabka]="wet_sponge"
    [muchomor]="red_mushroom"
    [muszla_lodzika]="nautilus_shell"
    [namorzynowa_furtka]="mangrove_fence_gate"
    [namorzynowa_klapa]="mangrove_trapdoor"
    [namorzynowa_lodka]="mangrove_boat"
    [namorzynowa_lodka_ze_skrzynia]="mangrove_chest_boat"
    [namorzynowa_plyta]="mangrove_slab"
    [namorzynowa_plytka_naciskowa]="mangrove_pressure_plate"
    [namorzynowa_podwieszana_tabliczka]="mangrove_hanging_sign"
    [namorzynowa_tabliczka]="mangrove_sign"
    [namorzynowe_deski]="mangrove_planks"
    [namorzynowe_drewno]="mangrove_wood"
    [namorzynowe_drzwi]="mangrove_door"
    [namorzynowe_korzenie]="mangrove_roots"
    [namorzynowe_liscie]="mangrove_leaves"
    [namorzynowe_schody]="mangrove_stairs"
    [namorzynowy_pien]="mangrove_log"
    [namorzynowy_plot]="mangrove_fence"
    [namorzynowy_przycisk]="mangrove_button"
    [napedzany_wagonik]="furnace_minecart"
    [nasiona_arbuza]="melon_seeds"
    [nasiona_buraka]="beetroot_seeds"
    [nasiona_dyni]="pumpkin_seeds"
    [nasiona_ognistego_kwiatu]="torchflower_seeds"
    [nasiona_pszenicy]="wheat_seeds"
    [netherowa_brodawka]="nether_wart"
    [netherowa_cegla]="nether_brick"
    [netherowa_ceglana_plyta]="nether_brick_slab"
    [netherowa_gwiazda]="nether_star"
    [netherowe_ceglane_schody]="nether_brick_stairs"
    [netherowe_cegly]="nether_bricks"
    [netherowe_kielki]="nether_sprouts"
    [netherowe_zloze_zlota]="nether_gold_ore"
    [netherowy_ceglany_murek]="nether_brick_wall"
    [netherowy_ceglany_plot]="nether_brick_fence"
    [netherowy_kwarc]="quartz"
    [netherrack]="netherrack"
    [netherytowa_lopata]="netherite_shovel"
    [netherytowa_motyka]="netherite_hoe"
    [netherytowa_siekiera]="netherite_axe"
    [netherytowe_buty]="netherite_boots"
    [netherytowe_nogawice]="netherite_leggings"
    [netherytowy_helm]="netherite_helmet"
    [netherytowy_kilof]="netherite_pickaxe"
    [netherytowy_miecz]="netherite_sword"
    [netherytowy_napiersnik]="netherite_chestplate"
    [nic]="string"
    [niebieska_glazurowana_terakota]="blue_glazed_terracotta"
    [niebieska_orchidea]="blue_orchid"
    [niebieska_sakwa]="blue_bundle"
    [niebieska_shulkerowa_skrzynia]="blue_shulker_box"
    [niebieska_swieca]="blue_candle"
    [niebieska_szyba]="blue_stained_glass_pane"
    [niebieska_terakota]="blue_terracotta"
    [niebieska_welna]="blue_wool"
    [niebieski_barwnik]="blue_dye"
    [niebieski_beton]="blue_concrete"
    [niebieski_cement]="blue_concrete_powder"
    [niebieski_dywan]="blue_carpet"
    [niebieski_lod_lodowcowy]="blue_ice"
    [niebieski_sztandar]="blue_banner"
    [niebieskie_lozko]="blue_bed"
    [niebieskie_szklo]="blue_stained_glass"
    [niska_trawa]="short_grass"
    [nozyce]="shears"
    [obraz]="painting"
    [obsydian]="obsidian"
    [ociosane_akacjowe_drewno]="stripped_acacia_wood"
    [ociosane_bladodebowe_drewno]="stripped_pale_oak_wood"
    [ociosane_brzozowe_drewno]="stripped_birch_wood"
    [ociosane_ciemnodebowe_drewno]="stripped_dark_oak_wood"
    [ociosane_debowe_drewno]="stripped_oak_wood"
    [ociosane_namorzynowe_drewno]="stripped_mangrove_wood"
    [ociosane_spaczone_strzepki]="stripped_warped_hyphae"
    [ociosane_swierkowe_drewno]="stripped_spruce_wood"
    [ociosane_szkarlatne_strzepki]="stripped_crimson_hyphae"
    [ociosane_tropikalne_drewno]="stripped_jungle_wood"
    [ociosane_wisniowe_drewno]="stripped_cherry_wood"
    [ociosany_akacjowy_pien]="stripped_acacia_log"
    [ociosany_bladodebowy_pien]="stripped_pale_oak_log"
    [ociosany_brzozowy_pien]="stripped_birch_log"
    [ociosany_ciemnodebowy_pien]="stripped_dark_oak_log"
    [ociosany_debowy_pien]="stripped_oak_log"
    [ociosany_namorzynowy_pien]="stripped_mangrove_log"
    [ociosany_spaczony_trzon]="stripped_warped_stem"
    [ociosany_swierkowy_pien]="stripped_spruce_log"
    [ociosany_szkarlatny_trzon]="stripped_crimson_stem"
    [ociosany_tropikalny_pien]="stripped_jungle_log"
    [ociosany_wisniowy_pien]="stripped_cherry_log"
    [oddech_smoka]="dragon_breath"
    [odlamek_ametystu]="amethyst_shard"
    [odlamek_ceramiki_alchemik]="brewer_pottery_sherd"
    [odlamek_ceramiki_czaszka]="skull_pottery_sherd"
    [odlamek_ceramiki_dostatek]="plenty_pottery_sherd"
    [odlamek_ceramiki_druh]="friend_pottery_sherd"
    [odlamek_ceramiki_gornik]="miner_pottery_sherd"
    [odlamek_ceramiki_lucznik]="archer_pottery_sherd"
    [odlamek_ceramiki_nagroda]="prize_pottery_sherd"
    [odlamek_ceramiki_niuch]="snort_pottery_sherd"
    [odlamek_ceramiki_nurt]="flow_pottery_sherd"
    [odlamek_ceramiki_odkrywca]="explorer_pottery_sherd"
    [odlamek_ceramiki_ostoja]="shelter_pottery_sherd"
    [odlamek_ceramiki_ostrze]="blade_pottery_sherd"
    [odlamek_ceramiki_plomien]="burn_pottery_sherd"
    [odlamek_ceramiki_podmuch]="guster_pottery_sherd"
    [odlamek_ceramiki_rece_w_gorze]="arms_up_pottery_sherd"
    [odlamek_ceramiki_rybak]="angler_pottery_sherd"
    [odlamek_ceramiki_serce]="heart_pottery_sherd"
    [odlamek_ceramiki_skowyt]="howl_pottery_sherd"
    [odlamek_ceramiki_skrobak]="scrape_pottery_sherd"
    [odlamek_ceramiki_snop]="sheaf_pottery_sherd"
    [odlamek_ceramiki_zagrozenie]="danger_pottery_sherd"
    [odlamek_ceramiki_zalobnik]="mourner_pottery_sherd"
    [odlamek_ceramiki_zlamane_serce]="heartbreak_pottery_sherd"
    [odlamek_echa]="echo_shard"
    [odlamek_netherytu]="netherite_scrap"
    [odlamek_pryzmarynu]="prismarine_shard"
    [ognisko]="campfire"
    [ognisko_dusz]="soul_campfire"
    [ognista_kula]="fire_charge"
    [ognisty_kwiat]="torchflower"
    [oko_endera]="ender_eye"
    [oko_pajaka]="spider_eye"
    [otwarty_zerkwiat]="open_eyeblossom"
    [owoc_refrenusu]="chorus_fruit"
    [pajeczyna]="cobweb"
    [papier]="paper"
    [paproc]="fern"
    [patyk]="stick"
    [patyk_debugujacy]="debug_stick"
    [pedzel]="brush"
    [perlowa_zabia_lampa]="pearlescent_froglight"
    [piasek]="sand"
    [piasek_dusz]="soul_sand"
    [piaskowcowa_plyta]="sandstone_slab"
    [piaskowcowe_schody]="sandstone_stairs"
    [piaskowcowy_murek]="sandstone_wall"
    [piaskowiec]="sandstone"
    [piec]="furnace"
    [piec_hutniczy]="blast_furnace"
    [pieczona_baranina]="cooked_mutton"
    [pieczona_wieprzowina]="cooked_porkchop"
    [pieczona_wolowina]="cooked_beef"
    [pieczony_dorsz]="cooked_cod"
    [pieczony_krolik]="cooked_rabbit"
    [pieczony_kurczak]="cooked_chicken"
    [pieczony_losos]="cooked_salmon"
    [pieczony_ziemniak]="baked_potato"
    [pioro]="feather"
    [piorunochron]="lightning_rod"
    [piwonia]="peony"
    [placek_dyniowy]="pumpkin_pie"
    [placzace_pnacza]="weeping_vines"
    [placzacy_obsydian]="crying_obsidian"
    [plaster_miodu]="honeycomb"
    [plomienna_rozdzka]="blaze_rod"
    [plomienny_proszek]="blaze_powder"
    [plyta_muzyczna_music_disc_11]="music_disc_11"
    [plyta_muzyczna_music_disc_13]="music_disc_13"
    [plyta_muzyczna_music_disc_5]="music_disc_5"
    [plyta_muzyczna_music_disc_blocks]="music_disc_blocks"
    [plyta_muzyczna_music_disc_cat]="music_disc_cat"
    [plyta_muzyczna_music_disc_chirp]="music_disc_chirp"
    [plyta_muzyczna_music_disc_creator]="music_disc_creator"
    [plyta_muzyczna_music_disc_creator_music_box]="music_disc_creator_music_box"
    [plyta_muzyczna_music_disc_far]="music_disc_far"
    [plyta_muzyczna_music_disc_mall]="music_disc_mall"
    [plyta_muzyczna_music_disc_mellohi]="music_disc_mellohi"
    [plyta_muzyczna_music_disc_otherside]="music_disc_otherside"
    [plyta_muzyczna_music_disc_pigstep]="music_disc_pigstep"
    [plyta_muzyczna_music_disc_precipice]="music_disc_precipice"
    [plyta_muzyczna_music_disc_relic]="music_disc_relic"
    [plyta_muzyczna_music_disc_stal]="music_disc_stal"
    [plyta_muzyczna_music_disc_strad]="music_disc_strad"
    [plyta_muzyczna_music_disc_wait]="music_disc_wait"
    [plyta_muzyczna_music_disc_ward]="music_disc_ward"
    [pnacza]="vine"
    [pochodnia]="torch"
    [pochodnia_dusz]="soul_torch"
    [pochodnia_redstone]="redstone_torch"
    [podajnik]="dropper"
    [podejrzana_potrawka]="suspicious_stew"
    [podejrzany_piasek]="suspicious_sand"
    [podejrzany_zwir]="suspicious_gravel"
    [pole_uprawne]="farmland"
    [pomaranczowa_glazurowana_terakota]="orange_glazed_terracotta"
    [pomaranczowa_sakwa]="orange_bundle"
    [pomaranczowa_shulkerowa_skrzynia]="orange_shulker_box"
    [pomaranczowa_swieca]="orange_candle"
    [pomaranczowa_szyba]="orange_stained_glass_pane"
    [pomaranczowa_terakota]="orange_terracotta"
    [pomaranczowa_welna]="orange_wool"
    [pomaranczowe_lozko]="orange_bed"
    [pomaranczowe_szklo]="orange_stained_glass"
    [pomaranczowy_barwnik]="orange_dye"
    [pomaranczowy_beton]="orange_concrete"
    [pomaranczowy_cement]="orange_concrete_powder"
    [pomaranczowy_dywan]="orange_carpet"
    [pomaranczowy_sztandar]="orange_banner"
    [pomaranczowy_tulipan]="orange_tulip"
    [popekane_kamienne_cegly]="cracked_stone_bricks"
    [popekane_lupkowe_cegly]="cracked_deepslate_bricks"
    [popekane_lupkowe_kafelki]="cracked_deepslate_tiles"
    [popekane_netherowe_cegly]="cracked_nether_bricks"
    [popekane_wypolerowane_czernitowe_cegly]="cracked_polished_blackstone_bricks"
    [potrawka_z_krolika]="rabbit_stew"
    [powtarzajacy_blok_polecen]="repeating_command_block"
    [pradawne_zgliszcza]="ancient_debris"
    [prazony_owoc_refrenusu]="popped_chorus_fruit"
    [proch]="gunpowder"
    [pryzmaryn]="prismarine"
    [pryzmarynowa_ceglana_plyta]="prismarine_brick_slab"
    [pryzmarynowa_plyta]="prismarine_slab"
    [pryzmarynowe_ceglane_schody]="prismarine_brick_stairs"
    [pryzmarynowe_cegly]="prismarine_bricks"
    [pryzmarynowe_schody]="prismarine_stairs"
    [pryzmarynowy_murek]="prismarine_wall"
    [przecinarka]="stonecutter"
    [przekaznik_redstone]="repeater"
    [przewodnia]="conduit"
    [przyciemnione_szklo]="tinted_glass"
    [przycieta_czerwona_piaskowcowa_plyta]="cut_red_sandstone_slab"
    [przycieta_piaskowcowa_plyta]="cut_sandstone_slab"
    [przyciety_czerwony_piaskowiec]="cut_red_sandstone"
    [przyciety_piaskowiec]="cut_sandstone"
    [przyzywacz_potworow]="spawner"
    [przyzywacz_prob]="trial_spawner"
    [pszenica]="wheat"
    [pulpit]="lectern"
    [purpurowa_plyta]="purpur_slab"
    [purpurowe_schody]="purpur_stairs"
    [purpurowy_filar]="purpur_pillar"
    [pusta_mapa]="map"
    [pustka_strukturalna]="structure_void"
    [pylikwiat]="spore_blossom"
    [rama_portalu_do_endu]="end_portal_frame"
    [ramka_na_przedmiot]="item_frame"
    [rozdymka]="pufferfish"
    [rozowa_glazurowana_terakota]="pink_glazed_terracotta"
    [rozowa_sakwa]="pink_bundle"
    [rozowa_shulkerowa_skrzynia]="pink_shulker_box"
    [rozowa_swieca]="pink_candle"
    [rozowa_szyba]="pink_stained_glass_pane"
    [rozowa_terakota]="pink_terracotta"
    [rozowa_welna]="pink_wool"
    [rozowe_kwiatki]="pink_petals"
    [rozowe_lozko]="pink_bed"
    [rozowe_szklo]="pink_stained_glass"
    [rozowy_barwnik]="pink_dye"
    [rozowy_beton]="pink_concrete"
    [rozowy_cement]="pink_concrete_powder"
    [rozowy_dywan]="pink_carpet"
    [rozowy_sztandar]="pink_banner"
    [rozowy_tulipan]="pink_tulip"
    [ruda_miedzi]="raw_copper"
    [ruda_zelaza]="raw_iron"
    [rusztowanie]="scaffolding"
    [ryba_tropikalna]="tropical_fish"
    [rzezbiona_biblioteczka]="chiseled_bookshelf"
    [rzezbiona_miedz]="chiseled_copper"
    [rzezbione_kamienne_cegly]="chiseled_stone_bricks"
    [rzezbione_netherowe_cegly]="chiseled_nether_bricks"
    [rzezbione_tufowe_cegly]="chiseled_tuff_bricks"
    [rzezbione_zywicowe_cegly]="chiseled_resin_bricks"
    [rzezbiony_blok_kwarcu]="chiseled_quartz_block"
    [rzezbiony_czerwony_piaskowiec]="chiseled_red_sandstone"
    [rzezbiony_lupek]="chiseled_deepslate"
    [rzezbiony_piaskowiec]="chiseled_sandstone"
    [rzezbiony_tuf]="chiseled_tuff"
    [rzezbiony_wypolerowany_czernit]="chiseled_polished_blackstone"
    [sadzonka_akacji]="acacia_sapling"
    [sadzonka_bladego_debu]="pale_oak_sapling"
    [sadzonka_brzozy]="birch_sapling"
    [sadzonka_ciemnego_debu]="dark_oak_sapling"
    [sadzonka_debu]="oak_sapling"
    [sadzonka_swierku]="spruce_sapling"
    [sadzonka_tropikalna]="jungle_sapling"
    [sadzonka_wisni]="cherry_sapling"
    [sakwa]="bundle"
    [sciezka]="dirt_path"
    [sculk]="sculk"
    [sculkowe_wrzeszczydlo]="sculk_shrieker"
    [sculkowy_czujnik]="sculk_sensor"
    [sculkowy_katalizator]="sculk_catalyst"
    [serce_oceanu]="heart_of_the_sea"
    [sfermentowane_oko_pajaka]="fermented_spider_eye"
    [shulkerowa_skrzynia]="shulker_box"
    [siewka_namorzynu]="mangrove_propagule"
    [siodlo]="saddle"
    [skala_macierzysta]="bedrock"
    [skalibrowany_sculkowy_czujnik]="calibrated_sculk_sensor"
    [skamieniala_debowa_plyta]="petrified_oak_slab"
    [skarbiec]="vault"
    [skora]="leather"
    [skorupa_shulkera]="shulker_shell"
    [skorzana_czapka]="leather_helmet"
    [skorzana_tunika]="leather_chestplate"
    [skorzana_zbroja_konska]="leather_horse_armor"
    [skorzane_buty]="leather_boots"
    [skorzane_spodnie]="leather_leggings"
    [skrzynia]="chest"
    [skrzynia_endu]="ender_chest"
    [skrzynia_pulapka]="trapped_chest"
    [skupisko_ametystu]="amethyst_cluster"
    [slodkie_jagody]="sweet_berries"
    [slonecznik]="sunflower"
    [smocze_jajo]="dragon_egg"
    [smycz]="lead"
    [snieg]="snow"
    [sniezka]="snowball"
    [snop_siana]="hay_block"
    [spaczona_furtka]="warped_fence_gate"
    [spaczona_klapa]="warped_trapdoor"
    [spaczona_plyta]="warped_slab"
    [spaczona_plytka_naciskowa]="warped_pressure_plate"
    [spaczona_podwieszana_tabliczka]="warped_hanging_sign"
    [spaczona_tabliczka]="warped_sign"
    [spaczone_deski]="warped_planks"
    [spaczone_drzwi]="warped_door"
    [spaczone_korzenie]="warped_roots"
    [spaczone_nylium]="warped_nylium"
    [spaczone_pnacza]="twisting_vines"
    [spaczone_schody]="warped_stairs"
    [spaczone_strzepki]="warped_hyphae"
    [spaczony_grzyb]="warped_fungus"
    [spaczony_grzyb_na_patyku]="warped_fungus_on_a_stick"
    [spaczony_plot]="warped_fence"
    [spaczony_przycisk]="warped_button"
    [spaczony_trzon]="warped_stem"
    [spiczasty_naciek]="pointed_dripstone"
    [sproszkowany_redstone]="redstone"
    [sredni_zarodek_ametystu]="medium_amethyst_bud"
    [statyw_alchemiczny]="brewing_stand"
    [stojak_na_zbroje]="armor_stand"
    [stol_do_zaklinania]="enchanting_table"
    [stol_kartograficzny]="cartography_table"
    [stol_kowalski]="smithing_table"
    [stol_luczarski]="fletching_table"
    [stol_rzemieslniczy]="crafting_table"
    [strak_dzbanecznika]="pitcher_pod"
    [strzala]="arrow"
    [strzala_z_mikstura]="tipped_arrow"
    [surowa_baranina]="mutton"
    [surowa_wieprzowina]="porkchop"
    [surowa_wolowina]="beef"
    [surowe_zloto]="raw_gold"
    [surowy_dorsz]="cod"
    [surowy_krolik]="rabbit"
    [surowy_kurczak]="chicken"
    [surowy_losos]="salmon"
    [suszony_wodorost]="dried_kelp"
    [swiatlo]="light"
    [swiatlogrzyb]="shroomlight"
    [swieca]="candle"
    [swiecaca_ramka_na_przedmiot]="glow_item_frame"
    [swiecace_jagody]="glow_berries"
    [swiecacy_porost]="glow_lichen"
    [swierkowa_furtka]="spruce_fence_gate"
    [swierkowa_klapa]="spruce_trapdoor"
    [swierkowa_lodka]="spruce_boat"
    [swierkowa_lodka_ze_skrzynia]="spruce_chest_boat"
    [swierkowa_plyta]="spruce_slab"
    [swierkowa_plytka_naciskowa]="spruce_pressure_plate"
    [swierkowa_podwieszana_tabliczka]="spruce_hanging_sign"
    [swierkowa_tabliczka]="spruce_sign"
    [swierkowe_deski]="spruce_planks"
    [swierkowe_drewno]="spruce_wood"
    [swierkowe_drzwi]="spruce_door"
    [swierkowe_liscie]="spruce_leaves"
    [swierkowe_schody]="spruce_stairs"
    [swierkowy_pien]="spruce_log"
    [swierkowy_plot]="spruce_fence"
    [swierkowy_przycisk]="spruce_button"
    [szablon_kowalski_bolt_armor_trim_smithing_template]="bolt_armor_trim_smithing_template"
    [szablon_kowalski_coast_armor_trim_smithing_template]="coast_armor_trim_smithing_template"
    [szablon_kowalski_dune_armor_trim_smithing_template]="dune_armor_trim_smithing_template"
    [szablon_kowalski_eye_armor_trim_smithing_template]="eye_armor_trim_smithing_template"
    [szablon_kowalski_flow_armor_trim_smithing_template]="flow_armor_trim_smithing_template"
    [szablon_kowalski_host_armor_trim_smithing_template]="host_armor_trim_smithing_template"
    [szablon_kowalski_netherite_upgrade_smithing_template]="netherite_upgrade_smithing_template"
    [szablon_kowalski_raiser_armor_trim_smithing_template]="raiser_armor_trim_smithing_template"
    [szablon_kowalski_rib_armor_trim_smithing_template]="rib_armor_trim_smithing_template"
    [szablon_kowalski_sentry_armor_trim_smithing_template]="sentry_armor_trim_smithing_template"
    [szablon_kowalski_shaper_armor_trim_smithing_template]="shaper_armor_trim_smithing_template"
    [szablon_kowalski_silence_armor_trim_smithing_template]="silence_armor_trim_smithing_template"
    [szablon_kowalski_snout_armor_trim_smithing_template]="snout_armor_trim_smithing_template"
    [szablon_kowalski_spire_armor_trim_smithing_template]="spire_armor_trim_smithing_template"
    [szablon_kowalski_tide_armor_trim_smithing_template]="tide_armor_trim_smithing_template"
    [szablon_kowalski_vex_armor_trim_smithing_template]="vex_armor_trim_smithing_template"
    [szablon_kowalski_ward_armor_trim_smithing_template]="ward_armor_trim_smithing_template"
    [szablon_kowalski_wayfinder_armor_trim_smithing_template]="wayfinder_armor_trim_smithing_template"
    [szablon_kowalski_wild_armor_trim_smithing_template]="wild_armor_trim_smithing_template"
    [szafa_grajaca]="jukebox"
    [szara_glazurowana_terakota]="gray_glazed_terracotta"
    [szara_sakwa]="gray_bundle"
    [szara_shulkerowa_skrzynia]="gray_shulker_box"
    [szara_swieca]="gray_candle"
    [szara_szyba]="gray_stained_glass_pane"
    [szara_terakota]="gray_terracotta"
    [szara_welna]="gray_wool"
    [szare_lozko]="gray_bed"
    [szare_szklo]="gray_stained_glass"
    [szary_barwnik]="gray_dye"
    [szary_beton]="gray_concrete"
    [szary_cement]="gray_concrete_powder"
    [szary_dywan]="gray_carpet"
    [szary_sztandar]="gray_banner"
    [szkarlatna_furtka]="crimson_fence_gate"
    [szkarlatna_klapa]="crimson_trapdoor"
    [szkarlatna_plyta]="crimson_slab"
    [szkarlatna_plytka_naciskowa]="crimson_pressure_plate"
    [szkarlatna_podwieszana_tabliczka]="crimson_hanging_sign"
    [szkarlatna_tabliczka]="crimson_sign"
    [szkarlatne_deski]="crimson_planks"
    [szkarlatne_drzwi]="crimson_door"
    [szkarlatne_korzenie]="crimson_roots"
    [szkarlatne_nylium]="crimson_nylium"
    [szkarlatne_schody]="crimson_stairs"
    [szkarlatne_strzepki]="crimson_hyphae"
    [szkarlatny_grzyb]="crimson_fungus"
    [szkarlatny_plot]="crimson_fence"
    [szkarlatny_przycisk]="crimson_button"
    [szkarlatny_trzon]="crimson_stem"
    [szklana_butelka]="glass_bottle"
    [szklo]="glass"
    [szmaragd]="emerald"
    [sztabka_miedzi]="copper_ingot"
    [sztabka_netherytu]="netherite_ingot"
    [sztabka_zelaza]="iron_ingot"
    [sztabka_zlota]="gold_ingot"
    [szyba]="glass_pane"
    [tarcza]="shield"
    [tarcza_strzelecka]="target"
    [tarczka_pancernika]="armadillo_scute"
    [tarczka_zolwia]="turtle_scute"
    [terakota]="terracotta"
    [tlok]="piston"
    [tnt]="tnt"
    [torbiel_z_atramentem]="ink_sac"
    [torbiel_ze_swiecacym_atramentem]="glow_ink_sac"
    [tory]="rail"
    [tory_aktywacyjne]="activator_rail"
    [tory_z_czujnikiem]="detector_rail"
    [totem_niesmiertelnosci]="totem_of_undying"
    [trawa_morska]="seagrass"
    [trojzab]="trident"
    [tropikalna_furtka]="jungle_fence_gate"
    [tropikalna_klapa]="jungle_trapdoor"
    [tropikalna_lodka]="jungle_boat"
    [tropikalna_lodka_ze_skrzynia]="jungle_chest_boat"
    [tropikalna_plyta]="jungle_slab"
    [tropikalna_plytka_naciskowa]="jungle_pressure_plate"
    [tropikalna_podwieszana_tabliczka]="jungle_hanging_sign"
    [tropikalna_tabliczka]="jungle_sign"
    [tropikalne_deski]="jungle_planks"
    [tropikalne_drewno]="jungle_wood"
    [tropikalne_drzwi]="jungle_door"
    [tropikalne_liscie]="jungle_leaves"
    [tropikalne_schody]="jungle_stairs"
    [tropikalny_pien]="jungle_log"
    [tropikalny_plot]="jungle_fence"
    [tropikalny_przycisk]="jungle_button"
    [trujacy_ziemniak]="poisonous_potato"
    [trwala_mikstura]="lingering_potion"
    [trzcina_cukrowa]="sugar_cane"
    [trzeszczace_serce]="creaking_heart"
    [trzon_grzyba]="mushroom_stem"
    [tuf]="tuff"
    [tufowa_ceglana_plyta]="tuff_brick_slab"
    [tufowa_plyta]="tuff_slab"
    [tufowe_ceglane_schody]="tuff_brick_stairs"
    [tufowe_cegly]="tuff_bricks"
    [tufowe_schody]="tuff_stairs"
    [tufowy_ceglany_murek]="tuff_brick_wall"
    [tufowy_murek]="tuff_wall"
    [twarda_ziemia]="coarse_dirt"
    [ul]="beehive"
    [uschniety_krzak]="dead_bush"
    [uszkodzone_kowadlo]="damaged_anvil"
    [utleniona_miedz]="oxidized_copper"
    [utleniona_miedziana_klapa]="oxidized_copper_trapdoor"
    [utleniona_miedziana_krata]="oxidized_copper_grate"
    [utleniona_miedziana_lampa]="oxidized_copper_bulb"
    [utleniona_rzezbiona_miedz]="oxidized_chiseled_copper"
    [utleniona_zlobiona_miedz]="oxidized_cut_copper"
    [utleniona_zlobiona_miedziana_plyta]="oxidized_cut_copper_slab"
    [utlenione_miedziane_drzwi]="oxidized_copper_door"
    [utlenione_zlobione_miedziane_schody]="oxidized_cut_copper_stairs"
    [utwardzone_bloto]="packed_mud"
    [wachlarz_koralowca_babelkowatego]="bubble_coral_fan"
    [wachlarz_koralowca_mozgowatego]="brain_coral_fan"
    [wachlarz_koralowca_ognistego]="fire_coral_fan"
    [wachlarz_koralowca_rogatego]="horn_coral_fan"
    [wachlarz_koralowca_rurkowatego]="tube_coral_fan"
    [wagonik]="minecart"
    [wagonik_z_blokiem_polecen]="command_block_minecart"
    [wagonik_z_lejem]="hopper_minecart"
    [wagonik_z_tnt]="tnt_minecart"
    [wagonik_ze_skrzynia]="chest_minecart"
    [warstwa_bladego_mchu]="pale_moss_carpet"
    [warstwa_mchu]="moss_carpet"
    [wedka]="fishing_rod"
    [wedzarka]="smoker"
    [wegiel]="coal"
    [wegiel_drzewny]="charcoal"
    [wiadro]="bucket"
    [wiadro_lawy]="lava_bucket"
    [wiadro_mleka]="milk_bucket"
    [wiadro_sypkiego_sniegu]="powder_snow_bucket"
    [wiadro_wody]="water_bucket"
    [wiadro_z_aksolotlem]="axolotl_bucket"
    [wiadro_z_dorszem]="cod_bucket"
    [wiadro_z_kijanka]="tadpole_bucket"
    [wiadro_z_lososiem]="salmon_bucket"
    [wiadro_z_rozdymka]="pufferfish_bucket"
    [wiadro_z_tropikalna_ryba]="tropical_fish_bucket"
    [wichrowa_rozdzka]="breeze_rod"
    [widmowa_strzala]="spectral_arrow"
    [wielki_spadkolisc]="big_dripleaf"
    [wietrzna_kula]="wind_charge"
    [wilcza_zbroja]="wolf_armor"
    [wisniowa_furtka]="cherry_fence_gate"
    [wisniowa_klapa]="cherry_trapdoor"
    [wisniowa_lodka]="cherry_boat"
    [wisniowa_lodka_ze_skrzynia]="cherry_chest_boat"
    [wisniowa_plyta]="cherry_slab"
    [wisniowa_plytka_naciskowa]="cherry_pressure_plate"
    [wisniowa_podwieszana_tabliczka]="cherry_hanging_sign"
    [wisniowa_tabliczka]="cherry_sign"
    [wisniowe_deski]="cherry_planks"
    [wisniowe_drewno]="cherry_wood"
    [wisniowe_drzwi]="cherry_door"
    [wisniowe_liscie]="cherry_leaves"
    [wisniowe_schody]="cherry_stairs"
    [wisniowy_pien]="cherry_log"
    [wisniowy_plot]="cherry_fence"
    [wisniowy_przycisk]="cherry_button"
    [witherowa_roza]="wither_rose"
    [wodorost]="kelp"
    [woskowana_miedziana_klapa]="waxed_copper_trapdoor"
    [woskowana_miedziana_krata]="waxed_copper_grate"
    [woskowana_miedziana_lampa]="waxed_copper_bulb"
    [woskowana_rzezbiona_miedz]="waxed_chiseled_copper"
    [woskowana_utleniona_miedz]="waxed_oxidized_copper"
    [woskowana_utleniona_miedziana_klapa]="waxed_oxidized_copper_trapdoor"
    [woskowana_utleniona_miedziana_krata]="waxed_oxidized_copper_grate"
    [woskowana_utleniona_miedziana_lampa]="waxed_oxidized_copper_bulb"
    [woskowana_utleniona_rzezbiona_miedz]="waxed_oxidized_chiseled_copper"
    [woskowana_utleniona_zlobiona_miedz]="waxed_oxidized_cut_copper"
    [woskowana_utleniona_zlobiona_miedziana_plyta]="waxed_oxidized_cut_copper_slab"
    [woskowana_zasniedziala_miedz]="waxed_weathered_copper"
    [woskowana_zasniedziala_miedziana_klapa]="waxed_weathered_copper_trapdoor"
    [woskowana_zasniedziala_miedziana_krata]="waxed_weathered_copper_grate"
    [woskowana_zasniedziala_miedziana_lampa]="waxed_weathered_copper_bulb"
    [woskowana_zasniedziala_rzezbiona_miedz]="waxed_weathered_chiseled_copper"
    [woskowana_zasniedziala_zlobiona_miedz]="waxed_weathered_cut_copper"
    [woskowana_zasniedziala_zlobiona_miedziana_plyta]="waxed_weathered_cut_copper_slab"
    [woskowana_zlobiona_miedz]="waxed_cut_copper"
    [woskowana_zlobiona_miedziana_plyta]="waxed_cut_copper_slab"
    [woskowana_zwietrzala_miedz]="waxed_exposed_copper"
    [woskowana_zwietrzala_miedziana_klapa]="waxed_exposed_copper_trapdoor"
    [woskowana_zwietrzala_miedziana_krata]="waxed_exposed_copper_grate"
    [woskowana_zwietrzala_miedziana_lampa]="waxed_exposed_copper_bulb"
    [woskowana_zwietrzala_rzezbiona_miedz]="waxed_exposed_chiseled_copper"
    [woskowana_zwietrzala_zlobiona_miedz]="waxed_exposed_cut_copper"
    [woskowana_zwietrzala_zlobiona_miedziana_plyta]="waxed_exposed_cut_copper_slab"
    [woskowane_miedziane_drzwi]="waxed_copper_door"
    [woskowane_utlenione_miedziane_drzwi]="waxed_oxidized_copper_door"
    [woskowane_utlenione_zlobione_miedziane_schody]="waxed_oxidized_cut_copper_stairs"
    [woskowane_zasniedziale_miedziane_drzwi]="waxed_weathered_copper_door"
    [woskowane_zasniedziale_zlobione_miedziane_schody]="waxed_weathered_cut_copper_stairs"
    [woskowane_zlobione_miedziane_schody]="waxed_cut_copper_stairs"
    [woskowane_zwietrzale_miedziane_drzwi]="waxed_exposed_copper_door"
    [woskowane_zwietrzale_zlobione_miedziane_schody]="waxed_exposed_cut_copper_stairs"
    [woskowany_blok_miedzi]="waxed_copper_block"
    [wykrawana_dynia]="carved_pumpkin"
    [wypolerowana_andezytowa_plyta]="polished_andesite_slab"
    [wypolerowana_czernitowa_ceglana_plyta]="polished_blackstone_brick_slab"
    [wypolerowana_czernitowa_plyta]="polished_blackstone_slab"
    [wypolerowana_czernitowa_plytka_naciskowa]="polished_blackstone_pressure_plate"
    [wypolerowana_diorytowa_plyta]="polished_diorite_slab"
    [wypolerowana_granitowa_plyta]="polished_granite_slab"
    [wypolerowana_lupkowa_plyta]="polished_deepslate_slab"
    [wypolerowana_tufowa_plyta]="polished_tuff_slab"
    [wypolerowane_andezytowe_schody]="polished_andesite_stairs"
    [wypolerowane_czernitowe_ceglane_schody]="polished_blackstone_brick_stairs"
    [wypolerowane_czernitowe_cegly]="polished_blackstone_bricks"
    [wypolerowane_czernitowe_schody]="polished_blackstone_stairs"
    [wypolerowane_diorytowe_schody]="polished_diorite_stairs"
    [wypolerowane_granitowe_schody]="polished_granite_stairs"
    [wypolerowane_lupkowe_schody]="polished_deepslate_stairs"
    [wypolerowane_tufowe_schody]="polished_tuff_stairs"
    [wypolerowany_andezyt]="polished_andesite"
    [wypolerowany_bazalt]="polished_basalt"
    [wypolerowany_czernit]="polished_blackstone"
    [wypolerowany_czernitowy_ceglany_murek]="polished_blackstone_brick_wall"
    [wypolerowany_czernitowy_murek]="polished_blackstone_wall"
    [wypolerowany_czernitowy_przycisk]="polished_blackstone_button"
    [wypolerowany_dioryt]="polished_diorite"
    [wypolerowany_granit]="polished_granite"
    [wypolerowany_lupek]="polished_deepslate"
    [wypolerowany_lupkowy_murek]="polished_deepslate_wall"
    [wypolerowany_tuf]="polished_tuff"
    [wypolerowany_tufowy_murek]="polished_tuff_wall"
    [wysoka_trawa]="tall_grass"
    [wyszczerbione_kowadlo]="chipped_anvil"
    [wytwarzacz]="crafter"
    [wzor_sztandaru_creeper_banner_pattern]="creeper_banner_pattern"
    [wzor_sztandaru_flow_banner_pattern]="flow_banner_pattern"
    [wzor_sztandaru_flower_banner_pattern]="flower_banner_pattern"
    [wzor_sztandaru_globe_banner_pattern]="globe_banner_pattern"
    [wzor_sztandaru_guster_banner_pattern]="guster_banner_pattern"
    [wzor_sztandaru_mojang_banner_pattern]="mojang_banner_pattern"
    [wzor_sztandaru_mur]="field_masoned_banner_pattern"
    [wzor_sztandaru_piglin_banner_pattern]="piglin_banner_pattern"
    [wzor_sztandaru_skull_banner_pattern]="skull_banner_pattern"
    [wzor_sztandaru_zabkowane_obramowanie]="bordure_indented_banner_pattern"
    [zabi_skrzek]="frogspawn"
    [zablocone_namorzynowe_korzenie]="muddy_mangrove_roots"
    [zaczep_na_linke]="tripwire_hook"
    [zakleta_butelka]="experience_bottle"
    [zakleta_ksiazka]="enchanted_book"
    [zaklete_zlote_jablko]="enchanted_golden_apple"
    [zakorzeniona_ziemia]="rooted_dirt"
    [zamkniety_zerkwiat]="closed_eyeblossom"
    [zamszona_brukowa_plyta]="mossy_cobblestone_slab"
    [zamszona_kamienna_ceglana_plyta]="mossy_stone_brick_slab"
    [zamszone_brukowe_schody]="mossy_cobblestone_stairs"
    [zamszone_kamienne_ceglane_schody]="mossy_stone_brick_stairs"
    [zamszone_kamienne_cegly]="mossy_stone_bricks"
    [zamszony_bruk]="mossy_cobblestone"
    [zamszony_brukowy_murek]="mossy_cobblestone_wall"
    [zamszony_kamienny_ceglany_murek]="mossy_stone_brick_wall"
    [zapisana_ksiazka]="written_book"
    [zarobaczone_kamienne_cegly]="infested_stone_bricks"
    [zarobaczone_popekane_kamienne_cegly]="infested_cracked_stone_bricks"
    [zarobaczone_rzezbione_kamienne_cegly]="infested_chiseled_stone_bricks"
    [zarobaczone_zamszone_kamienne_cegly]="infested_mossy_stone_bricks"
    [zarobaczony_bruk]="infested_cobblestone"
    [zarobaczony_kamien]="infested_stone"
    [zarobaczony_lupek]="infested_deepslate"
    [zasilane_tory]="powered_rail"
    [zasniedziala_miedz]="weathered_copper"
    [zasniedziala_miedziana_klapa]="weathered_copper_trapdoor"
    [zasniedziala_miedziana_krata]="weathered_copper_grate"
    [zasniedziala_miedziana_lampa]="weathered_copper_bulb"
    [zasniedziala_rzezbiona_miedz]="weathered_chiseled_copper"
    [zasniedziala_zlobiona_miedz]="weathered_cut_copper"
    [zasniedziala_zlobiona_miedziana_plyta]="weathered_cut_copper_slab"
    [zasniedziale_miedziane_drzwi]="weathered_copper_door"
    [zasniedziale_zlobione_miedziane_schody]="weathered_cut_copper_stairs"
    [zbity_lod]="packed_ice"
    [zbrojony_lupek]="reinforced_deepslate"
    [zegar]="clock"
    [zelazna_klapa]="iron_trapdoor"
    [zelazna_lopata]="iron_shovel"
    [zelazna_motyka]="iron_hoe"
    [zelazna_siekiera]="iron_axe"
    [zelazna_zbroja_konska]="iron_horse_armor"
    [zelazne_buty]="iron_boots"
    [zelazne_drzwi]="iron_door"
    [zelazne_kraty]="iron_bars"
    [zelazne_nogawice]="iron_leggings"
    [zelazny_helm]="iron_helmet"
    [zelazny_kilof]="iron_pickaxe"
    [zelazny_miecz]="iron_sword"
    [zelazny_napiersnik]="iron_chestplate"
    [zgnile_mieso]="rotten_flesh"
    [ziarna_kakaowe]="cocoa_beans"
    [zielenista_zabia_lampa]="verdant_froglight"
    [zielona_glazurowana_terakota]="green_glazed_terracotta"
    [zielona_sakwa]="green_bundle"
    [zielona_shulkerowa_skrzynia]="green_shulker_box"
    [zielona_swieca]="green_candle"
    [zielona_szyba]="green_stained_glass_pane"
    [zielona_terakota]="green_terracotta"
    [zielona_welna]="green_wool"
    [zielone_lozko]="green_bed"
    [zielone_szklo]="green_stained_glass"
    [zielony_barwnik]="green_dye"
    [zielony_beton]="green_concrete"
    [zielony_cement]="green_concrete_powder"
    [zielony_dywan]="green_carpet"
    [zielony_sztandar]="green_banner"
    [ziemia]="dirt"
    [ziemniak]="potato"
    [zlobiona_miedz]="cut_copper"
    [zlobiona_miedziana_plyta]="cut_copper_slab"
    [zlobione_miedziane_schody]="cut_copper_stairs"
    [zlocista_zabia_lampa]="ochre_froglight"
    [zlocony_czernit]="gilded_blackstone"
    [zlota_lopata]="golden_shovel"
    [zlota_marchewka]="golden_carrot"
    [zlota_motyka]="golden_hoe"
    [zlota_siekiera]="golden_axe"
    [zlota_zbroja_konska]="golden_horse_armor"
    [zlote_buty]="golden_boots"
    [zlote_jablko]="golden_apple"
    [zlote_nogawice]="golden_leggings"
    [zloty_helm]="golden_helmet"
    [zloty_kilof]="golden_pickaxe"
    [zloty_miecz]="golden_sword"
    [zloty_napiersnik]="golden_chestplate"
    [zlowieszcza_butelka]="ominous_bottle"
    [zlowieszczy_klucz_proby]="ominous_trial_key"
    [zloze_diamentu]="diamond_ore"
    [zloze_lazurytu]="lapis_ore"
    [zloze_miedzi]="copper_ore"
    [zloze_netherowego_kwarcu]="nether_quartz_ore"
    [zloze_redstone]="redstone_ore"
    [zloze_szmaragdu]="emerald_ore"
    [zloze_wegla]="coal_ore"
    [zloze_zelaza]="iron_ore"
    [zloze_zlota]="gold_ore"
    [znacznik]="name_tag"
    [zolta_glazurowana_terakota]="yellow_glazed_terracotta"
    [zolta_sakwa]="yellow_bundle"
    [zolta_shulkerowa_skrzynia]="yellow_shulker_box"
    [zolta_swieca]="yellow_candle"
    [zolta_szyba]="yellow_stained_glass_pane"
    [zolta_terakota]="yellow_terracotta"
    [zolta_welna]="yellow_wool"
    [zolte_lozko]="yellow_bed"
    [zolte_szklo]="yellow_stained_glass"
    [zolty_barwnik]="yellow_dye"
    [zolty_beton]="yellow_concrete"
    [zolty_cement]="yellow_concrete_powder"
    [zolty_dywan]="yellow_carpet"
    [zolty_sztandar]="yellow_banner"
    [zolwia_skorupa]="turtle_helmet"
    [zolwie_jajko]="turtle_egg"
    [zupa_grzybowa]="mushroom_stew"
    [zwietrzala_miedz]="exposed_copper"
    [zwietrzala_miedziana_klapa]="exposed_copper_trapdoor"
    [zwietrzala_miedziana_krata]="exposed_copper_grate"
    [zwietrzala_miedziana_lampa]="exposed_copper_bulb"
    [zwietrzala_rzezbiona_miedz]="exposed_chiseled_copper"
    [zwietrzala_zlobiona_miedz]="exposed_cut_copper"
    [zwietrzala_zlobiona_miedziana_plyta]="exposed_cut_copper_slab"
    [zwietrzale_miedziane_drzwi]="exposed_copper_door"
    [zwietrzale_zlobione_miedziane_schody]="exposed_cut_copper_stairs"
    [zwir]="gravel"
    [zwisajace_korzenie]="hanging_roots"
    [zwisajacy_blady_mech]="pale_hanging_moss"
    [zyly_sculku]="sculk_vein"
    [zywicowa_cegla]="resin_brick"
    [zywicowa_ceglana_plyta]="resin_brick_slab"
    [zywicowe_ceglane_schody]="resin_brick_stairs"
    [zywicowe_cegly]="resin_bricks"
    [zywicowy_ceglany_murek]="resin_brick_wall"

)

# ==================================================
# SZUKANIE / ROZWIĄZYWANIE NAZW PRZEDMIOTÓW
# ==================================================

# Zbiór wszystkich poprawnych angielskich ID (do szybkiej walidacji
# O(1) w item_rozwiaz) - budowany raz z wartości słownika PRZEDMIOTY.
declare -A MC_ID_ZBIOR
for _mc_id in "${PRZEDMIOTY[@]}"; do
    MC_ID_ZBIOR["$_mc_id"]=1
done
unset _mc_id

# szukaj <fraza> - przeszukuje słownik po polskiej nazwie
# i po angielskim ID, wypisuje pasujące wpisy.

szukaj() {

    local zapytanie="${1,,}"

    if [[ -z "$zapytanie" ]]; then
        echo "Użycie: szukaj rozdymka"
        return 1
    fi

    local znaleziono=0

    echo "
Wyniki wyszukiwania dla '$zapytanie':
"

    for klucz in $(printf "%s\n" "${!PRZEDMIOTY[@]}" | sort); do

        if [[ "$klucz" == *"$zapytanie"* || "${PRZEDMIOTY[$klucz]}" == *"$zapytanie"* ]]; then
            printf "  %-30s -> %s\n" "$klucz" "${PRZEDMIOTY[$klucz]}"
            znaleziono=1
        fi
    done

    if [[ $znaleziono -eq 0 ]]; then
        echo "  Brak wyników. Spróbuj innego słowa albo 'przedmioty' dla pełnej listy."
    fi

    echo ""
}


# przedmioty - wypisuje cały słownik posortowany alfabetycznie

przedmioty() {

    for klucz in $(printf "%s\n" "${!PRZEDMIOTY[@]}" | sort); do
        printf "  %-30s -> %s\n" "$klucz" "${PRZEDMIOTY[$klucz]}"
    done
}


# item_rozwiaz <zapytanie> - zamienia polską nazwę na ID Minecrafta.
# Akceptuje TYLKO: dokładny klucz polski ze słownika, albo dokładne
# poprawne angielskie ID (z opcjonalnym prefiksem "minecraft:").
# Niejednoznaczne/nieznane frazy (np. samo "kilof" bez wariantu
# materiału) są odrzucane z czytelnym błędem zamiast wysyłać do
# serwera nieistniejące ID, które ciho nic by nie dało.
# Zwraca ID przez stdout, kod 1 jeśli się nie uda.

item_rozwiaz() {

    local zapytanie="${1,,}"
    local zapytanie_bez_ns="${zapytanie#minecraft:}"

    if [[ -n "${PRZEDMIOTY[$zapytanie]:-}" ]]; then
        echo "${PRZEDMIOTY[$zapytanie]}"
        return 0
    fi

    if [[ -n "${MC_ID_ZBIOR[$zapytanie_bez_ns]:-}" ]] && item_waliduj "$zapytanie_bez_ns"; then
        echo "$zapytanie_bez_ns"
        return 0
    fi

    return 1
}


# ==================================================
# ZAKLĘCIA (RCON)
# ==================================================
#
# Słownik wszystkich zaklęć dostępnych w grze wraz z polskimi
# opisami i maksymalnym poziomem dopuszczalnym przez /enchant
# (te same limity, które egzekwuje sama gra - jeśli podasz więcej,
# encik odrzuci to od razu z czytelnym komunikatem).

declare -A ZAKLECIA_OPISY=(

    [aqua_affinity]="szybsze kopanie pod wodą (hełm)"
    [bane_of_arthropods]="dodatkowe obrażenia stawonogom - pająki, molki (miecz/topór)"
    [binding_curse]="klątwa związania - nie można zdjąć (zbroja)"
    [blast_protection]="ochrona przed obrażeniami od wybuchów (zbroja)"
    [breach]="częściowo ignoruje pancerz przeciwnika (topór)"
    [channeling]="przywołuje piorun przy trafieniu podczas burzy (trójząb)"
    [depth_strider]="szybsze poruszanie się w wodzie (buty)"
    [density]="dodatkowe obrażenia za każdy blok spadania (buzdygan)"
    [efficiency]="szybsze kopanie (narzędzia)"
    [feather_falling]="mniejsze obrażenia od upadku (buty)"
    [fire_aspect]="podpala trafionego przeciwnika (miecz)"
    [fire_protection]="ochrona przed obrażeniami od ognia (zbroja)"
    [flame]="płonące strzały (łuk)"
    [fortune]="więcej surowców z wykopanych bloków (narzędzia)"
    [frost_walker]="zamraża wodę pod nogami w lód (buty)"
    [impaling]="dodatkowe obrażenia morskim stworzeniom (trójząb)"
    [infinity]="nieskończona amunicja - nie zużywa strzał (łuk)"
    [knockback]="mocniej odrzuca przeciwnika (miecz)"
    [looting]="więcej łupu z pokonanych mobów (miecz)"
    [loyalty]="trójząb wraca do ręki po rzucie (trójząb)"
    [luck_of_the_sea]="lepszy fant przy wędkowaniu (wędka)"
    [lure]="szybsze branie ryb (wędka)"
    [mending]="naprawia przedmiot za zdobywane doświadczenie"
    [multishot]="kusza strzela trzema bełtami naraz (kusza)"
    [piercing]="bełty przebijają cele na wylot (kusza)"
    [power]="większe obrażenia od strzał (łuk)"
    [projectile_protection]="ochrona przed pociskami - strzały itp. (zbroja)"
    [protection]="ogólna ochrona przed większością obrażeń (zbroja)"
    [punch]="mocniej odrzuca trafionego strzałą (łuk)"
    [quick_charge]="szybsze ładowanie kuszy (kusza)"
    [respiration]="dłuższy oddech pod wodą (hełm)"
    [riptide]="teleportuje gracza rzutem trójzębu w wodzie/deszczu (trójząb)"
    [sharpness]="większe obrażenia w walce wręcz (miecz/topór)"
    [silk_touch]="zbiera bloki w oryginalnej postaci (narzędzia)"
    [smite]="dodatkowe obrażenia nieumarłym - zombie, szkielety (miecz)"
    [soul_speed]="szybsze poruszanie po piasku dusz (buty)"
    [sweeping_edge]="większe obrażenia ataku obszarowego (miecz)"
    [swift_sneak]="szybsze skradanie się (spodnie)"
    [thorns]="odbija część obrażeń napastnikowi (zbroja)"
    [unbreaking]="większa trwałość - rzadziej się psuje (wszystko)"
    [vanishing_curse]="klątwa znikania - przedmiot znika po śmierci (wszystko)"
    [wind_burst]="wybuch podmuchu wiatru przy trafieniu (buzdygan)"

)

# Maksymalny poziom każdego zaklęcia - dokładnie te same limity,
# które wymusza /enchant. Cokolwiek tu nie ma - domyślnie 1.
declare -A ZAKLECIA_MAX=(

    [sharpness]=5 [smite]=5 [bane_of_arthropods]=5 [power]=5 [impaling]=5 [density]=5 [efficiency]=5
    [protection]=4 [blast_protection]=4 [fire_protection]=4 [projectile_protection]=4 [breach]=4 [piercing]=4 [feather_falling]=4
    [unbreaking]=3 [fortune]=3 [looting]=3 [loyalty]=3 [luck_of_the_sea]=3 [lure]=3 [respiration]=3
    [depth_strider]=3 [riptide]=3 [soul_speed]=3 [sweeping_edge]=3 [swift_sneak]=3 [thorns]=3 [quick_charge]=3 [wind_burst]=3
    [fire_aspect]=2 [knockback]=2 [punch]=2 [frost_walker]=2

)

# Zbiór poprawnych ID zaklęć (do szybkiej walidacji O(1))
declare -A MC_ZAKLECIA_ZBIOR
for _mc_zak in "${!ZAKLECIA_OPISY[@]}"; do
    MC_ZAKLECIA_ZBIOR["$_mc_zak"]=1
done
unset _mc_zak


# encik co - lista wszystkich zaklęć z opisami i maksymalnym poziomem

encik_lista() {

    echo "
==============================
      DOSTĘPNE ZAKLĘCIA
==============================
"

    for zak in $(printf "%s\n" "${!ZAKLECIA_OPISY[@]}" | sort); do
        printf "%-22s (max %s) - %s\n" "$zak" "${ZAKLECIA_MAX[$zak]:-1}" "${ZAKLECIA_OPISY[$zak]}"
    done

    echo "
Użycie:

encik <gracz> <przedmiot> <zaklęcie[:poziom]> [zaklęcie2[:poziom2]] ...

UWAGA: podmienia przedmiot aktualnie trzymany w ręce gracza!
Poziom nie może przekroczyć maksimum z gry (patrz kolumna wyżej).
Bez podania poziomu domyślnie 1.

Przykłady:

encik g2 tarcza unbreaking:3
encik g1 netherytowy_miecz sharpness:5 unbreaking:3 mending
encik gracz2 luk infinity power:5

"

}


# zaklecie_rozwiaz <nazwa> - waliduje nazwę zaklęcia względem
# realnej listy istniejących w grze zaklęć. Odrzuca nieznane/
# niebezpieczne wartości zamiast wstrzykiwać je bezpośrednio
# do komendy RCON (to samo podejście co przy item_rozwiaz).

zaklecie_rozwiaz() {

    local zapytanie="${1,,}"
    local zapytanie_bez_ns="${zapytanie#minecraft:}"

    if [[ -n "${MC_ZAKLECIA_ZBIOR[$zapytanie_bez_ns]:-}" ]] && item_waliduj "$zapytanie_bez_ns"; then
        echo "$zapytanie_bez_ns"
        return 0
    fi

    return 1
}


# encik <gracz> <przedmiot> <zaklęcie[:poziom]> [zaklęcie2[:poziom2]] ... -
# daje przedmiot z jednym LUB WIELOMA zaklęciami naraz. Poziom po
# dwukropku jest opcjonalny, domyślnie 1 (np. "sharpness" = poziom 1,
# "sharpness:5" = poziom 5).
#
# UWAGA - jak to działa: format /give[enchantments={...}] w naszych
# testach na tej wersji gry (Paper 26.2) przechodził bez błędu, ale
# NIE nakładał realnie zaklęcia. Jedyny niezawodny, potwierdzony
# testem sposób to: /item replace wstawia goły przedmiot bezpośrednio
# w rękę gracza (main hand), a /enchant (wywoływane raz na każde
# zaklęcie) dokłada kolejne zaklęcia na ten sam przedmiot.
#
# Konsekwencje tego podejścia:
#   1. PODMIENIA to, co gracz aktualnie trzyma w ręce (main hand)!
#      Cokolwiek tam było, zostaje nadpisane.
#   2. Poziom każdego zaklęcia nie może przekroczyć maksimum z gry
#      (patrz ZAKLECIA_MAX) - sprawdzane lokalnie PRZED wysłaniem
#      czegokolwiek do serwera, więc albo wszystko się uda, albo nic.
#   3. Zaklęcia wykluczające się wzajemnie (np. sharpness + smite)
#      zostaną odrzucone przez samą grę przy drugim /enchant - komunikat
#      gry pojawi się wprost w terminalu.

encik() {

    mc_check || return 1

    if [[ "$1" == "co" || "$1" == "lista" ]]; then
        encik_lista
        return
    fi

    local gracz="$1"
    local item_nazwa="$2"
    shift 2

    if [[ -z "$gracz" || -z "$item_nazwa" || $# -eq 0 ]]; then

        echo "
Użycie:

encik <gracz> <przedmiot> <zaklęcie[:poziom]> [zaklęcie2[:poziom2]] ...

UWAGA: podmienia przedmiot aktualnie trzymany w ręce gracza!

Przykłady:

encik g2 tarcza unbreaking:3
encik g1 netherytowy_miecz sharpness:5 unbreaking:3 mending
encik gracz2 luk infinity power:5

Lista zaklęć z maksymalnymi poziomami: encik co

"
        return 1
    fi

    local nick
    nick=$(gracz_nick "$gracz") || {

        echo -e "${RED}Nieznany gracz.${NC}"
        gracz_lista
        return 1
    }

    local mc_item
    mc_item=$(item_rozwiaz "$item_nazwa") || {

        echo -e "${RED}Nie znaleziono itemu: $item_nazwa${NC}"
        echo "Spróbuj: szukaj $item_nazwa"

        mc_log "encik" "ODRZUCONO nieznaleziony item: gracz=$gracz item=$item_nazwa"

        return 1
    }

    # Walidacja WSZYSTKICH podanych zaklęć NAJPIERW, zanim cokolwiek
    # trafi do serwera - albo cała komenda się uda, albo nic się nie zmieni.
    local -a zaklecia_ok=()
    local para nazwa poziom mc_zaklecie max_poziom

    for para in "$@"; do

        nazwa="${para%%:*}"

        if [[ "$para" == *:* ]]; then
            poziom="${para#*:}"
        else
            poziom=1
        fi

        if [[ ! "$poziom" =~ ^[0-9]+$ ]]; then

            echo -e "${RED}Nieprawidłowy poziom w '$para' (musi być liczbą).${NC}"
            return 1
        fi

        mc_zaklecie=$(zaklecie_rozwiaz "$nazwa") || {

            echo -e "${RED}Nie znaleziono zaklęcia: $nazwa${NC}"
            echo "Sprawdź: encik co"

            mc_log "encik" "ODRZUCONO nieznane zaklecie: gracz=$gracz zaklecie=$nazwa"

            return 1
        }

        max_poziom="${ZAKLECIA_MAX[$mc_zaklecie]:-1}"

        if (( poziom > max_poziom )); then

            echo -e "${RED}Poziom $poziom za wysoki dla $mc_zaklecie (max: $max_poziom).${NC}"

            mc_log "encik" "ODRZUCONO za wysoki poziom: gracz=$gracz zaklecie=$mc_zaklecie poziom=$poziom max=$max_poziom"

            return 1
        fi

        zaklecia_ok+=("$mc_zaklecie:$poziom")
    done

    rcon "item replace entity $nick weapon.mainhand with minecraft:$mc_item 1"

    local wpis mz mp
    for wpis in "${zaklecia_ok[@]}"; do
        mz="${wpis%%:*}"
        mp="${wpis#*:}"
        rcon "enchant $nick minecraft:$mz $mp"
    done

    echo -e "${GREEN}$mc_item w ręce gracza $gracz z zaklęciami: ${zaklecia_ok[*]}${NC}"
}


# ==================================================
# ZAPIS ŚWIATA
# ==================================================

zapisz() {

    mc_check || return 1

    rcon "save-all flush"

    echo -e "${GREEN}Świat zapisany.${NC}"
}


# ==================================================
# ITEMY
# ==================================================

daj() {

    mc_check || return 1

    local gracz="$1"
    local item="$2"
    local ilosc="${3:-1}"


    local nick
    nick=$(gracz_nick "$gracz") || {

        echo -e "${RED}Nieznany gracz.${NC}"
        gracz_lista
        return 1
    }


    if [[ -z "$item" || ! "$ilosc" =~ ^[0-9]+$ ]]; then

        echo "
Użycie:

daj gracz1 diamond 10
daj gracz1 rozdymka             (bez ilości = domyślnie 1 szt.)
daj g1 kilof 1                    (krótki alias gracza też działa: g1, g2)

Nie pamiętasz nazwy? Wpisz: szukaj rozdymka

"

        return 1
    fi


    local mc_item
    mc_item=$(item_rozwiaz "$item") || {

        echo -e "${RED}Nie znaleziono itemu: $item${NC}"
        echo "Spróbuj: szukaj $item"

        mc_log "daj" "ODRZUCONO nieznaleziony/nieprawidlowy item: gracz=$gracz item=$item ilosc=$ilosc"

        return 1
    }


    rcon "give $nick minecraft:$mc_item $ilosc"


    echo -e "${GREEN}Dano $ilosc x $mc_item graczowi $gracz.${NC}"

}


# ==================================================
# TELEPORTY
# ==================================================

# dom - zawsze te same, stałe współrzędne (domyślny "dom" gracza).
# Do teleportu pod dowolne współrzędne służy funkcja tp.


_mc_wspolrzedne() {
    local wartosc
    for wartosc in "$@"; do
        if [[ ! "$wartosc" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
            echo "Uzupełnij współrzędne w nik.local.sh."
            return 1
        fi
    done
}

dom() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    _mc_wspolrzedne "$MC_DOM_X" "$MC_DOM_Y" "$MC_DOM_Z" || return 1
    rcon "tp $nick $MC_DOM_X $MC_DOM_Y $MC_DOM_Z"


    echo -e "${GREEN}$1 teleportowany do domu.${NC}"

}



zamek() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    _mc_wspolrzedne "$MC_ZAMEK_X" "$MC_ZAMEK_Y" "$MC_ZAMEK_Z" || return 1
    rcon "tp $nick $MC_ZAMEK_X $MC_ZAMEK_Y $MC_ZAMEK_Z"


    echo -e "${GREEN}$1 teleportowany do zamku.${NC}"

}



# tp <gracz> <x> <y> <z> - teleport pod dowolne współrzędne.
# Wszystkie trzy współrzędne są wymagane, żeby nazwa jednoznacznie
# odpowiadała działaniu (w przeciwieństwie do dawnego dom z opcjonalnymi
# argumentami, które potrafiły zaskoczyć).

tp() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    local x="$2"
    local y="$3"
    local z="$4"

    if [[ -z "$x" || -z "$y" || -z "$z" ]]; then

        echo "
Użycie:

tp gracz1 100 70 200
tp g1 100 70 200        (skrót gracza też działa)

"

        return 1
    fi


    rcon "tp $nick $x $y $z"


    echo -e "${GREEN}$1 teleportowany na $x $y $z.${NC}"

}


# dolacz <gracz> <do_gracza> - teleportuje pierwszego gracza
# bezpośrednio do drugiego (wykorzystuje wbudowaną obsługę /tp
# z celem-graczem, więc nie trzeba znać/podawać współrzędnych).
# Działa w obie strony - zamień kolejność argumentów.

dolacz() {

    mc_check || return 1

    if [[ -z "$1" || -z "$2" ]]; then

        echo "
Użycie:

dolacz <gracz> <do_gracza>

Przykłady:

dolacz g2 g1        (teleportuje gracza2 do gracza1)
dolacz g1 g2        (teleportuje gracza1 do gracza2)

"
        return 1
    fi

    local nick1
    nick1=$(gracz_nick "$1") || {

        echo -e "${RED}Nieznany gracz.${NC}"
        gracz_lista
        return 1
    }

    local nick2
    nick2=$(gracz_nick "$2") || {

        echo -e "${RED}Nieznany gracz.${NC}"
        gracz_lista
        return 1
    }

    if [[ "$nick1" == "$nick2" ]]; then

        echo -e "${YELLOW}To ten sam gracz.${NC}"
        return 1
    fi

    rcon "tp $nick1 $nick2"

    echo -e "${GREEN}$1 teleportowany do $2.${NC}"
}


# ==================================================
# PEŁNE WYPOSAŻENIE
# ==================================================
#
# wyposaz <gracz> - daje pełny netherytowy zestaw (broń + zbroja),
# zaklina wszystko na maksymalnych rozsądnych poziomach, i sam
# umieszcza każdą rzecz w odpowiednim miejscu (zbroja na graczu,
# tarcza w drugiej ręce, reszta w plecaku) - bez ręcznego
# przekładania. Wykorzystuje ten sam mechanizm co encik
# (/item replace + /enchant), plus dodatkowy krok przenoszący
# przedmiot z ręki do docelowego slotu.
#
# UWAGA: nadpisuje zawartość slotów docelowych (inventory.0-4,
# armor.*, weapon.offhand) - jeśli gracz ma tam coś wartościowego,
# zostanie zastąpione.

# Format wpisu: "klucz_polski|docelowy_slot|zaklecie1:poziom zaklecie2:poziom ..."
declare -a WYPOSAZ_ZESTAW=(
    "netherytowy_miecz|inventory.0|sharpness:5 unbreaking:3 mending looting:3 fire_aspect:2 sweeping_edge:3"
    "netherytowa_siekiera|inventory.1|sharpness:5 unbreaking:3 mending"
    "luk|inventory.2|power:5 unbreaking:3 infinity flame"
    "kusza|inventory.3|quick_charge:3 unbreaking:3 mending multishot"
    "tarcza|weapon.offhand|unbreaking:3 mending"
    "netherytowy_helm|armor.head|protection:4 unbreaking:3 mending respiration:3"
    "netherytowy_napiersnik|armor.chest|protection:4 unbreaking:3 mending"
    "netherytowe_nogawice|armor.legs|protection:4 unbreaking:3 mending swift_sneak:3"
    "netherytowe_buty|armor.feet|protection:4 unbreaking:3 mending feather_falling:4"
)

wyposaz() {

    mc_check || return 1

    if [[ -z "$1" ]]; then

        echo "
Użycie:

wyposaz <gracz>

Daje pełny netherytowy zestaw (miecz, siekiera, łuk, kusza, tarcza,
cała zbroja) zaklęty na maksa, i sam wkłada wszystko na swoje miejsce.

UWAGA: nadpisuje zbroję i kilka slotów plecaka (inventory.0-3)!

"
        return 1
    fi

    local nick
    nick=$(gracz_nick "$1") || {

        echo -e "${RED}Nieznany gracz.${NC}"
        gracz_lista
        return 1
    }

    mc_log "wyposaz" "start dla gracza=$1"

    local wpis item reszta slot zaklecia para nazwa poziom mc_item mc_zaklecie

    for wpis in "${WYPOSAZ_ZESTAW[@]}"; do

        item="${wpis%%|*}"
        reszta="${wpis#*|}"
        slot="${reszta%%|*}"
        zaklecia="${reszta#*|}"

        mc_item=$(item_rozwiaz "$item") || {
            echo -e "${RED}Błąd wewnętrzny: nieznany item $item (pomijam).${NC}"
            continue
        }

        rcon "item replace entity $nick weapon.mainhand with minecraft:$mc_item 1"

        for para in $zaklecia; do

            nazwa="${para%%:*}"
            [[ "$para" == *:* ]] && poziom="${para#*:}" || poziom=1

            mc_zaklecie=$(zaklecie_rozwiaz "$nazwa") || {
                echo -e "${RED}Błąd wewnętrzny: nieznane zaklęcie $nazwa (pomijam).${NC}"
                continue
            }

            rcon "enchant $nick minecraft:$mc_zaklecie $poziom"
        done

        rcon "item replace entity $nick $slot from entity $nick weapon.mainhand"

        echo -e "${GREEN}✓ $mc_item -> $slot${NC}"
    done

    mc_log "wyposaz" "koniec dla gracza=$1"

    echo -e "${GREEN}$1 wyposażony w pełny zestaw.${NC}"
}

# ==================================================
# ŚWIAT
# ==================================================

dzien() {

    mc_check || return 1

    rcon "time set day"
    rcon "weather clear"

    echo -e "${GREEN}Ustawiono dzień i dobrą pogodę.${NC}"
}



noc() {

    mc_check || return 1

    rcon "time set night"

    echo -e "${BLUE}Ustawiono noc.${NC}"
}



burza() {

    mc_check || return 1

    rcon "weather thunder"

    echo -e "${YELLOW}Burza rozpoczęta.${NC}"
}



pogoda() {

    mc_check || return 1

    case "${1,,}" in

        clear|czysto)
            rcon "weather clear"
            echo -e "${GREEN}Czysta pogoda.${NC}"
            ;;

        rain|deszcz)
            rcon "weather rain"
            echo -e "${BLUE}Deszcz.${NC}"
            ;;

        thunder|burza)
            rcon "weather thunder"
            echo -e "${YELLOW}Burza.${NC}"
            ;;

        *)
            echo "
Użycie:

pogoda czysto
pogoda deszcz
pogoda burza

"
            ;;
    esac
}



# ==================================================
# GRACZE - ADMIN
# ==================================================

zdrowie() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    rcon "effect give $nick instant_health 1 255 true"
    rcon "effect give $nick saturation 1 255 true"


    echo -e "${GREEN}$1 został uleczony.${NC}"
}



zamroz() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    rcon "effect give $nick slowness 999 255 true"
    rcon "effect give $nick jump_boost 999 250 true"


    echo -e "${YELLOW}$1 został zamrożony.${NC}"

}



odmroz() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    rcon "effect clear $nick"


    echo -e "${GREEN}$1 został odmrożony.${NC}"

}



kick() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || {

        gracz_lista
        return 1
    }


    rcon "kick $nick ${2:-Zostałeś wyrzucony przez admina}"


    echo -e "${RED}$1 wyrzucony z serwera.${NC}"

}



# ==================================================
# ZABAWA
# ==================================================

grzmot() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || return 1


    rcon "execute at $nick run summon lightning_bolt"


    echo -e "${YELLOW}Piorun dla $1.${NC}"

}



wybuch() {

    mc_check || return 1

    local nick
    nick=$(gracz_nick "$1") || return 1


    rcon "execute at $nick run summon creeper ~ ~ ~ {Fuse:0}"


    echo -e "${RED}BOOM dla $1.${NC}"

}



# ==================================================
# SERWER
# ==================================================

online() {

    mc_check || return 1

    rcon "list"

}



restartmc() {

    echo -e "${YELLOW}Restart Minecraft...${NC}"

    mc_log "restartmc" "restart kontenera $MC_CONTAINER"

    docker restart "$MC_CONTAINER"


    echo -e "${GREEN}Restart zakończony.${NC}"
}

# ==================================================
# SYSTEM EFEKTÓW
# ==================================================

declare -A EFEKTY=(

    # pozytywne
    [szybkosc]="speed"
    [sila]="strength"
    [kopanie]="haste"
    [regeneracja]="regeneration"
    [odpornosc]="resistance"
    [ognioodpornosc]="fire_resistance"
    [oddychanie]="water_breathing"
    [niewidzialnosc]="invisibility"
    [widzenie]="night_vision"
    [skok]="jump_boost"
    [serca]="health_boost"
    [tarcza]="absorption"
    [najedzenie]="saturation"
    [swiecenie]="glowing"
    [lewitacja]="levitation"
    [szczescie]="luck"
    [powolny_upadek]="slow_falling"
    [konduit]="conduit_power"
    [delfin]="dolphins_grace"
    [bohater]="hero_of_the_village"

    # negatywne
    [spowolnienie]="slowness"
    [zmeczenie]="mining_fatigue"
    [mdlosci]="nausea"
    [slepota]="blindness"
    [glod]="hunger"
    [slabosc]="weakness"
    [trucizna]="poison"
    [wither]="wither"
    [ciemnosc]="darkness"

    # 1.21+
    [zly_omen]="bad_omen"
    [trial_omen]="trial_omen"
    [raid_omen]="raid_omen"
    [wiatr]="wind_charged"
    [pajeczyna]="weaving"
    [sluz]="oozing"
    [rybiki]="infested"

)



# ==================================================
# OPISY EFEKTÓW
# ==================================================

declare -A OPISY=(

[szybkosc]="szybsze bieganie"
[spowolnienie]="wolniejsze chodzenie"
[sila]="mocniejsze ataki"
[kopanie]="szybsze kopanie"
[zmeczenie]="wolniejsze kopanie"

[regeneracja]="odnawia życie"
[odpornosc]="mniejsze obrażenia"
[ognioodpornosc]="odporność na ogień i lawę"
[oddychanie]="oddychanie pod wodą"

[niewidzialnosc]="gracz znika"
[widzenie]="widzenie w ciemności"
[slepota]="brak widzenia"

[skok]="wyższe skoki"
[lewitacja]="unosi gracza"

[glod]="szybszy spadek głodu"
[slabosc]="mniejsze obrażenia"
[trucizna]="zabiera życie"
[wither]="efekt Withera"

[serca]="dodatkowe serca"
[tarcza]="złote serca"

[swiecenie]="widoczny przez ściany"
[szczescie]="lepszy loot"
[powolny_upadek]="wolne spadanie"

[konduit]="moc pod wodą"
[delfin]="szybsze pływanie"

[bohater]="zniżki u wieśniaków"

[ciemnosc]="ciemny ekran"

[zly_omen]="najazd"
[trial_omen]="trial omen"
[raid_omen]="raid omen"

[wiatr]="wybuch wiatru"
[pajeczyna]="pajęczyny"
[sluz]="śluzy"
[rybiki]="rybiki"

)



# ==================================================
# LISTA EFEKTÓW
# ==================================================

efekt_lista() {


echo "
==============================
      DOSTĘPNE EFEKTY
==============================
"


for efekt in "${!EFEKTY[@]}"
do

    printf "%-18s - %s\n" \
    "$efekt" "${OPISY[$efekt]}"

done


echo "
Użycie:

efekt gracz1 sila 60
efekt gracz2 slepota 10

Leczenie:

efekt gracz1 leczenie

"

}



# ==================================================
# DODAWANIE EFEKTU
# ==================================================

efekt() {

    mc_check || return 1


    if [[ "$1" == "co" || "$1" == "lista" ]]; then

        efekt_lista
        return

    fi



    local gracz="$1"
    local nazwa="$2"
    local czas="${3:-30}"



    local nick
    nick=$(gracz_nick "$gracz") || {

        echo "Użycie:"
        echo "efekt gracz1 sila 30"
        echo "Lista: efekt co"

        return 1
    }



    # specjalne leczenie

    if [[ "$nazwa" == "leczenie" ]]; then


        rcon "effect give $nick instant_health 1 255 true"
        rcon "effect give $nick saturation 1 255 true"


        echo -e "${GREEN}$gracz uleczony.${NC}"

        return

    fi



    local mc_efekt="${EFEKTY[$nazwa]}"



    if [[ -z "$mc_efekt" ]]; then

        echo -e "${RED}Nie ma takiego efektu.${NC}"
        echo "Wpisz: efekt co"

        return 1

    fi



    rcon "effect give $nick minecraft:$mc_efekt $czas 1 true"


    echo -e "${GREEN}Dodano $nazwa dla $gracz na ${czas}s.${NC}"

}



# ==================================================
# USUWANIE EFEKTÓW
# ==================================================

wyczysc() {

    mc_check || return 1


    local nick
    nick=$(gracz_nick "$1") || return 1


    rcon "effect clear $nick"


    echo -e "${GREEN}Usunięto wszystkie efekty $1.${NC}"

}



usun() {

    mc_check || return 1


    local nick
    nick=$(gracz_nick "$1") || return 1


    local efekt="${EFEKTY[$2]}"


    if [[ -z "$efekt" ]]; then

        echo "Nie ma takiego efektu."
        echo "Lista: efekt co"

        return 1
    fi



    rcon "effect clear $nick $efekt"


    echo -e "${GREEN}Usunięto $2 z $1.${NC}"

}

# ==================================================
# POMOC
# ==================================================

nik() {

echo "
==================================================
         Naczelny Inspektorat Kreeperowy
==================================================

👤 GRACZE
  gracz_lista                    lista graczy (i skrótów z konfiguracji)
  zdrowie <gracz>                pełne leczenie + głód
  zamroz <gracz>                 zamraża
  odmroz <gracz>                 odmraża
  kick <gracz> [powód]           wyrzuca z serwera

🎒 ITEMY
  daj <gracz> <item> [ilość]     daje przedmiot (bez ilości = 1 szt.)
  szukaj <fraza>                 szuka przedmiotu po nazwie PL/EN
  przedmioty                     cała lista PL -> EN (1384 poz.)
                                  np: daj g1 rozdymka  |  daj g1 diamond 64

  encik <gracz> <item> <zakl[:poz]>...     daje przedmiot z 1+ zaklęciami
  encik co                       lista wszystkich zaklęć z opisami
                                  np: encik g2 tarcza unbreaking:3

  wyposaz <gracz>                pełny netherytowy zestaw broni + zbroja naraz

📍 TELEPORTY
  dom <gracz>                    teleport do domu (stałe współrzędne)
  zamek <gracz>                  teleport do zamku
  tp <gracz> <x> <y> <z>         teleport pod dowolne współrzędne
  dolacz <gracz> <do_gracza>     teleportuje jednego gracza do drugiego

🌍 ŚWIAT
  dzien / noc / burza            ustawia porę dnia / burzę
  pogoda <czysto|deszcz|burza>   ustawia pogodę

⚡ EFEKTY
  efekt co                       lista wszystkich efektów
  efekt <gracz> <nazwa> [s]      dodaje efekt (domyślnie 30s)
  efekt <gracz> leczenie         szybkie uleczenie
  wyczysc <gracz>                usuwa wszystkie efekty
  usun <gracz> <efekt>           usuwa jeden efekt
                                  np: efekt g1 sila 60  |  usun g1 sila

💥 ZABAWA
  grzmot <gracz>                 piorun
  wybuch <gracz>                 creeper boom

💾 SERWER
  zapisz                         zapisuje świat
  online                         gracze online
  restartmc                      restart kontenera
  Log komend: $MC_LOG  (auto-czyszczony po ${MC_LOG_DNI} dniach)

--------------------------------------------------
Skróty graczy: według nik.local.sh   •   Tab-completion działa dla wszystkich komend
==================================================
"

}



# ==================================================
# SZYBKIE ALIASY
# ==================================================

alias zapiszswiat='zapisz'
alias listaefektow='efekt co'
alias gracze='online'


# ==================================================
# BASH COMPLETION
# ==================================================
#
# Jedna uniwersalna funkcja obsługująca Tab-completion
# dla wszystkich komend skryptu. Podpowiedzi graczy,
# przedmiotów i efektów pobierane są bezpośrednio z tablic
# MC_GRACZE / PRZEDMIOTY / EFEKTY, więc zawsze są aktualne -
# nie trzeba niczego ręcznie synchronizować.

_mc_completion() {

    local cur cmd

    cur="${COMP_WORDS[COMP_CWORD]}"
    cmd="${COMP_WORDS[0]}"

    case "$cmd" in

        # gracz jako 1. argument, przedmiot jako 2.
        daj)
            case "$COMP_CWORD" in
                1) COMPREPLY=($(compgen -W "${MC_GRACZE[*]} ${MC_GRACZE_SKROTY[*]}" -- "$cur")) ;;
                2) COMPREPLY=($(_mc_szukaj_substring "$cur" "${!PRZEDMIOTY[@]}")) ;;
            esac
            ;;

        # tylko gracz jako 1. argument
        zdrowie|zamroz|odmroz|kick|dom|zamek|tp|grzmot|wybuch|wyczysc|wyposaz)
            if [[ "$COMP_CWORD" -eq 1 ]]; then
                COMPREPLY=($(compgen -W "${MC_GRACZE[*]} ${MC_GRACZE_SKROTY[*]}" -- "$cur"))
            fi
            ;;

        # gracz na obu pozycjach (1. i 2.)
        dolacz)
            if [[ "$COMP_CWORD" -eq 1 || "$COMP_CWORD" -eq 2 ]]; then
                COMPREPLY=($(compgen -W "${MC_GRACZE[*]} ${MC_GRACZE_SKROTY[*]}" -- "$cur"))
            fi
            ;;

        # gracz jako 1., nazwa efektu jako 2.
        efekt)
            case "$COMP_CWORD" in
                1) COMPREPLY=($(compgen -W "${MC_GRACZE[*]} ${MC_GRACZE_SKROTY[*]} co lista" -- "$cur")) ;;
                2) COMPREPLY=($(_mc_szukaj_substring "$cur" "${!EFEKTY[@]}" "leczenie")) ;;
            esac
            ;;

        # gracz jako 1., nazwa efektu jako 2. (bez czasu)
        usun)
            case "$COMP_CWORD" in
                1) COMPREPLY=($(compgen -W "${MC_GRACZE[*]} ${MC_GRACZE_SKROTY[*]}" -- "$cur")) ;;
                2) COMPREPLY=($(_mc_szukaj_substring "$cur" "${!EFEKTY[@]}")) ;;
            esac
            ;;

        # gracz jako 1., przedmiot jako 2., dowolna liczba zaklęć od 3 w górę
        encik)
            case "$COMP_CWORD" in
                1) COMPREPLY=($(compgen -W "${MC_GRACZE[*]} ${MC_GRACZE_SKROTY[*]} co lista" -- "$cur")) ;;
                2) COMPREPLY=($(_mc_szukaj_substring "$cur" "${!PRZEDMIOTY[@]}")) ;;
                *) COMPREPLY=($(_mc_szukaj_substring "$cur" "${!ZAKLECIA_OPISY[@]}")) ;;
            esac
            ;;

        # wolne wyszukiwanie po słowniku przedmiotów - dopasowanie w dowolnym miejscu nazwy
        szukaj)
            COMPREPLY=($(_mc_szukaj_substring "$cur" "${!PRZEDMIOTY[@]}"))
            ;;

        # opcje pogody (PL i EN)
        pogoda)
            if [[ "$COMP_CWORD" -eq 1 ]]; then
                COMPREPLY=($(compgen -W "czysto deszcz burza clear rain thunder" -- "$cur"))
            fi
            ;;
    esac
}


# Dopasowuje zapytanie do dowolnego miejsca w nazwie (nie tylko prefiksu).
# Potrzebne bo polskie nazwy przedmiotów/efektów zwykle mają przymiotnik
# na początku (np. "diamentowy_kilof") - wpisanie "kilof" musi je znaleźć,
# a zwykłe compgen -W dopasowuje tylko od początku słowa.
_mc_szukaj_substring() {

    local cur="${1,,}"
    shift

    local k
    for k in "$@"; do
        [[ "$k" == *"$cur"* ]] && echo "$k"
    done
}


complete -F _mc_completion \
    daj zdrowie zamroz odmroz kick dom zamek tp dolacz grzmot wybuch \
    wyczysc efekt usun encik szukaj pogoda wyposaz



# ==================================================
# BANER POWITALNY
# ==================================================
#
# Wyświetlany raz przy source'owaniu (czyli przy każdym
# logowaniu, jeśli sourcujesz w .bashrc). Pokazuje stan Minecrafta.

mc_baner() {

    local mc_stan mc_kolor mc_gracze

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${MC_CONTAINER}$"; then
        mc_stan="działa"
        mc_kolor="$GREEN"

        mc_gracze=$(timeout 2 docker exec "$MC_CONTAINER" rcon-cli list 2>/dev/null \
            | grep -oE 'online:.*' | sed 's/^online:[[:space:]]*//')
    else
        mc_stan="nie działa"
        mc_kolor="$RED"
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}      NACZELNY INSPEKTORAT KREEPEROWY       ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"

    printf "  %-12s ${mc_kolor}%s${NC}\n" "Minecraft:" "$mc_stan"
    [[ -n "$mc_gracze" ]] && printf "  %-12s %s\n" "Gracze:" "$mc_gracze"

    printf "  %-12s %s\n" "Log:" "$MC_LOG"

    echo ""
    echo -e "  Wpisz: ${YELLOW}nik${NC}"
    echo ""
}


# ==================================================
# KONIEC
# ==================================================

mc_log_rotacja

mc_baner
