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
: "${ARK_CLUSTER_ID:=}"                # shared cluster id — identical on every cluster server; empty = no cluster args (single-server M2 launch)
# CLUSTER_DIR embeds UNQUOTED into the launch flags string below (word-split at launch) — avoid
# spaces in this path; quote if you must (same caveat as SESSION_NAME above).
: "${CLUSTER_DIR:=${ARK_DIR}/ShooterGame/Saved/clusters}"  # -ClusterDirOverride target; all servers in a cluster must share this path
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
    # ArkAscendedServer.pdb (~2GB, not shipped by every build — see ensure_modded_pdb() below):
    # kept on a fresh modded install ONLY WHEN the currently-installed build's Steam depot actually
    # includes it (confirmed NOT always true — e.g. build 89.38/buildid 24058917 shipped without
    # it, an acknowledged upstream Wildcard regression: https://github.com/ArkServerApi/AsaApi/issues/61).
    # Shed on a fresh vanilla install regardless. A volume first-installed as vanilla (pdb absent)
    # that later flips to ENABLE_ASAAPI=1 is checked by ensure_modded_pdb() at the launch gate —
    # it CAN restore the pdb via steamcmd validate when the depot has it, but validate is a no-op
    # if the current build's depot doesn't ship the file at all; in that case a same-buildid pdb
    # must be manually copied from elsewhere (see ensure_modded_pdb()'s FATAL message).
    rm -rf "${ARK_DIR}/ShooterGame/Content/Movies/"
    if [[ "${ENABLE_ASAAPI}" != "1" ]]; then
      rm -rf "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
    fi
    touch "$INSTALL_MARKER"
  elif [[ "$UPDATE_ON_BOOT" == "1" ]]; then
    echo "[entrypoint] UPDATE_ON_BOOT=1 — delta update, no validate…"
    local steamcmd_out
    steamcmd_out="$(mktemp)"
    # steamcmd exits 0 even on failure (the well-known footgun noted above), so the failure
    # signal has to come from its own text output, not its exit code — hence the tee+grep
    # instead of checking $?.
    "${STEAMCMD_DIR}/steamcmd.sh" ${force_windows} +force_install_dir "${ARK_DIR}" \
      +login anonymous +app_update "${ASA_APPID}" +quit 2>&1 | tee "${steamcmd_out}" || true

    # Flow: a delta update can leave SteamCMD reporting "state is 0x6" (update-required AND
    # fully-installed at once) when its local depot manifest desyncs from the CDN — observed
    # 2026-07-05 immediately after a same-day ARK patch, reproduced on both a bare delta and a
    # validate pass against the stale manifest. Deleting appmanifest_*.acf forces SteamCMD to
    # rebuild it from scratch; a validate against the manifest-free tree is the confirmed fix
    # (manually verified same-day: cleared the stuck state and landed on the current build).
    # Failure mode if this repair also fails: server boots on whatever's already on disk — that
    # binary may be stale relative to what clients have patched to, but a boot beats no boot.
    if grep -q "state is 0x6" "${steamcmd_out}"; then
      echo "[entrypoint] SteamCMD stuck (state 0x6) — deleting manifest and retrying with validate…"
      rm -f "${ARK_DIR}/steamapps/appmanifest_${ASA_APPID}.acf"
      "${STEAMCMD_DIR}/steamcmd.sh" ${force_windows} +force_install_dir "${ARK_DIR}" \
        +login anonymous +app_update "${ASA_APPID}" validate +quit 2>&1 | tee -a "${steamcmd_out}" || true
      if grep -q "state is 0x6" "${steamcmd_out}"; then
        echo "[entrypoint] WARNING: SteamCMD still stuck after manifest reset — booting on whatever's already on disk." >&2
      else
        echo "[entrypoint] SteamCMD update recovered after manifest reset."
      fi
    fi
    rm -f "${steamcmd_out}"
  else
    echo "[entrypoint] Fast boot — skipping Steam (set UPDATE_ON_BOOT=1 to update)."
  fi
}

