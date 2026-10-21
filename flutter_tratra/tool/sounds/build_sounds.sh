#!/usr/bin/env bash
# Régénère l'identité sonore Tratra et l'installe dans l'application :
#   Android : android/app/src/main/res/raw/<nom>.ogg (Vorbis, lu par les canaux de notification et le lecteur natif)
#   iOS     : ios/Runner/<nom>.caf (PCM 16 bits, format accepté par APNs ; < 30 s)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
python3 tool/sounds/generate_tratra_sounds.py
mkdir -p android/app/src/main/res/raw
for name in tratra_flash tratra_notification; do
  ffmpeg -loglevel error -y -i "tool/sounds/$name.wav" -c:a libvorbis -q:a 6 "android/app/src/main/res/raw/$name.ogg"
  afconvert -f caff -d LEI16@44100 -c 1 "tool/sounds/$name.wav" "ios/Runner/$name.caf"
done
ls -l android/app/src/main/res/raw/*.ogg ios/Runner/*.caf
