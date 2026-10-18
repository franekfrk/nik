# Konfiguracja demonstracyjna, bez prywatnych danych.
# cp nik.local.example.sh nik.local.sh
# Edytuj nik.local.sh, następnie: source nik.sh
# Wymagania: Bash >= 4, Docker oraz rcon-cli w kontenerze Minecraft.
# Hasło RCON skonfiguruj w kontenerze, nie w tym repozytorium.
MC_CONTAINER="minecraft"
MC_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nik/nik.log"
MC_LOG_DNI=30

MC_GRACZE=(gracz1 gracz2)
MC_GRACZE_SKROTY=([gracz1]="g1" [gracz2]="g2")
MC_GRACZE_NICKI=([gracz1]="PlayerOne" [gracz2]="PlayerTwo")

# Uzupełnij lokalnie; puste wartości blokują teleport do stałego miejsca.
MC_DOM_X=""
MC_DOM_Y=""
MC_DOM_Z=""
MC_ZAMEK_X=""
MC_ZAMEK_Y=""
MC_ZAMEK_Z=""