deploy_plugins() {
  # Sync the image-baked AsaApi + plugin binaries onto the volume's Win64 tree.
  # The game installs at runtime (install_or_update above), so we can't COPY during the
  # build — the image is the version source-of-truth; this sync makes it so on the volume.
  #
  # Clean-replace strategy: stash existing config.json files from ArkApi/Plugins/*/,
  # remove the AsaApi-owned paths (so stale binaries from a prior version can't linger),
  # copy fresh from the image, then restore the saved configs. Paths not owned by AsaApi
  # (everything else in Win64) are never touched. Config files that didn't exist before
  # are seeded from the image defaults (seed-if-absent).
  #
  # The stash/restore is deliberately KEPT under the per-server deploy-from-repo model
  # (ADR 0004): it is redundant for ArkShop/Permissions (setup_plugin_configs overwrites both
  # from their repo seeds right after this), but load-bearing for any plugin WITHOUT a repo
  # seed — ArkShopUI today — whose volume config would otherwise reset to the image default
  # on every boot.
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
    [[ -e "${entry}" ]] || continue   # guard the degenerate empty-dir glob (no nullglob): skip a literal "*"
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
  # ---------------------------------------------------------------------------------------------
  # Cross-map pdb cache (added 2026-07-06 — see .claude/plans/active/ark-asa-server/m3-cluster/audit.md
  # for the full incident this fixes). WHAT this is: a small, buildid-keyed cache directory living
  # on the SHARED `ark-cluster` volume (already mounted into every map service at the fixed path
  # `/home/container/cluster-data` for ASA's own native cluster-transfer feature — this reuses that
  # existing mount, adds no new volume). WHY it exists: a genuinely fresh install cannot always get
  # this file from steamcmd — confirmed live: Wildcard's build 89.38/buildid 24058917 shipped with
  # NO pdb at all (an acknowledged upstream regression, AsaApi/AsaApi#61), and `steamcmd validate`
  # can only restore a file that's actually in the depot's current manifest, so retrying it is a
  # predictable no-op, not flakiness. WHAT it fixes: the first map that successfully boots at a
  # given buildid (whether the depot legitimately shipped the pdb, or an operator manually restored
  # it from elsewhere) seeds this cache; every OTHER map added afterward at the SAME buildid — a
  # new map on this same cluster, a rebuild-from-clean, anything sharing this `ark-cluster` volume —
  # picks it up automatically, with zero steamcmd calls and zero manual intervention. This does NOT
  # cover a genuinely fresh, isolated host with no shared volume to seed from at all (e.g. a first-
  # ever prod VPS deploy) — that case still needs the pdb carried over manually (see the FATAL
  # message below), since there is nothing on that host to cache from.
  # ---------------------------------------------------------------------------------------------
  #
  # Flow:
  #   1. Return early if the pdb is already present and non-trivially-sized (common path on a modded
  #      volume) — and opportunistically seed the shared cache if this buildid isn't cached yet.
  #   2. If missing, check the shared cache for this exact buildid first — free, instant, no steamcmd.
  #   3. Only if the cache misses: attempt steamcmd validate (up to 3 times); break on a valid artifact.
  #      NOTE: validate can only restore a file the CURRENT build's depot actually ships — if it
  #      doesn't (see the 89.38 case above), all 3 attempts are a predictable no-op, not flakiness.
  #   4. Verify the pdb is present and non-trivially-sized — trust the artifact, not steamcmd's exit code.
  #      On success, seed the shared cache so the NEXT map/rebuild at this buildid skips steamcmd too.
  #   5. If still missing after all attempts: HOLD (loud, periodic, non-exiting) rather than
  #      fatal-exit — see the holding loop below for why exiting here is actively harmful.
  #
  # Time: O(1) compute, up to 3 steamcmd validate calls (I/O-dominated)  Space: O(1)
  #
  # Side effects: may write the ~2GB pdb file onto the ark-game volume, and/or a ~2GB copy onto the
  # shared ark-cluster volume's cache directory (once per distinct buildid, never per-boot).
  local pdb="${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb"
  local force_windows="+@sSteamCmdForcePlatformType windows"
  local appmanifest="${ARK_DIR}/steamapps/appmanifest_${ASA_APPID}.acf"
  # Fixed path, NOT derived from ${CLUSTER_DIR}: CLUSTER_DIR is ASA's own launch-arg-facing path,
  # subject to its own charset/traversal guards further down this file for ASA's specific use —
  # this cache is an unrelated, our-own-infra concern, so it reads the real shared mount point
  # directly (the same one docker-compose.yml mounts `ark-cluster` at) rather than reusing or
  # depending on that ASA-specific variable's validation logic.
  local pdb_cache_dir="/home/container/cluster-data/.infra-pdb-cache"

  # A bare -f test passes a 0-byte or truncated pdb (e.g. steamcmd exhausted disk mid-download),
  # which AsaApi then fails to SHA-256 — the exact silent-zero-plugin failure this function prevents.
  # The real pdb is ~2GB; require >1 MiB to reject truncated files while never rejecting a real one.
  pdb_ok() { [[ -f "${pdb}" ]] && [[ "$(stat -c%s "${pdb}" 2>/dev/null || echo 0)" -gt 1048576 ]]; }

  # Steam's own appmanifest is the single source of truth for "which build is actually installed
  # right now" — read directly from it rather than trusting any env var or cached assumption.
  _current_buildid() {
    grep -oP '"buildid"\s*"\K[0-9]+' "${appmanifest}" 2>/dev/null || true
  }

  # Best-effort only: caching is a nice-to-have optimization, never a boot-blocking requirement.
  # Any failure here (unwritable volume, unknown buildid) is skipped, never fatal — and this
  # function ALWAYS explicitly `return 0`, on every branch, rather than falling through to
  # "whatever the last command's exit code happened to be". This script runs under
  # `set -euo pipefail`, and this function is called as a bare statement (not `foo || true`) at
  # both call sites below — a version that let a failed `cp` become its own return value would
  # silently abort the ENTIRE entrypoint on a cache-write failure alone, killing an otherwise-
  # healthy boot to protect a nice-to-have optimization (caught live by graveyard-auditor before
  # this shipped: reproduced the abort with a failing `cp` and zero log output). Never repeat that
  # shape here — every path out of this function must end in an explicit `return 0`.
  _cache_pdb_if_new() {
    local buildid; buildid="$(_current_buildid)"
    if [[ -z "${buildid}" ]]; then return 0; fi
    if ! mkdir -p "${pdb_cache_dir}" 2>/dev/null; then return 0; fi
    local cached="${pdb_cache_dir}/${buildid}.pdb"
    if [[ -f "${cached}" ]]; then return 0; fi
    if cp -f "${pdb}" "${cached}" 2>/dev/null; then
      echo "[entrypoint] Cached ArkAscendedServer.pdb for buildid ${buildid} on the shared cluster volume (future maps/rebuilds at this buildid will reuse it)."
    else
      echo "[entrypoint] NOTE: could not write pdb cache to ${pdb_cache_dir} (non-fatal, continuing boot)." >&2
    fi
    return 0
  }

  if pdb_ok; then
    _cache_pdb_if_new
    return 0
  fi

  # Shared-cache check — before ever touching steamcmd. Skipped silently if the buildid can't be
  # determined or nothing is cached for it yet; falls through to the steamcmd path below either way.
  local current_buildid cached_pdb
  current_buildid="$(_current_buildid)"
  cached_pdb="${pdb_cache_dir}/${current_buildid}.pdb"
  if [[ -n "${current_buildid}" ]] && [[ -f "${cached_pdb}" ]]; then
    echo "[entrypoint] pdb missing locally but found cached for buildid ${current_buildid} on the shared cluster volume — restoring from cache (no steamcmd needed)…"
    # `|| true`: a bare `cp` here, under this script's `set -euo pipefail`, would abort the WHOLE
    # entrypoint on failure (disk full, permission issue) instead of falling through to the
    # steamcmd path this comment block promises — the exact sibling bug graveyard-auditor caught
    # in _cache_pdb_if_new()'s write path, live-reproduced here too. Let pdb_ok (not cp's exit
    # code) decide whether the restore actually worked.
    cp -f "${cached_pdb}" "${pdb}" || true
    if pdb_ok; then
      echo "[entrypoint] pdb restored from shared cache."
      return 0
    fi
    echo "[entrypoint] WARNING: cached pdb for buildid ${current_buildid} failed validation after copy — falling through to steamcmd." >&2
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
      _cache_pdb_if_new
      break
    fi
    echo "[entrypoint] pdb still absent after attempt ${attempt}."
  done

  if ! pdb_ok; then
    # Do NOT exit here. `restart: unless-stopped` restarts on ANY exit code, so exiting would
    # re-trigger this exact 3x-validate loop forever — an unattended, unbounded hammer on the
    # Steam CDN (each attempt is a full validate pass against the ~13.5GB depot), not a fast
    # crash-loop. Hold the container open in a visibly-failed state instead: loud, periodic,
    # impossible to miss in `docker compose logs`/`ps`, and it never re-touches steamcmd.
    echo "[entrypoint] FATAL: ArkAscendedServer.pdb is still missing or truncated after 3 steamcmd validate attempts." >&2
    echo "  Expected: ${pdb}" >&2
    echo "  This is usually NOT a local problem (CDN/disk) — steamcmd validate can only restore" >&2
    echo "  files that are actually in the current build's depot manifest. If Wildcard's current" >&2
    echo "  build shipped without this file (check https://github.com/ArkServerApi/AsaApi/issues" >&2
    echo "  for a known regression on this buildid), validate will never produce it no matter how" >&2
    echo "  many times it's retried." >&2
    echo "  Fix (this server): copy a same-buildid ArkAscendedServer.pdb from another server/volume" >&2
    echo "  onto ${pdb}, then restart this container manually." >&2
    echo "  Fix (every future map/rebuild too, recommended): drop that same pdb at" >&2
    echo "  ${pdb_cache_dir}/${current_buildid:-<buildid>}.pdb on the shared ark-cluster volume instead —" >&2
    echo "  this server AND every other map on this cluster will pick it up automatically on next boot," >&2
    echo "  no per-server manual copy needed again for this buildid." >&2
    echo "[entrypoint] HOLDING (not exiting) to avoid an unattended validate-storm crash-loop." >&2
    while true; do
      echo "[entrypoint] $(date -Iseconds) — still holding: ArkAscendedServer.pdb missing, AsaApi cannot start. See FATAL above." >&2
      sleep 300
    done
  fi
}

