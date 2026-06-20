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

ARG STEAMCMD_DIR=/opt/steamcmd
RUN mkdir -p ${STEAMCMD_DIR} \
 && curl -sL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
      | tar -xz -C ${STEAMCMD_DIR} \
 && chown -R container:container ${STEAMCMD_DIR}

# Pre-create the game dir owned by container so the named volume mounted here inherits that
# ownership on first use (Docker seeds an empty named volume from the image dir's perms).
RUN mkdir -p /home/container/arkserver \
 && chown container:container /home/container/arkserver

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
