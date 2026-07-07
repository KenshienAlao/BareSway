#!/bin/bash

DIR="$HOME/Pictures/Wallpaper"

CHOICE=$(
find "$DIR" -type f \
  \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) |
while read -r file; do
    basename "${file%.*}"
done |
sort |
wofi --dmenu --prompt "Wallpaper"
)

[ -z "$CHOICE" ] && exit 0

FILE=$(find "$DIR" -type f \
  \( -iname "$CHOICE.jpg" -o \
     -iname "$CHOICE.jpeg" -o \
     -iname "$CHOICE.png" -o \
     -iname "$CHOICE.webp" \) \
  | head -n1)

[ -n "$FILE" ] && awww img "$FILE"