seed_gus() {
  # Deploy GameUserSettings.ini as a fresh per-server copy from the repo canonical each boot,
  # then inject this server's SessionName so N servers sharing ONE canonical each advertise
  # their own name. Repo wins: the engine rewrites GUS on shutdown (strips comments), and the
  # fresh copy discards that rewrite by design — edit config/GameUserSettings.ini → restart.
  # Injecting onto a fresh copy of the canonical means the injection always operates on a
  # known-good file, never on last boot's engine-rewritten output.
  #
  # The injection is line-oriented (INI — not jq territory) and CRLF-consistent both ways:
  # matching tolerates a trailing \r (the canonical is CRLF), and every INJECTED line adopts
  # the source file's own ending (a \r is appended when any source line carries one), so a
  # CRLF canonical stays uniformly CRLF instead of gaining mixed LF-only injected lines.
  # Three cases are covered:
  #   1. SessionName key exists under [SessionSettings]  → replace its value
  #   2. [SessionSettings] exists but the key is absent  → append the key inside the section
  #   3. [SessionSettings] section absent                → append section + key at EOF
  # SESSION_NAME passes via the environment (not awk -v) so awk cannot mangle backslash
  # escape sequences in the value.
  #
  # The `|| { … exit 1; }` is load-bearing under set -e for the same reason documented in
  # _inject_mysql_block below: awk sits in a non-final list position where set -e won't fire.
  #
  # Time: O(n) where n = GUS line count  Space: O(1) streaming (tmp file on disk)
  local dest_dir="$1"
  local canonical="/home/container/config/GameUserSettings.ini"
  local gus="${dest_dir}/GameUserSettings.ini"
  cp "${canonical}" "${gus}"

  local tmp
  tmp="$(mktemp)"
  GUS_SESSION_NAME="${SESSION_NAME}" awk '
    BEGIN { name = ENVIRON["GUS_SESSION_NAME"]; eol = ""; in_section = 0; seen_section = 0; done = 0 }
    /\r$/ { eol = "\r" }
    /^\[SessionSettings\]\r?$/ { in_section = 1; seen_section = 1; print; next }
    /^\[/ {
      if (in_section && !done) { print "SessionName=" name eol; done = 1 }
      in_section = 0; print; next
    }
    in_section && /^SessionName[ \t]*=/ {
      if (!done) { print "SessionName=" name eol; done = 1 }
      next
    }
    { print }
    END {
      if (!seen_section) { print "[SessionSettings]" eol; print "SessionName=" name eol }
      else if (!done)    { print "SessionName=" name eol }
    }
  ' "${gus}" > "${tmp}" || { rm -f "${tmp}"; echo "[entrypoint] FATAL: SessionName injection into ${gus} failed." >&2; exit 1; }
  mv "${tmp}" "${gus}"
  echo "[entrypoint] GameUserSettings.ini deployed from repo canonical (SessionName=${SESSION_NAME})."
}

setup_plugin_configs() {
  # Deploy each plugin's config.json as a fresh per-server copy from its tracked repo seed
  # every boot (repo = source of truth; runtime edits discarded — ADR 0004). Each copy is a
  # REAL file written into the deploy_plugins()-managed plugin dir on this server's own game
  # volume — never a symlink to a shared path — so N servers booting in parallel have
  # physically distinct files and cannot race or clobber each other. Edit the repo seed →
  # push → restart to change every server at once.
  #
  # Seeds carry NO secrets: the DB connection is injected AFTER this
  # (inject_plugin_db_config) onto the per-server runtime copy only.
  #   - ArkShop: config/arkshop.config.json — GENERATED + tracked (tools/gen-shop.ts).
  #   - Permissions: config/permissions.config.json — tracked capture of the image default.
  #
  # A missing seed is FATAL, not fall-back-to-image-default: the seeds are tracked files on
  # the read-only ./config bind, so absence means a broken checkout/mount — booting on the
  # image default would silently serve the wrong catalog (and a DB-less Permissions).
  #
  # Time: O(p) where p = plugin count (2 in practice — ArkShop + Permissions)  Space: O(1)
  local win64="${ARK_DIR}/ShooterGame/Binaries/Win64"

  local plugin seed
  for plugin in ArkShop Permissions; do
    local plugin_dir="${win64}/ArkApi/Plugins/${plugin}"
    case "${plugin}" in
      ArkShop)     seed="/home/container/config/arkshop.config.json" ;;
      Permissions) seed="/home/container/config/permissions.config.json" ;;
    esac

    # The plugin dir (with its DLL) must already exist from deploy_plugins(); if it doesn't,
    # the plugin wasn't deployed — skip rather than write a config AsaApi will never load.
    if [[ ! -d "${plugin_dir}" ]]; then
      echo "[entrypoint] WARN: ${plugin} not deployed (no ${plugin_dir}); skipping config deploy." >&2
      continue
    fi
    if [[ ! -f "${seed}" ]]; then
      echo "[entrypoint] FATAL: ${plugin} repo seed missing at ${seed} — check the ./config mount / repo checkout." >&2
      exit 1
    fi
    cp "${seed}" "${plugin_dir}/config.json"
    echo "[entrypoint] Deployed ${plugin} config.json from repo seed (${seed##*/})."
  done
}

