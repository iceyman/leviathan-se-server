#!/bin/bash
# Pulled directly from the real sknnr/space-engineers-dedicated-server
# image via `docker run --rm ... cat`. Used verbatim, unchanged — these
# are specific, hard-won Wine workarounds for this exact game (disabling
# mscoree during initial boot to avoid the .NET crash confirmed earlier
# tonight with a from-scratch build, win10 version emulation, vcrun2019,
# disabled audio) that a from-scratch build wouldn't have known to include.
export DISPLAY=:1.0

Xvfb :1 -screen 0 1024x768x16 &
env WINEDLLOVERRIDES="mscoree=d" wineboot --init /nogui
winetricks corefonts
winetricks sound=disabled
winetricks -q --force vcrun2019
winetricks -q --force dotnet48
wine winecfg -v win10
rm -rf /home/steam/.cache
