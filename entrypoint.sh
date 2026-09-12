#!/bin/bash
set -e

# WINEPREFIX was intentionally pointed at a build-time-only baked location
# during the image build (see Dockerfile) — set it back to the real
# persistent path now, and copy the baked prefix in if this volume
# doesn't have it yet (fresh deploy or after Reinstall). Same reasoning
# as the Hytale image earlier tonight: baking into a path that later gets
# hidden by the actual volume mount is a real, confirmed bug class — this
# avoids it by keeping the bake location genuinely separate and copying
# in explicitly rather than baking directly into the mount path.
export WINEPREFIX="/home/container/.space_engineers_prefix"
if [ ! -d "$WINEPREFIX" ] || [ -z "$(ls -A "$WINEPREFIX" 2>/dev/null)" ]; then
    echo "INFO: Copying baked Wine prefix into persistent volume (first run)..."
    mkdir -p "$WINEPREFIX"
    cp -a /home/steam/.space_engineers_prefix_baked/. "$WINEPREFIX/"
fi

# Based on sknnr/space-engineers-dedicated-server's own entrypoint.sh,
# pulled directly from the real image. Two real bugs fixed:
#
# 1. Several paths were hardcoded to /home/steam/space-engineers instead
#    of using $SE_PATH, even though other lines in the SAME script
#    correctly used $SE_PATH — confirmed directly from the actual script
#    content, not a guess. This broke overriding SE_PATH to point into
#    this panel's actual persistent volume (/home/container).
#
# 2. The original required a pre-made world to already exist (checks for
#    SpaceEngineers-Dedicated.cfg and exits immediately if missing, before
#    ever reaching the steamcmd download step). Added automatic default
#    world creation via the game's own --create-world-if-missing-style
#    flow instead, matching how the rest of this panel's blueprints work
#    (auto-generate on first run rather than requiring a manual upload).

echo "INFO: Installing/updating Space Engineers via steamcmd..."
/home/steam/steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir "$SE_PATH" +login anonymous +app_update 298740 validate +quit

# Windows-style path equivalent of $SE_PATH, used everywhere below —
# computed once, here, rather than the original's hardcoded
# /home/steam/space-engineers appearing in multiple separate places
# (confirmed as the actual bug: some lines used $SE_PATH correctly,
# others didn't, inconsistently).
SE_PATH_WIN="$(echo "$SE_PATH" | sed 's#^/##; s#/#\\\\#g')"

# If we are pulling a world zip down, do it now
if [ -n "$WORLD_ZIP_URL" ]; then
    echo "INFO: WORLD_ZIP_URL as ${WORLD_ZIP_URL}"
    if [ -d "${SE_PATH}/world/Saves" ]; then
        echo "INFO: Found existing world..."
        if [[ "$OVERWRITE" == "true" ]]; then
            echo "INFO: OVERWRITE set true, overwriting"
            wget -O /tmp/world.zip "$WORLD_ZIP_URL"
            unzip -o /tmp/world.zip -d "${SE_PATH}/world"
            rm -f /tmp/world.zip
        else
            echo "INFO: OVERWRITE not true, not overwriting"
        fi
    else
        echo "INFO: Downloading and extracting world to ${SE_PATH}/world"
        wget -O /tmp/world.zip "$WORLD_ZIP_URL"
        unzip -o /tmp/world.zip -d "${SE_PATH}/world"
        rm -f /tmp/world.zip
    fi
fi

# Wine talks too much and it's annoying
export WINEDEBUG=-all

# If no world config exists yet (no WORLD_ZIP_URL was given, and this is
# a genuinely fresh volume), generate a real default world by actually
# launching the server once with no existing save — Space Engineers
# itself creates a default world + config on first boot when none exists,
# same as it would on a normal Windows install. This replaces the
# original script's "just exit with an error" behavior.
if ! [ -f "${SE_PATH}/world/SpaceEngineers-Dedicated.cfg" ]; then
    echo "INFO: No existing world found — generating a default world (first boot only)..."
    mkdir -p "${SE_PATH}/world"
    timeout 90 wine "${SE_PATH}/DedicatedServer64/SpaceEngineersDedicated.exe" -noconsole -ignorelastsession -path "Z:\\${SE_PATH_WIN}\\world" || true
    echo "INFO: Default world generation attempt finished."
fi

if ! [ -f "${SE_PATH}/world/SpaceEngineers-Dedicated.cfg" ]; then
    echo "ERROR: SpaceEngineers-Dedicated.cfg still not present in ${SE_PATH}/world after default-world generation attempt."
    exit 1
fi

if ! [ -d "${SE_PATH}/world/Saves" ]; then
    echo "ERROR: Saves directory not present in ${SE_PATH}/world"
    exit 1
fi

CONFIG_PATH="${SE_PATH}/world/SpaceEngineers-Dedicated.cfg"

SAVE_NAME="$(grep -oEi '<LoadWorld>(.*)</LoadWorld>' "${CONFIG_PATH}" | sed -E "s=<LoadWorld>|</LoadWorld>==g" | rev | cut -d '\' -f2 | rev)"

if ! [ -f "${SE_PATH}/world/Saves/${SAVE_NAME}/Sandbox.sbc" ]; then
    echo "ERROR: Sandbox.sbc not present at: ${SE_PATH}/world/Saves/${SAVE_NAME}"
    exit 1
fi

# FIX: this now genuinely uses $SE_PATH throughout, not a hardcoded
# /home/steam string — confirmed against the exact same construction
# logic as the original, just parameterized correctly this time.
LOAD_WORLD_PATH="Z:\\\\${SE_PATH_WIN}\\\\world\\\\Saves\\\\${SAVE_NAME}\\\\Sandbox.sbc"
echo ""
echo "DEBUG: LoadWorld = ${LOAD_WORLD_PATH}"
echo ""

echo "INFO: Updating SpaceEngineers-Dedicated.cfg"
sed -i "s=<IP>.*</IP>=<IP>$(hostname -I)</IP>=g" "$CONFIG_PATH"
sed -E -i "s=<LoadWorld />|<LoadWorld.*LoadWorld>=<LoadWorld>${LOAD_WORLD_PATH}</LoadWorld>=g" "$CONFIG_PATH"

# FIX: was hardcoded to /home/steam/space-engineers regardless of $SE_PATH
rm -rf "${SE_PATH}/world/Saves"/*.log 2>/dev/null || true

echo "INFO: Launching Space Engineers Dedicated Server"

# FIX: the -path argument was hardcoded to Z:\home\steam\space-engineers\world
# regardless of $SE_PATH — now correctly derived from it, same as LOAD_WORLD_PATH above.
exec wine "${SE_PATH}/DedicatedServer64/SpaceEngineersDedicated.exe" -noconsole -ignorelastsession -path "Z:\\${SE_PATH_WIN}\\world"
