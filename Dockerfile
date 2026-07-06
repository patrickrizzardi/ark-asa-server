# ARK: Survival Ascended — lean server image, built on the proven steamcmd:proton base.
#
# We proved a from-scratch image first; the lesson (documented in the README + state.md) is
# that ASA-on-Proton needs a specific runtime: winbind, xvfb, libgdiplus, audio libs, a real
# dbus machine-id, GE-Proton, AND a non-root user. The parkervcp steamcmd:proton base ships
# all of that, so we build on it instead of reassembling it by hand. We add only:
#   - SteamCMD (the base expects the game-server layer to provide it)
#   - our fast-boot entrypoint
# Per build-time-vs-runtime.md the ~30GB game still installs at RUNTIME onto a volume.
FROM ghcr.io/parkervcp/steamcmd:proton

# Base sets USER container; switch to root only to install SteamCMD + drop in our entrypoint.
USER root

# unzip is needed to extract the AsaApi + ArkShop zips below; the steamcmd:proton base
# ships curl/tar but not unzip. Fixed build dependency → image layer (build-time-vs-runtime.md).
RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip jq \
 && rm -rf /var/lib/apt/lists/*

ARG STEAMCMD_DIR=/opt/steamcmd
# Run steamcmd once at build so it self-updates and bakes its native client libs
# (linux32/linux64/steamclient.so) into the image. Proton's lsteamclient loads steamclient.so
# at launch or the server asserts and aborts; baking it means even a fast boot (which skips
# steamcmd) always has it. It's a fixed dependency → image, per build-time-vs-runtime.md.
RUN mkdir -p ${STEAMCMD_DIR} \
 && curl -sL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
      | tar -xz -C ${STEAMCMD_DIR} \
 && "${STEAMCMD_DIR}/steamcmd.sh" +login anonymous +quit \
 && chown -R container:container ${STEAMCMD_DIR}

# Bake pinned AsaApi + ArkShop + Permissions into the image at a neutral /opt path.
# The game's Binaries/Win64 lives on the ark-game volume (installed at runtime), so we
# can't COPY there directly — the entrypoint syncs /opt/asaapi/* onto Win64 each boot.
# Rebuild the image to update versions (no auto-latest; bad upstream = silent server breakage).
# Lib/ (developer import lib) and the ONLY FOR DEVELOPERS dir are excluded — not needed at
# runtime. Per build-time-vs-runtime.md: immutable + version-pinned → Dockerfile.
ARG ASAAPI_VERSION=1.21
ARG ARKSHOP_VERSION=1.4
ARG PERMISSIONS_VERSION=1.1  # doc-pin only — Permissions ships bundled in the AsaApi zip; no separate download, no URL interpolation. Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries.
ARG ARKSHOPUI_VERSION=1.4    # bridge plugin between ArkShop and the MX-E Ark Shop UI mod (942249)
RUN mkdir -p /opt/asaapi/ArkApi/Plugins/ArkShop \
 && curl -fsSL "https://ark-server-api.com/resources/asa-server-api.31/download?version=${ASAAPI_VERSION}" \
      -o /tmp/asaapi.zip \
 && unzip -q /tmp/asaapi.zip -d /tmp/asaapi_src \
 && cp -r /tmp/asaapi_src/ArkApi /opt/asaapi/ \
 && rm -rf "/opt/asaapi/ArkApi/Plugins/Permissions/ONLY FOR DEVELOPERS" \
 && cp /tmp/asaapi_src/AsaApiLoader.exe \
       /tmp/asaapi_src/msvcp140.dll \
       /tmp/asaapi_src/msdia140.dll \
       /tmp/asaapi_src/libcrypto-3-x64.dll \
       /tmp/asaapi_src/libssl-3-x64.dll \
       /tmp/asaapi_src/config.json \
       /opt/asaapi/ \
 && curl -fsSL "https://ark-server-api.com/resources/asa-arkshop.34/download?version=${ARKSHOP_VERSION}" \
      -o /tmp/arkshop.zip \
 && unzip -q /tmp/arkshop.zip -d /tmp/arkshop_src \
 && cp -r /tmp/arkshop_src/ArkShop/. /opt/asaapi/ArkApi/Plugins/ArkShop/ \
 && mkdir -p /opt/asaapi/ArkApi/Plugins/ArkShopUI \
 && curl -fsSL "https://ark-server-api.com/resources/arkshopui-ascended.13/download?version=${ARKSHOPUI_VERSION}" \
      -o /tmp/arkshopui.zip \
 && unzip -q /tmp/arkshopui.zip -d /tmp/arkshopui_src \
 && cp -r /tmp/arkshopui_src/ArkShopUI/. /opt/asaapi/ArkApi/Plugins/ArkShopUI/ \
 && rm -rf /tmp/asaapi.zip /tmp/asaapi_src /tmp/arkshop.zip /tmp/arkshop_src /tmp/arkshopui.zip /tmp/arkshopui_src \
 && find /opt/asaapi -name '*.pdb' -delete \
 && chown -R container:container /opt/asaapi

# Bake the VC++ 2019 redist installer into the image. The Proton Wine prefix lives on the
# ark-game volume (created at first boot), so the redist CANNOT be run at build time — the
# prefix does not exist yet. The image stores the immutable installer at /opt/vcredist/;
# the entrypoint installs it into the volume prefix on first boot (marker-guarded, idempotent).
# Per build-time-vs-runtime.md 3-question test: Q1 yes (depends on the mounted volume) → entrypoint.
RUN mkdir -p /opt/vcredist \
 && curl -fsSL "https://aka.ms/vs/16/release/vc_redist.x64.exe" \
      -o /opt/vcredist/VC_redist.x64.exe \
 && chown -R container:container /opt/vcredist

# Pre-create the game dir owned by container so the named volume mounted here inherits that
# ownership on first use (Docker seeds an empty named volume from the image dir's perms).
RUN mkdir -p /home/container/arkserver \
 && chown container:container /home/container/arkserver

# Same seeding trick for the shared cluster-transfer volume (ark-cluster, docker-compose.yml).
# Mounted SHALLOW at this fixed top-level path (not nested inside arkserver's
# ShooterGame/Saved/clusters) — a nested mount there wouldn't exist yet at container-create time
# (steamcmd hasn't created ShooterGame/Saved/ on first boot), so Docker would root-create the
# missing intermediate dirs INSIDE the already-mounted ark-game volume, blocking the non-root
# user's writes. entrypoint.sh symlinks CLUSTER_DIR to this mount (mirrors config_link).
RUN mkdir -p /home/container/cluster-data \
 && chown container:container /home/container/cluster-data

ENV STEAMCMD_DIR=${STEAMCMD_DIR} \
    ASA_APPID=2430930 \
    ARK_DIR=/home/container/arkserver \
    STEAM_COMPAT_DATA_PATH=/home/container/arkserver/steamapps/compatdata/2430930 \
    STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/.steam/steam \
    SDL_VIDEODRIVER=dummy \
    PROTON_USE_XALIA=0

COPY --chown=container:container entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7777/udp 27020/tcp

USER container
WORKDIR /home/container

# Base provides proton at /usr/local/bin/proton and ENTRYPOINT ["/usr/bin/tini","-g","--"].
# We just point CMD at our script.
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
