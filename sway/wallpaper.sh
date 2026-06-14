#!/bin/bash

WALL="$HOME/Pictures/Wallpaper/Main.png"

if [ -f "$WALL" ]; then
    swaymsg output "*" bg "$WALL" fill
else
    # fallback 
  swaymsg output "*" bg /usr/share/backgrounds/sway/Sway_Wallpaper_Blue_1920x1080.png fill
fi