_inject_mysql_block() {
  # Write the DB connection block into one plugin's config.json via jq.
  #   $1 = config path — a REAL per-server file (setup_plugin_configs deploys it from the repo
  #        seed each boot), so the write is a plain atomic tmp+mv onto that file.
  #   $2 = schema — the two plugins expect DIFFERENT config shapes:
  #        nested: ArkShop — connection keys live under a top-level "Mysql" object.
  #        flat:   Permissions — Mysql* keys sit at the JSON root (the plugin's real schema,
  #                per its shipped image default; a nested "Mysql" object would be silently
  #                ignored and the plugin would boot DB-less).
  # jq --arg passes each value as a plain string (not evaluated as a jq filter expression), so
  # special characters in creds are safe. The PASSWORD alone reaches jq via a per-invocation
  # environment variable (env.INJECT_MYSQL_PASS — the same idiom seed_gus uses for awk) instead
  # of --arg, so it never appears in the jq process's argv (/proc/<pid>/cmdline); jq's env
  # values are plain strings too, never evaluated as filter code. MysqlPort coerces via
  # tonumber so the JSON type stays integer, matching the plugins' expected schema.
  #
  # The `|| { … exit 1; }` is load-bearing: in `jq … > tmp && mv tmp cfg`, jq sits in a non-final
  # position of an && list, where `set -e` does NOT abort on its failure. Without the explicit
  # exit, a jq failure (e.g. a bad value reaching tonumber) is swallowed and the caller logs a
  # false success against an unwritten config. The handler is the list's final element, so its
  # exit fires unconditionally.
  #
  # Time: O(1)  Space: O(1)   Side effect: rewrites ${cfg} in place (atomic tmp+mv).
  local cfg schema filter
  cfg="$1"
  schema="$2"
  case "${schema}" in
    nested)
      filter='.Mysql.UseMysql  = true
            | .Mysql.MysqlHost = $host
            | .Mysql.MysqlUser = $user
            | .Mysql.MysqlPass = env.INJECT_MYSQL_PASS
            | .Mysql.MysqlDB   = $db
            | .Mysql.MysqlPort = ($port | tonumber)'
      ;;
    flat)
      filter='.UseMysql  = true
            | .MysqlHost = $host
            | .MysqlUser = $user
            | .MysqlPass = env.INJECT_MYSQL_PASS
            | .MysqlDB   = $db
            | .MysqlPort = ($port | tonumber)'
      ;;
    *)
      echo "[entrypoint] FATAL: _inject_mysql_block: unknown schema '${schema}' (expected nested|flat)." >&2
      exit 1
      ;;
  esac
  local tmp
  tmp="$(mktemp)"
  INJECT_MYSQL_PASS="${ARKSHOP_DB_PASS}" \
  jq --arg host "${ARKSHOP_DB_HOST}" \
     --arg user "${ARKSHOP_DB_USER}" \
     --arg db   "${ARKSHOP_DB_NAME}" \
     --arg port "${ARKSHOP_DB_PORT}" \
     "${filter}" \
     "${cfg}" > "${tmp}" || { rm -f "${tmp}"; echo "[entrypoint] FATAL: jq failed to write DB config into ${cfg}." >&2; exit 1; }
  mv "${tmp}" "${cfg}"
}

