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
  # ASA's server (app 2430930) ships a Windows-only depot — no Linux build exists. SteamCMD on
  # Linux defaults to the Linux platform and fails with "Missing configuration" for this app, so
  # force the Windows platform BEFORE +login. The game then runs under Proton/Wine.
  local force_windows="+@sSteamCmdForcePlatformType windows"
  if [[ ! -f "$INSTALL_MARKER" ]]; then
    echo "[entrypoint] First run — full install + validate (one-time, this IS slow)…"
    "${STEAMCMD_DIR}/steamcmd.sh" ${force_windows} +force_install_dir "${ARK_DIR}" \
      +login anonymous +app_update "${ASA_APPID}" validate +quit
    # steamcmd exits 0 even when app_update fails (its well-known footgun), so its exit code
    # can't gate the marker. Verify the server binary actually landed — otherwise a partial
    # download would set the marker, fast-boot would skip repair, and the server would crash.
    if [[ ! -f "$SERVER_EXE" ]]; then
      echo "[entrypoint] FATAL: install finished but ${SERVER_EXE} is missing — install incomplete." >&2
      exit 1
    fi
    # shed ~6GB we never need on a headless server (re-pulled only on a future validate)
    rm -rf "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" \
           "${ARK_DIR}/ShooterGame/Content/Movies/"
    touch "$INSTALL_MARKER"
  elif [[ "$UPDATE_ON_BOOT" == "1" ]]; then
    echo "[entrypoint] UPDATE_ON_BOOT=1 — delta update, no validate…"
    "${STEAMCMD_DIR}/steamcmd.sh" ${force_windows} +force_install_dir "${ARK_DIR}" \
      +login anonymous +app_update "${ASA_APPID}" +quit
  else
    echo "[entrypoint] Fast boot — skipping Steam (set UPDATE_ON_BOOT=1 to update)."
  fi
}

deploy_plugins() {
  # Sync the image-baked AsaApi + plugin binaries onto the volume's Win64 tree.
  # The game installs at runtime (install_or_update above), so we can't COPY during the
  # build — the image is the version source-of-truth; this sync makes it so on the volume.
  #
  # Clean-replace strategy: stash operator-edited config.json files from ArkApi/Plugins/*/,
  # remove the AsaApi-owned paths (so stale binaries from a prior version can't linger),
  # copy fresh from the image, then restore the saved configs. Paths not owned by AsaApi
  # (everything else in Win64) are never touched. Config files that didn't exist before
  # are seeded from the image defaults (seed-if-absent).
  #
  # Time: O(n)  Space: O(n) where n = plugin count (2-5 in practice)
  local win64="${ARK_DIR}/ShooterGame/Binaries/Win64"
  local src="/opt/asaapi"
  local cfg_stash
  cfg_stash="$(mktemp -d)"

  echo "[entrypoint] Deploying AsaApi + plugins from image to volume…"

  # Stash any operator-edited plugin config.json files before we wipe the tree.
  # We only stash files that already exist on the volume — new plugins get the image default.
  if [[ -d "${win64}/ArkApi/Plugins" ]]; then
    for cfg in "${win64}/ArkApi/Plugins"/*/config.json; do
      [[ -f "${cfg}" ]] || continue
      local plugin_name
      plugin_name="$(basename "$(dirname "${cfg}")")"
      cp "${cfg}" "${cfg_stash}/${plugin_name}_config.json"
    done
  fi

  # Remove AsaApi-owned paths. ArkApi/ holds the framework DLL + all plugins. The
  # root-level DLLs and loader are listed explicitly to avoid touching game-owned files.
  rm -rf "${win64}/ArkApi" \
         "${win64}/AsaApiLoader.exe" \
         "${win64}/AsaApiLoader.pdb" \
         "${win64}/msdia140.dll" \
         "${win64}/libcrypto-3-x64.dll" \
         "${win64}/libssl-3-x64.dll" \
         "${win64}/msvcp140.dll"

  # Copy the full ArkApi tree (framework DLL + all plugin dirs with their default configs).
  cp -r "${src}/ArkApi" "${win64}/"

  # Copy root-level binaries and runtime DLLs.
  cp "${src}/AsaApiLoader.exe" \
     "${src}/msdia140.dll" \
     "${src}/libcrypto-3-x64.dll" \
     "${src}/libssl-3-x64.dll" \
     "${src}/msvcp140.dll" \
     "${win64}/"

  # Restore stashed operator configs, overwriting the image defaults.
  # A plugin dir that existed before gets its operator config back; a new plugin dir
  # (first boot or new plugin added) keeps the image default (seed-if-absent satisfied).
  for stashed in "${cfg_stash}"/*_config.json; do
    [[ -f "${stashed}" ]] || continue
    local plugin_name
    plugin_name="${stashed##*/}"
    plugin_name="${plugin_name%_config.json}"
    local target="${win64}/ArkApi/Plugins/${plugin_name}/config.json"
    if [[ -d "${win64}/ArkApi/Plugins/${plugin_name}" ]]; then
      cp "${stashed}" "${target}"
    fi
  done
  rm -rf "${cfg_stash}"

  # Seed the AsaApi framework config.json only if absent — never overwrite, so operator/injector edits survive restarts.
  local asaapi_cfg="${win64}/config.json"
  if [[ ! -f "${asaapi_cfg}" ]]; then
    cp "${src}/config.json" "${asaapi_cfg}"
  fi

  echo "[entrypoint] AsaApi deploy done — $(ls "${win64}/ArkApi/Plugins/" 2>/dev/null | tr '\n' ' ')"
}

main() {
  export HOME="${HOME:-/home/container}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}" "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" \
           "$(dirname "$LOG_FILE")" "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  # Link the engine's config path to the host bind mount (/home/container/config).
  # The bind is shallow (see docker-compose.yml) so the volume tree stays owned by this
  # non-root user; we create the dir chain here and symlink WindowsServer at the host mount.
  # Edit ./config/*.ini on the host → restart → ASA reads through the link.
  local config_link="${ARK_DIR}/ShooterGame/Saved/Config/WindowsServer"
  mkdir -p "$(dirname "$config_link")"
  rm -rf "$config_link"
  ln -sfn /home/container/config "$config_link"

  # Proton's lsteamclient loads the native Steam client from ~/.steam/sdk{64,32}/steamclient.so;
  # without it the server asserts in steamclient_main.c and aborts (exit 21). The .so is baked
  # into the image (see Dockerfile); ~/.steam is ephemeral (not on the volume), so relink each boot.
  : "${STEAMCMD_DIR:=/opt/steamcmd}"
  mkdir -p "${HOME}/.steam/sdk64" "${HOME}/.steam/sdk32"
  ln -sf "${STEAMCMD_DIR}/linux64/steamclient.so" "${HOME}/.steam/sdk64/steamclient.so"
  ln -sf "${STEAMCMD_DIR}/linux32/steamclient.so" "${HOME}/.steam/sdk32/steamclient.so"

  install_or_update
  deploy_plugins
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
