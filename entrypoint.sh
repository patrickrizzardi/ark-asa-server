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
# ArkShop DB connection. NAME/USER/PASS fall back to their MARIADB_* peers (the same vars the
# mariadb service is created from), so the common compose setup works with no ARKSHOP_DB_*
# overrides. HOST/PORT have no MARIADB_* peer — the DB is always reached at the internal compose
# service `mariadb:3306` — so they default to literals; override ARKSHOP_DB_HOST/PORT only for an
# external DB. Only used when ENABLE_ASAAPI=1; ignored on the vanilla (ENABLE_ASAAPI=0) path.
ARKSHOP_DB_HOST="${ARKSHOP_DB_HOST:-mariadb}"
ARKSHOP_DB_PORT="${ARKSHOP_DB_PORT:-3306}"
ARKSHOP_DB_NAME="${ARKSHOP_DB_NAME:-${MARIADB_DATABASE:-arkshop}}"
ARKSHOP_DB_USER="${ARKSHOP_DB_USER:-${MARIADB_USER:-arkshop}}"
ARKSHOP_DB_PASS="${ARKSHOP_DB_PASS:-${MARIADB_PASSWORD:-}}"
: "${UPDATE_ON_BOOT:=0}"              # 1 = check for an ASA update this boot (slower)
: "${SAVE_ON_STOP:=1}"               # 1 = RCON SaveWorld on stop; 0 = instant kill (test loops)
: "${ENABLE_BATTLEYE:=0}"            # 1 = BattlEye anti-cheat ON (prod PvP); 0 = off (testing)
: "${ENABLE_ASAAPI:=1}"             # 1 = launch via AsaApiLoader (modded); 0 = vanilla ArkAscendedServer (M1 rollback)