inject_plugin_db_config() {
  # Inject DB connection credentials into the ArkShop (and Permissions) config.json.
  # Credentials come from env vars (ARKSHOP_DB_*), never from a literal in this script. The
  # password reaches jq through the environment (see _inject_mysql_block), never as a
  # command-line argument — so it is not visible in /proc/<pid>/cmdline — and is never echoed
  # to stdout or the logs.
  #
  # Fail-fast on missing/empty creds: a partially-configured ArkShop connects to the wrong host
  # or fails silently, which is harder to diagnose than an explicit boot-time fatal.
  #
  # Each config.json is a real per-server file deployed from its repo seed by
  # setup_plugin_configs(); injection rewrites that per-server copy in place.
  #
  # Time: O(1)  Space: O(1)
  # Side effects: mutates the per-server ArkShop/config.json (and Permissions/config.json)
  #               inside the plugin dirs on this server's game volume each boot. The write is
  #               idempotent — re-running produces the same file content (creds from env are
  #               constant within a boot).
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

  _inject_mysql_block "${arkshop_cfg}" nested
  echo "[entrypoint] ArkShop DB config injected (host=${ARKSHOP_DB_HOST}, db=${ARKSHOP_DB_NAME}, user=${ARKSHOP_DB_USER})."
  # Password intentionally omitted from the log line above.

  # Permissions plugin: inject the same MySQL connection, FLAT schema — its Mysql* keys sit at
  # the JSON root, unlike ArkShop's nested "Mysql" object (see _inject_mysql_block). Permissions
  # manages in-game role grants and is an ArkShop dependency — it needs the same DB. Guard on
  # the flat schema's UseMysql key; a config without it cannot take the connection, and skipping
  # SILENTLY would be the exact DB-less boot this guard exists to surface — so warn loudly.
  local perms_cfg="${win64}/ArkApi/Plugins/Permissions/config.json"
  if [[ -f "${perms_cfg}" ]]; then
    if jq -e 'has("UseMysql")' "${perms_cfg}" >/dev/null 2>&1; then
      _inject_mysql_block "${perms_cfg}" flat
      echo "[entrypoint] Permissions DB config injected."
    else
      echo "[entrypoint] WARN: Permissions config.json carries no UseMysql key — DB inject skipped; Permissions would run on its LOCAL store, not the shared DB. Check config/permissions.config.json." >&2
    fi
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

  # Deploy the engine INIs: WindowsServer is a REAL per-server directory on the ark-game
  # volume holding fresh copies of the repo canonicals (the ./config bind) each boot — repo
  # wins, runtime edits are discarded (ADR 0004). Per-server copies mean the engine's GUS
  # shutdown-rewrite lands on this server's own file, never a shared one — N servers cannot
  # clobber each other. Edit ./config/*.ini on the host → restart → fresh copies deployed.
  # This is a real dir on the ark-game VOLUME, not a Docker bind — docker-compose.yml's
  # deep-bind root-creation warning (on the ./config mount) does not apply here.
  # Transition-safe: a volume last booted on the whole-dir-symlink model still has
  # WindowsServer as a symlink to /home/container/config — remove the LINK itself (never the
  # canonical it points at; rm on a symlink never follows it) before creating the real dir,
  # or the copies below would write THROUGH the link into the shared canonicals.
  local config_dir="${ARK_DIR}/ShooterGame/Saved/Config/WindowsServer"
  [[ -L "${config_dir}" ]] && rm -f "${config_dir}"
  mkdir -p "${config_dir}"
  cp /home/container/config/Game.ini "${config_dir}/Game.ini"
  seed_gus "${config_dir}"

  # ARK_CLUSTER_ID interpolates unquoted into the launch flags string (below) — reject anything
  # outside a safe charset now, at boot, rather than let a stray space/glob char corrupt argv.
  # ARK_CLUSTER_ID is documented "treat like a password" — never echo the raw value, even on
  # rejection; state that it's invalid without printing it.
  if [[ -n "${ARK_CLUSTER_ID}" && ! "${ARK_CLUSTER_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "[entrypoint] FATAL: ARK_CLUSTER_ID contains invalid characters — only [A-Za-z0-9._-] allowed." >&2
    exit 1
  fi

  # CLUSTER_DIR reaches the SAME unquoted launch-flags sink as ARK_CLUSTER_ID above AND feeds a
  # destructive `rm -rf "${CLUSTER_DIR}"` in the symlink setup just below — reject anything
  # outside a safe absolute-path charset now, at boot, rather than let a stray space/glob char
  # corrupt argv or a malformed path widen the rm -rf's blast radius. (Not a secret like
  # ARK_CLUSTER_ID — a path, so safe to echo back for debugging.)
  if [[ ! "${CLUSTER_DIR}" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    echo "[entrypoint] FATAL: CLUSTER_DIR is not a safe absolute path — only [A-Za-z0-9._/-] allowed, got '${CLUSTER_DIR}'." >&2
    exit 1
  fi

  # Charset alone doesn't stop a COLLISION with the game install root — a regex-shape check
  # (matching literal `..` segments and a bare `${ARK_DIR}"/*"` glob) still let a *spelling*
  # variant of the same path through uncaught: a trailing slash (`${ARK_DIR}/`), a doubled slash
  # (`${ARK_DIR}//`), or a bare `.` segment (`${ARK_DIR}/.`) all satisfy `"${CLUSTER_DIR}" ==
  # "${ARK_DIR}"` in every way that matters on disk, but bash's glob `*` also matches the EMPTY
  # string, so `"${ARK_DIR}/"` matches the pattern `"${ARK_DIR}"/*` and slipped past that check —
  # reaching the `rm -rf "${CLUSTER_DIR}"` below and wiping the entire ~13GB game install root
  # (reproduced live; see entrypoint.sh history / plan review notes). Canonicalization must be
  # LEXICAL ONLY — `.`, `..`, and repeated/trailing slashes collapsed WITHOUT following any
  # symlink the path happens to already be. Two reasons: (1) CLUSTER_DIR's parent dirs may not
  # exist yet on first boot (steamcmd hasn't created ShooterGame/Saved/ before this guard runs),
  # so plain symlink resolution would fail outright; (2) on every boot AFTER the first, this same
  # CLUSTER_DIR value already exists on disk as the symlink the block below creates, pointing at
  # /home/container/cluster-data — which sits OUTSIDE ARK_DIR by design (see that block's comment).
  # A canonicalizer that follows symlinks would resolve THROUGH that link on a warm boot and see
  # the out-of-tree target, incorrectly FATAL-rejecting a value that, as a string, is still the
  # exact same safe default it was on first boot — the server could never restart past its first
  # boot. `realpath -m -s` (`-m`: tolerate not-yet-existing components; `-s`/`--no-symlinks`:
  # normalize lexically, never expand a symlink) canonicalizes the STRING shape only, giving the
  # same verdict on first boot, warm boot, and every spelling variant alike. Requiring the
  # canonical CLUSTER_DIR to have the canonical ARK_DIR as a strict path-prefix (the glob's `/`
  # separator rules out a same-prefix-different-dir collision like `${ARK_DIR}foo`) makes every
  # spelling of "equals or escapes ARK_DIR" collapse to the same rejected case, instead of
  # enumerating each spelling by hand. Reassign CLUSTER_DIR to its canonical form so every
  # downstream use (the rm -rf below, the symlink target, the launch flags string) is unambiguous.
  local cluster_dir_canon ark_dir_canon
  cluster_dir_canon="$(realpath -m -s -- "${CLUSTER_DIR}")"
  ark_dir_canon="$(realpath -m -s -- "${ARK_DIR}")"
  if [[ "${cluster_dir_canon}" != "${ark_dir_canon}"/* ]]; then
    echo "[entrypoint] FATAL: CLUSTER_DIR must be a path strictly under ARK_DIR (${ARK_DIR}) — got '${CLUSTER_DIR}' (canonicalizes to '${cluster_dir_canon}')." >&2
    exit 1
  fi
  CLUSTER_DIR="${cluster_dir_canon}"

  # The lexical-only check above must never follow a symlink (that's the whole point of `-s` —
  # see the comment above it), but that also means it is blind to an INTERMEDIATE path component
  # between ARK_DIR and CLUSTER_DIR's leaf (e.g. if `ShooterGame` or `Saved` were ever a symlink
  # pointing outside ARK_DIR) — the lexical check only inspects the string, while the actual
  # mkdir -p / rm -rf / ln -sfn below follow normal kernel symlink resolution through every
  # component on the real filesystem, so such a symlink could send them outside ARK_DIR even
  # though the lexical check passed. Only the FINAL `clusters` component is an intentional
  # symlink (the block below creates it every boot); the PARENT directory is never meant to be
  # one, so canonicalizing just the parent WITH symlink-following (plain `realpath -m`, no `-s`)
  # is safe — it cannot reintroduce the warm-boot false-rejection the lexical check above exists
  # to avoid, because the parent is never the leaf symlink itself.
  local cluster_parent_canon
  cluster_parent_canon="$(realpath -m -- "$(dirname "${CLUSTER_DIR}")")"
  if [[ "${cluster_parent_canon}" != "${ark_dir_canon}" && "${cluster_parent_canon}" != "${ark_dir_canon}"/* ]]; then
    echo "[entrypoint] FATAL: CLUSTER_DIR's parent directory resolves outside ARK_DIR (${ARK_DIR}) through a symlink — got '${CLUSTER_DIR}' (parent canonicalizes to '${cluster_parent_canon}')." >&2
    exit 1
  fi

  # Link CLUSTER_DIR (the -ClusterDirOverride target) to the shared cluster-data volume mount —
  # same pattern as the WindowsServer config_link above, for the same reason: docker-compose.yml
  # mounts ark-cluster SHALLOW at a fixed top-level path (/home/container/cluster-data) instead of
  # directly at CLUSTER_DIR, because CLUSTER_DIR sits inside the already-mounted ark-game volume at
  # a path that doesn't exist yet on first boot (steamcmd hasn't created ShooterGame/Saved/) —
  # mounting there directly would make Docker root-create the missing intermediate dirs, blocking
  # this non-root user's writes to the cluster-transfer files. Idempotent (rm + relink) so a warm
  # boot with the link already present is a no-op.
  mkdir -p "$(dirname "${CLUSTER_DIR}")"
  rm -rf "${CLUSTER_DIR}"
  ln -sfn /home/container/cluster-data "${CLUSTER_DIR}"

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

  # -Port= as a STANDALONE flag (not just the ?Port= inside the quoted map-URL query above) is
  # required for the engine's actual listen socket to bind to it. Verified live, this was a real
  # bug: with only the URL's ?Port=, every instance's engine bound its UDP game socket to 7777
  # regardless of SERVER_PORT — the URL param is read later by ARK's own game code (which is why
  # RCONPort, read the same way, worked correctly per-instance the whole time), but the engine's
  # low-level socket subsystem binds from a standalone command-line switch parsed earlier, before
  # the game-specific URL options are read at all. Confirmed via `ss` inside each container: every
  # map's actual UDP listener was 0.0.0.0:7777 until this flag was added.
  local flags="-log -Port=${SERVER_PORT} -WinLiveMaxPlayers=${MAX_PLAYERS}"
  if [[ "$ENABLE_BATTLEYE" == "1" ]]; then flags="${flags} -BattlEye"; else flags="${flags} -NoBattlEye"; fi
  [[ -n "$MODS" ]] && flags="${flags} -mods=${MODS}"
  # Cluster args are inert with one server but required once N servers share transfers — only
  # appended when ARK_CLUSTER_ID is set, so an unset/empty id preserves the byte-identical M2 launch.
  [[ -n "$ARK_CLUSTER_ID" ]] && flags="${flags} -clusterid=${ARK_CLUSTER_ID} -ClusterDirOverride=${CLUSTER_DIR}"

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
