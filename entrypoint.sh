#!/usr/bin/env bash
# Runtime work: install/update the game onto the volume, then launch via Proton.
# Built for FAST boot — validation runs once on first install, then is skipped on every
# boot after, so a config-change restart is just the map load (not a 30GB recheck).
# Runs as the unprivileged 'container' user provided by the steamcmd:proton base.
set -euo pipefail

: "${ARK_DIR:=/home/container/arkserver}"
: "${ASA_APPID:=2430930}"
: "${SERVER_MAP:=TheIsland_WP}"
: "${SESSION_NAME:=ARK-Test}"          # avoid spaces for the test server; quote if you must
: "${SERVER_PORT:=7777}"
: "${RCON_PORT:=27020}"
: "${MAX_PLAYERS:=10}"
: "${ARK_ADMIN_PASSWORD:=changeme}"
: "${SERVER_PASSWORD:=}"
: "${MODS:=}"                          # comma-separated CurseForge mod IDs, e.g. 928988
: "${UPDATE_ON_BOOT:=0}"              # 1 = check for an ASA update this boot (slower)
: "${SAVE_ON_STOP:=1}"               # 1 = RCON SaveWorld on stop; 0 = instant kill (test loops)
: "${ENABLE_BATTLEYE:=0}"            # 1 = BattlEye anti-cheat ON (prod PvP); 0 = off (testing)

INSTALL_MARKER="${ARK_DIR}/.installed"
LOG_FILE="${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
SERVER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"

install_or_update() {
  if [[ ! -f "$INSTALL_MARKER" ]]; then
    echo "[entrypoint] First run — full install + validate (one-time, this IS slow)…"
    "${STEAMCMD_DIR}/steamcmd.sh" +force_install_dir "${ARK_DIR}" \
      +login anonymous +app_update "${ASA_APPID}" validate +quit
    # shed ~6GB we never need on a headless server (re-pulled only on a future validate)
    rm -rf "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" \
           "${ARK_DIR}/ShooterGame/Content/Movies/"
    touch "$INSTALL_MARKER"
  elif [[ "$UPDATE_ON_BOOT" == "1" ]]; then
    echo "[entrypoint] UPDATE_ON_BOOT=1 — delta update, no validate…"
    "${STEAMCMD_DIR}/steamcmd.sh" +force_install_dir "${ARK_DIR}" \
      +login anonymous +app_update "${ASA_APPID}" +quit
  else
    echo "[entrypoint] Fast boot — skipping Steam (set UPDATE_ON_BOOT=1 to update)."
  fi
}

main() {
  export HOME="${HOME:-/home/container}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}" "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" \
           "$(dirname "$LOG_FILE")" "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  install_or_update
  : > "$LOG_FILE"

  echo "[entrypoint] vm.max_map_count = $(cat /proc/sys/vm/max_map_count) (ASA needs >= 262144)"

  # The whole map?listen?opt?opt string is ONE argv to the exe → keep it quoted.
  # The -flags are separate argv → unquoted so they word-split.
  local query="${SERVER_MAP}?listen?SessionName=${SESSION_NAME}?Port=${SERVER_PORT}?MaxPlayers=${MAX_PLAYERS}?RCONEnabled=True?RCONPort=${RCON_PORT}?ServerAdminPassword=${ARK_ADMIN_PASSWORD}"
  [[ -n "$SERVER_PASSWORD" ]] && query="${query}?ServerPassword=${SERVER_PASSWORD}"

  local flags="-log -WinLiveMaxPlayers=${MAX_PLAYERS}"
  if [[ "$ENABLE_BATTLEYE" == "1" ]]; then flags="${flags} -BattlEye"; else flags="${flags} -NoBattlEye"; fi
  [[ -n "$MODS" ]] && flags="${flags} -mods=${MODS}"

  echo "[entrypoint] Launching ${SERVER_MAP} on :${SERVER_PORT} (rcon :${RCON_PORT})"
  # WINEDEBUG comes from the container env (compose). -all = clean; +err,+seh to debug.
  proton run "${SERVER_EXE}" "${query}" ${flags} 2>&1 &
  local server_pid=$!

  # Stream the game log to container stdout → visible in `docker compose up`.
  tail -F "$LOG_FILE" &
  local tail_pid=$!

  stop() {
    echo "[entrypoint] stopping…"
    if [[ "$SAVE_ON_STOP" == "1" ]]; then
      rcon -a "127.0.0.1:${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" "SaveWorld" 2>/dev/null || true
    fi
    kill "$server_pid" 2>/dev/null || true
  }
  trap stop SIGTERM SIGINT

  wait "$server_pid"
  kill "$tail_pid" 2>/dev/null || true
}

main "$@"