INSTALL_MARKER="${ARK_DIR}/.installed"
LOG_FILE="${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log"
SERVER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
LOADER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"

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
    # Shed assets a headless server never needs. Movies/ is the intro videos a headless server never plays.
    # ArkAscendedServer.pdb (~6GB): kept on a fresh modded install, shed on a fresh vanilla install.
    # A volume first-installed as vanilla (pdb absent) that later flips to ENABLE_ASAAPI=1 is
    # handled by ensure_modded_pdb() at the launch gate — it restores the pdb via steamcmd validate
    # without requiring a manual intervention or a full reinstall.
    rm -rf "${ARK_DIR}/ShooterGame/Content/Movies/"
    if [[ "${ENABLE_ASAAPI}" != "1" ]]; then
      rm -rf "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
    fi
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

  # Derive the AsaApi-owned root-artifact set from the image tree (single source of truth):
  # every top-level /opt/asaapi entry EXCEPT ArkApi/ (the subtree, copied whole below) and
  # config.json (the framework config, seed-if-absent below). Deriving it — rather than hand-
  # listing the loader + DLLs in both an rm-list and a cp-list — means a pinned-version bump that
  # adds or drops a root DLL is picked up automatically, with no list to keep in lockstep with the
  # Dockerfile bake. The entrypoint now follows whatever the image ships; the two can't drift.
  local root_artifacts=() entry base
  for entry in "${src}"/*; do
    base="$(basename "${entry}")"
    [[ "${base}" == "ArkApi" || "${base}" == "config.json" ]] && continue
    root_artifacts+=("${base}")
  done

  # Remove AsaApi-owned paths (the ArkApi tree + the derived root artifacts) so stale binaries
  # from a prior version can't linger. Only AsaApi-owned names are touched — game files are safe.
  local artifact
  rm -rf "${win64}/ArkApi"
  for artifact in "${root_artifacts[@]}"; do
    rm -f "${win64}/${artifact}"
  done

  # Copy fresh from the image: the full ArkApi tree (framework DLL + plugin dirs with their
  # default configs) plus each derived root artifact (loader exe + runtime DLLs).
  cp -r "${src}/ArkApi" "${win64}/"
  for artifact in "${root_artifacts[@]}"; do
    cp "${src}/${artifact}" "${win64}/"
  done

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

install_vcredist() {
  # The VC++ 2019 runtime is required by AsaApiLoader. The Proton Wine prefix lives on the
  # ark-game volume and is created at runtime, so the redist cannot be installed at image-build
  # time. The installer is baked in /opt/vcredist/ (immutable); this function installs it into
  # the volume prefix on first boot and is a no-op on every boot after.
  #
  # Skip gate: check for the three runtime DLLs directly in the prefix system32 rather than
  # relying on a bare marker file. A marker-only gate would falsely skip after a pfx/ reset
  # (e.g. prefix nuked and recreated), leaving AsaApi unable to load. DLL presence is the
  # source of truth; the optional .vcredist-installed marker is a fast-path hint only.
  #
  # Time: O(1)  Space: O(1)  — missing[] bounded to 3 elements (constant)
  # Side effects: writes VC++ DLLs into ${STEAM_COMPAT_DATA_PATH}/pfx/ on the volume.
  #               Writes .vcredist-installed marker to the volume dir.
  local pfx_sys32="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32"
  local marker="${STEAM_COMPAT_DATA_PATH}/.vcredist-installed"

  local msvcp="${pfx_sys32}/msvcp140.dll"
  local vcrt="${pfx_sys32}/vcruntime140.dll"
  local vcrt1="${pfx_sys32}/vcruntime140_1.dll"

  # Fast-path: marker present AND all three DLLs still exist → skip without a filesystem walk.
  if [[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then
    echo "[entrypoint] VC++ 2019 redist already installed — skipping."
    return 0
  fi

  echo "[entrypoint] Installing VC++ 2019 redist into Proton prefix…"
  # Capture the installer's exit code rather than letting set -e abort on it.
  # The VC++ installer returns benign non-zero codes on success: 3010 (reboot suppressed)
  # and 1638 (another version already installed) are both normal. The DLL-presence check
  # below is the sole success/failure arbiter — same discipline as the steamcmd .installed
  # marker above. Log the rc if non-zero so it is visible in the boot log.
  local rc=0
  proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    echo "[entrypoint] VC++ installer exited with rc=${rc} (3010/1638 are benign — DLL check is the arbiter)."
  fi

  # Verify the three runtime DLLs actually landed in the prefix; the rc above is not trusted.
  local missing=()
  [[ -f "${msvcp}"  ]] || missing+=("msvcp140.dll")
  [[ -f "${vcrt}"   ]] || missing+=("vcruntime140.dll")
  [[ -f "${vcrt1}"  ]] || missing+=("vcruntime140_1.dll")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[entrypoint] FATAL: VC++ install finished but the following DLLs are missing from the prefix:" >&2
    printf "  %s\n" "${missing[@]}" >&2
    echo "  Expected in: ${pfx_sys32}" >&2
    exit 1
  fi

  touch "${marker}"
  echo "[entrypoint] VC++ 2019 redist installed — msvcp140, vcruntime140, vcruntime140_1 verified in prefix."
}

ensure_modded_pdb() {
  # AsaApi SHA-256s ArkAscendedServer.pdb to derive its symbol-offset cache key. Without the pdb
  # it logs "[critical] Failed to read pdb" and loads ZERO plugins — the server still starts and
  # reports success, making this a silent failure. The install-time shed (above) covers fresh
  # vanilla installs; this function covers the vanilla→modded flip: a volume first-installed with
  # ENABLE_ASAAPI=0 sheds the pdb and writes .installed, so subsequent boots with ENABLE_ASAAPI=1
  # skip install_or_update entirely and would launch into the silent failure without this gate.
  #
  # Flow:
  #   1. Return early if the pdb is already present and non-trivially-sized (common path on a modded volume)
  #   2. Attempt steamcmd validate (up to 3 times) to restore the pdb; break on a valid artifact
  #   3. Verify the pdb is present and non-trivially-sized — trust the artifact, not steamcmd's exit code
  #   4. Fatal-exit if still missing after all attempts
  #
  # Time: O(1) compute, up to 3 steamcmd validate calls (I/O-dominated)  Space: O(1)
  #
  # Side effects: may write ~6GB pdb file onto the ark-game volume.
  local pdb="${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
  local force_windows="+@sSteamCmdForcePlatformType windows"

  # A bare -f test passes a 0-byte or truncated pdb (e.g. steamcmd exhausted disk mid-download),
  # which AsaApi then fails to SHA-256 — the exact silent-zero-plugin failure this function prevents.
  # The real pdb is ~6GB; require >1 MiB to reject truncated files while never rejecting a real one.
  pdb_ok() { [[ -f "${pdb}" ]] && [[ "$(stat -c%s "${pdb}" 2>/dev/null || echo 0)" -gt 1048576 ]]; }

  if pdb_ok; then
    return 0
  fi

  echo "[entrypoint] ENABLE_ASAAPI=1 but pdb is absent — restoring via steamcmd validate…"

  local attempt
  for attempt in 1 2 3; do
    echo "[entrypoint] steamcmd validate attempt ${attempt}/3…"
    # steamcmd exits 0 even on transient failures ("Timed out waiting for update to start"),
    # so its exit code is not the success gate — the pdb file's presence is.
    "${STEAMCMD_DIR}/steamcmd.sh" ${force_windows} +force_install_dir "${ARK_DIR}" \
      +login anonymous +app_update "${ASA_APPID}" validate +quit || true
    if pdb_ok; then
      echo "[entrypoint] pdb restored on attempt ${attempt}."
      break
    fi
    echo "[entrypoint] pdb still absent after attempt ${attempt}."
  done

  if ! pdb_ok; then
    echo "[entrypoint] FATAL: ArkAscendedServer.pdb is still missing or truncated after 3 steamcmd validate attempts." >&2
    echo "  Expected: ${pdb}" >&2
    echo "  AsaApi cannot load plugins without the pdb. Check Steam CDN reachability or disk space." >&2
    exit 1
  fi
}

setup_plugin_configs() {
  # Bind each plugin's config.json onto the host via ./plugins-config/<PluginName>/config.json so
  # operators can edit configs on the host and pick them up on restart — mirrors the ./config →
  # WindowsServer symlink for engine INI.
  #
  # ONLY the config.json FILE is symlinked, never the whole plugin dir: the deployed plugin dir
  # also holds the plugin DLL (ArkShop.dll etc.) that AsaApi loads, so replacing the dir with a
  # symlink to a config-only host dir would delete the DLL and AsaApi would fail to find the plugin
  # ("Plugin … does not exist"). The DLL + everything else stay in the deploy_plugins()-managed
  # dir; only config.json points at the host bind.
  #
  # Seed-if-absent: if the host has no config.json yet, copy the image default before linking;
  # never overwrite a config the operator already edited.
  #
  # Time: O(p) where p = plugin count (2 in practice — ArkShop + Permissions)  Space: O(1)
  local win64="${ARK_DIR}/ShooterGame/Binaries/Win64"
  local host_root="/home/container/plugins-config"
  mkdir -p "${host_root}"

  local plugin
  for plugin in ArkShop Permissions; do
    local plugin_dir="${win64}/ArkApi/Plugins/${plugin}"
    local host_dir="${host_root}/${plugin}"

    # The plugin dir (with its DLL) must already exist from deploy_plugins(); if it doesn't, the
    # plugin wasn't deployed — skip rather than create a dangling config symlink.
    if [[ ! -d "${plugin_dir}" ]]; then
      echo "[entrypoint] WARN: ${plugin} not deployed (no ${plugin_dir}); skipping config bind." >&2
      continue
    fi
    mkdir -p "${host_dir}"

    # Seed the host config.json from the deployed image default if absent.
    if [[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]; then
      cp "${plugin_dir}/config.json" "${host_dir}/config.json"
      echo "[entrypoint] Seeded ${plugin} config.json from image default."
    fi

    # Symlink ONLY the config.json file → host bind; the DLL and siblings stay in the deployed dir.
    ln -sfn "${host_dir}/config.json" "${plugin_dir}/config.json"
  done

  echo "[entrypoint] Plugin config.json bound to host: $(ls "${host_root}" 2>/dev/null | tr '\n' ' ')"
}

_inject_mysql_block() {
  # Write the DB connection block into one plugin's config.json via jq.
  # jq --arg passes each value as a plain string (not evaluated as a jq filter expression), so
  # special characters in creds are safe. MysqlPort coerces via tonumber so the JSON type stays
  # integer, matching ArkShop's expected schema.
  #
  # The `|| { … exit 1; }` is load-bearing: in `jq … > tmp && mv tmp cfg`, jq sits in a non-final
  # position of an && list, where `set -e` does NOT abort on its failure. Without the explicit
  # exit, a jq failure (e.g. a bad value reaching tonumber) is swallowed and the caller logs a
  # false success against an unwritten config. The handler is the list's final element, so its
  # exit fires unconditionally.
  #
  # Time: O(1)  Space: O(1)   Side effect: rewrites the file ${cfg} resolves to, in place.
  # ${cfg} is a symlink (setup_plugin_configs points plugin_dir/config.json → the host bind), so we
  # resolve it and mv onto the real target — a bare `mv tmp symlink` would REPLACE the symlink with
  # a regular file and orphan the host-bound config the operator edits. Resolving keeps the link.
  local cfg dest
  cfg="$1"
  dest="${cfg}"
  [[ -L "${cfg}" ]] && dest="$(readlink -f "${cfg}")"
  local tmp
  tmp="$(mktemp)"
  jq --arg host "${ARKSHOP_DB_HOST}" \
     --arg user "${ARKSHOP_DB_USER}" \
     --arg pass "${ARKSHOP_DB_PASS}" \
     --arg db   "${ARKSHOP_DB_NAME}" \
     --arg port "${ARKSHOP_DB_PORT}" \
     '.Mysql.UseMysql  = true
    | .Mysql.MysqlHost = $host
    | .Mysql.MysqlUser = $user
    | .Mysql.MysqlPass = $pass
    | .Mysql.MysqlDB   = $db
    | .Mysql.MysqlPort = ($port | tonumber)' \
     "${cfg}" > "${tmp}" || { rm -f "${tmp}"; echo "[entrypoint] FATAL: jq failed to write DB config into ${cfg}." >&2; exit 1; }
  mv "${tmp}" "${dest}"
}

inject_plugin_db_config() {
  # Inject DB connection credentials into the ArkShop (and Permissions) config.json.
  # Credentials come from env vars (ARKSHOP_DB_*), never from a literal in this script. The
  # password is passed to jq as a --arg command-line argument (transiently visible in this
  # container's own /proc/<pid>/cmdline during the jq exec — acceptable in a single-user game
  # container) and is never echoed to stdout or the logs.
  #
  # Fail-fast on missing/empty creds: a partially-configured ArkShop connects to the wrong host
  # or fails silently, which is harder to diagnose than an explicit boot-time fatal.
  #
  # The config.json was seeded from the image default by setup_plugin_configs() and is now at the
  # host-bound path via the symlink.
  #
  # Time: O(1)  Space: O(1)
  # Side effects: mutates ArkShop/config.json (and Permissions/config.json if it has a Mysql block)
  #               on the plugins-config host bind each boot. The write is idempotent — re-running
  #               produces the same file content (creds from env are constant within a boot).
  local win64="${ARK_DIR}/ShooterGame/Binaries/Win64"

  if [[ -z "${ARKSHOP_DB_HOST}" || -z "${ARKSHOP_DB_USER}" || -z "${ARKSHOP_DB_PASS}" || -z "${ARKSHOP_DB_NAME}" ]]; then
    echo "[entrypoint] FATAL: ArkShop DB credentials are missing or empty." >&2
    echo "  Required: ARKSHOP_DB_HOST, ARKSHOP_DB_USER, ARKSHOP_DB_PASS, ARKSHOP_DB_NAME" >&2
    echo "  (HOST defaults to 'mariadb', PORT to 3306; NAME/USER/PASS default to" >&2
    echo "   MARIADB_DATABASE/MARIADB_USER/MARIADB_PASSWORD — check your .env file)" >&2
    exit 1
  fi
  # Port reaches jq's tonumber, which errors on a non-numeric value — validate up front for a
  # clearer message than a raw jq failure.
  if ! [[ "${ARKSHOP_DB_PORT}" =~ ^[0-9]+$ ]]; then
    echo "[entrypoint] FATAL: ARKSHOP_DB_PORT must be numeric, got '${ARKSHOP_DB_PORT}'." >&2
    exit 1
  fi

  local arkshop_cfg="${win64}/ArkApi/Plugins/ArkShop/config.json"
  if [[ ! -f "${arkshop_cfg}" ]]; then
    echo "[entrypoint] FATAL: ArkShop config.json not found at ${arkshop_cfg}." >&2
    echo "  setup_plugin_configs() should have seeded it — check that deploy_plugins() completed." >&2
    exit 1
  fi

  _inject_mysql_block "${arkshop_cfg}"
  echo "[entrypoint] ArkShop DB config injected (host=${ARKSHOP_DB_HOST}, db=${ARKSHOP_DB_NAME}, user=${ARKSHOP_DB_USER})."
  # Password intentionally omitted from the log line above.

  # Permissions plugin: inject the same MySQL block if its config.json has one.
  # Permissions manages in-game role grants and is an ArkShop dependency — it needs the same DB.
  local perms_cfg="${win64}/ArkApi/Plugins/Permissions/config.json"
  if [[ -f "${perms_cfg}" ]] && jq -e 'has("Mysql")' "${perms_cfg}" >/dev/null 2>&1; then
    _inject_mysql_block "${perms_cfg}"
    echo "[entrypoint] Permissions DB config injected."
  fi
}

main() {
  # Time: O(1) compute; boot is I/O-dominated (steamcmd update + pdb restore up to 3 calls,
  #       Proton game load, Xvfb socket poll bounded to 50 × 0.1s)  Space: O(1)
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
  install_vcredist
  if [[ "${ENABLE_ASAAPI}" == "1" ]]; then
    ensure_modded_pdb
    setup_plugin_configs
    inject_plugin_db_config
    # ASA API Utils (CurseForge mod 955333) is required by ArkShop — without it AsaApi logs
    # "Singleton not found" and ArkShop's economy hooks don't fire. Append the mod ID to MODS
    # automatically so operators don't need to remember it; de-duplicate to handle the case
    # where the operator already listed it in their .env MODS value.
    if [[ -z "${MODS}" ]]; then
      MODS="955333"
    elif [[ ",${MODS}," != *",955333,"* ]]; then
      MODS="${MODS},955333"
    fi
  fi
  : > "$LOG_FILE"

  echo "[entrypoint] vm.max_map_count = $(cat /proc/sys/vm/max_map_count) (ASA needs >= 262144)"

  # The whole map?listen?opt?opt string is ONE argv to the exe → keep it quoted.
  # The -flags are separate argv → unquoted so they word-split.
  local query="${SERVER_MAP}?listen?SessionName=${SESSION_NAME}?Port=${SERVER_PORT}?MaxPlayers=${MAX_PLAYERS}?RCONEnabled=True?RCONPort=${RCON_PORT}?ServerAdminPassword=${ARK_ADMIN_PASSWORD}"
  [[ -n "$SERVER_PASSWORD" ]] && query="${query}?ServerPassword=${SERVER_PASSWORD}"

  local flags="-log -WinLiveMaxPlayers=${MAX_PLAYERS}"
  if [[ "$ENABLE_BATTLEYE" == "1" ]]; then flags="${flags} -BattlEye"; else flags="${flags} -NoBattlEye"; fi
  [[ -n "$MODS" ]] && flags="${flags} -mods=${MODS}"

  # Route launch through the AsaApiLoader (modded) or the vanilla server binary.
  # Both binaries accept identical args; ENABLE_ASAAPI=0 restores the M1 vanilla path with no rebuild.
  local launch_exe
  local xvfb_pid=""
  if [[ "${ENABLE_ASAAPI}" == "1" ]]; then
    launch_exe="${LOADER_EXE}"
    # AsaApiLoader creates a real Win32 window during init (via Wine's x11 driver), unlike the
    # vanilla server which runs headless through SDL_VIDEODRIVER=dummy. With no X display, Wine
    # logs nodrv_CreateWindow ("explorer process failed to start") and the loader aborts. Give it
    # a virtual framebuffer. Vanilla (ENABLE_ASAAPI=0) skips this — its launch stays byte-for-byte M1.
    # Geometry 1024x768x24 is an arbitrary conventional minimum: the loader only needs a valid display
    # to create its init window; ASA/Wine render nothing (headless), so the actual resolution is ignored.
    #
    # `docker compose restart` reuses the container, so /tmp survives — a prior boot's X lock +
    # socket linger after Xvfb is gone. Xvfb then refuses display :0 ("server already active") and
    # exits, but the stale socket makes the readiness loop below break instantly and races kill -0
    # into a false pass, launching the loader against a dead display → instant crash / restart loop.
    # On a restart the old Xvfb is already gone (fresh PID namespace), so clearing these is safe.
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0
    Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
    xvfb_pid=$!
    export DISPLAY=:0
    # Xvfb binds its socket asynchronously; launch before it is ready and Wine still finds no
    # display. Wait for the X socket (cap ~5s — Xvfb is local and comes up in well under 1s).
    for _ in $(seq 1 50); do [[ -S /tmp/.X11-unix/X0 ]] && break; sleep 0.1; done
    # Two ways Xvfb leaves us without a usable display, both ending in the same nodrv_CreateWindow
    # abort we started Xvfb to prevent:
    #   1. It never bound its socket (missing kernel DRI, display in use) — the loop exhausts and the
    #      socket file is absent.
    #   2. It bound the socket then died (crash post-startup) — a STALE socket file passes -S but
    #      nothing is listening, so proton run hits ECONNREFUSED.
    # Require BOTH the socket present AND the Xvfb process still alive before proceeding. stderr was
    # suppressed above, so these checks are the only signal we have.
    xvfb_dead=0
    kill -0 "${xvfb_pid}" 2>/dev/null || xvfb_dead=1
    if [[ ! -S /tmp/.X11-unix/X0 || "${xvfb_dead}" -eq 1 ]]; then
      echo "[entrypoint] FATAL: Xvfb is not providing a usable display — socket absent or process dead after 5s." >&2
      echo "  AsaApiLoader requires a real X display. Check that Xvfb is installed in the image." >&2
      kill "${xvfb_pid}" 2>/dev/null || true
      exit 1
    fi
    echo "[entrypoint] Launching ${SERVER_MAP} on :${SERVER_PORT} (rcon :${RCON_PORT}) [AsaApiLoader — modded, Xvfb :0]"
  else
    launch_exe="${SERVER_EXE}"
    echo "[entrypoint] Launching ${SERVER_MAP} on :${SERVER_PORT} (rcon :${RCON_PORT}) [vanilla]"
  fi
  # WINEDEBUG comes from the container env (compose). -all = clean; +err,+seh to debug.
  proton run "${launch_exe}" "${query}" ${flags} 2>&1 &
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
  [[ -n "$xvfb_pid" ]] && kill "$xvfb_pid" 2>/dev/null || true
}

main "$@"
