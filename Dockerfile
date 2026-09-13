# Space Engineers dedicated server — combines two confirmed-real sources
# rather than guessing:
#   1. scottyhardy/docker-wine:stable-8.0.2 as the base — confirmed to
#      exactly match the Wine version sknnr's own real, running image
#      actually uses (`wine --version` run directly against the real
#      image returned wine-8.0.2 on Debian 12). The specific winetricks
#      workarounds below were tested against this exact Wine version, not
#      a newer one — matching it precisely rather than substituting a
#      different version.
#   2. sknnr/space-engineers-dedicated-server's own winetricks.sh and
#      entrypoint.sh, pulled directly from the real running image —
#      these contain specific, hard-won workarounds a from-scratch build
#      wouldn't know about (disabling mscoree during initial boot, win10
#      version emulation, vcrun2019, disabled audio).
#
# Two real bugs in the original entrypoint.sh are fixed here — several
# paths were hardcoded to /home/steam/space-engineers instead of using
# $SE_PATH, confirmed directly from the pulled script content, which
# broke pointing this at this panel's actual persistent volume
# (/home/container). Also added automatic default-world generation,
# since the original required a pre-made world to already exist and
# would just exit with an error otherwise.
FROM scottyhardy/docker-wine:stable-8.0.2

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV SE_PATH=/home/container/space-engineers
ENV WINEARCH=win64

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# steamcmd — needed for the actual game file download, confirmed from the
# real entrypoint.sh's own steamcmd invocation
RUN mkdir -p /home/steam/steamcmd && \
    wget -qO- "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar -xz -C /home/steam/steamcmd

# Robust user creation — the base image may already have a non-root
# user at UID 1000 (confirmed from earlier logs tonight showing a
# pre-existing "wineuser" in this same image family). Rather than a
# fragile conditional that can silently fail to actually create the
# user (confirmed via a real failed build — the check step reported
# success but "steam" didn't actually exist afterward), this explicitly
# creates a group only if GID 1000 is free, then creates the steam user
# regardless of what UID it lands on, and prints the result so failures
# are visible rather than silent.
RUN set -e; \
    if ! getent group 1000 >/dev/null; then groupadd -g 1000 steam; else groupadd steam; fi; \
    if ! id -u steam >/dev/null 2>&1; then useradd -g steam -m -s /bin/bash steam; fi; \
    id steam

RUN mkdir -p /home/steam && chown -R steam:steam /home/steam

COPY winetricks.sh /home/steam/winetricks.sh
COPY entrypoint.sh /home/steam/entrypoint.sh
COPY default-world.zip /home/steam/default-world.zip
RUN chmod +x /home/steam/winetricks.sh /home/steam/entrypoint.sh && chown steam:steam /home/steam/*.sh /home/steam/default-world.zip

# Bake the fully-configured Wine prefix (.NET, corefonts, vcrun2019, etc)
# into the image at build time instead of doing it on every first boot —
# confirmed this is what sknnr's original image's own unusually large
# "mkdir" layer was actually doing (773MB for a plain mkdir is not
# normal). Baked inside /home/steam (already correctly owned by steam at
# this point in the build) rather than /opt — a real build failure
# caught this: /opt is root-owned, and Wine's own ownership check
# refuses to create a config directory under a path it doesn't own, same
# class of issue fixed earlier tonight for the plain-Wine attempt, just
# in a different location this time.
ENV WINEPREFIX=/home/steam/.space_engineers_prefix_baked
USER steam
RUN /home/steam/winetricks.sh

WORKDIR /home/steam
ENTRYPOINT ["/home/steam/entrypoint.sh"]
