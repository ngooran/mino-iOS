#!/bin/zsh
# Raw store captures for the ShotKit set in screenshots/story.
#
# Every screen is opened with DEBUG launch arguments (Mino/App/DebugLaunch.swift); nothing is
# tapped. The sandbox store (-demoSandbox) is wiped and refilled with sample files on every
# launch, so the simulators are not erased and a device's real files never show.
#
#   screenshots/capture.sh                 all devices
#   screenshots/capture.sh iPhone          one device folder: iPhone, iPad or Duo-inner
#   SHOTS_ONLY="04_Photos 07_Edit" screenshots/capture.sh     only these shots
#   LOC=de screenshots/capture.sh          another language: en (default), de, es
#
# Writes screenshots/raw/<device>/en/<shot>.png (git-ignored). Needs a Debug simulator build:
#   xcodebuild -project Mino.xcodeproj -scheme Mino -sdk iphonesimulator \
#     -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/WarnData build
#
# Rules this follows (ShotKit docs/rules.md, docs/capture.md):
# - No frame may say "free": free tools run with -demoFree -demoHideAllowance, which keeps the
#   PRO badges and hides "free actions left today". Pro tools run with -demoPro.
# - Simulators are found by name. simctl cannot write to an external volume, so each shot goes
#   to a temp folder first. A blank shot is retried and never written over a good one.

set -euo pipefail
ROOT="${0:A:h:h}"
APP="$ROOT/build/WarnData/Build/Products/Debug-iphonesimulator/Mino.app"
OUT="$ROOT/screenshots/raw"
TMP="$(mktemp -d)"
PY=/opt/homebrew/bin/python3
LOC="${LOC:-en}"
# The app's language and the region whose number and date formats the store page uses.
case $LOC in
  en) REGION=en_US ;;
  de) REGION=de_DE ;;
  es) REGION=es_ES ;;
  fr) REGION=fr_FR ;;
  *) echo "Unknown LOC $LOC"; exit 1 ;;
esac
SAMPLES="$ROOT/screenshots/samples"   # sample photos and the Word file (make_photos.py)

[[ -d "$APP" ]] || { echo "No Debug simulator build at $APP"; exit 1; }

# folder, simulator name
DEVICES=(
  "iPhone|iPhone 18 Pro"
  "iPad|iPad Pro 13-inch (M5)"
  "Duo-inner|iPhone Duo"
)

# shot name | seconds to wait | launch arguments. The slot order lives in story/set.js.
FREE=(-demoFree -demoHideAllowance)
SHOTS=(
  "01_Home|16|${FREE[*]} -demoScreen home"
  "02_Scan|18|${FREE[*]} -demoScreen scan"
  "03_Sign|18|-demoPro -demoScreen sign"
  "04_Photos|20|${FREE[*]} -demoScreen photos -demoPhotos @PHOTOS@"
  "05_Office|18|-demoPro -demoScreen office -demoFile @DOCX@"
  "06_Compress|20|${FREE[*]} -demoScreen compress"
  "07_Edit|18|-demoPro -demoScreen edit -demoNoWhiteout"
  "08_Organize|18|${FREE[*]} -demoScreen organize"
  "09_OCR|32|-demoPro -demoScreen ocr -demoRun"
  "10_Images|18|${FREE[*]} -demoScreen images"
)

udid() {
  xcrun simctl list devices available -j | $PY -I -c "
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)['devices'].items():
    for d in devices:
        if d['name'] == name and d['isAvailable']:
            print(d['udid']); sys.exit()
sys.exit('no simulator named ' + name)" "$1"
}

# A shot that is one flat colour (a black Duo panel, a launch that never drew) is not a capture.
is_blank() {
  $PY -I -c "
import sys
from PIL import Image, ImageStat
im = Image.open(sys.argv[1]).convert('L').resize((200, 200))
sys.exit(0 if ImageStat.Stat(im).stddev[0] < 4 else 1)" "$1"
}

capture() {
  local folder=$1 name=$2 u=$3 file=$4
  if [[ $folder == Duo-inner ]]; then
    xcrun simctl io "$u" screenshot --display=primary-1 "$file" >/dev/null 2>&1
  else
    xcrun simctl io "$u" screenshot "$file" >/dev/null 2>&1
  fi
}

only="${1:-}"
for entry in "${DEVICES[@]}"; do
  folder="${entry%%|*}"; name="${entry#*|}"
  [[ -n $only && $only != $folder ]] && continue
  u="$(udid "$name")"
  echo "== $folder ($name, $u)"
  state="$(xcrun simctl list devices | grep "$u" | grep -c Booted || true)"
  [[ $state == 0 ]] && { xcrun simctl boot "$u"; sleep 20; }
  xcrun simctl ui "$u" appearance light
  xcrun simctl status_bar "$u" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode notSupported
  [[ $folder == Duo-inner ]] && { hinge -d "$u" open; sleep 4; }
  xcrun simctl install "$u" "$APP"
  mkdir -p "$OUT/$folder/$LOC"

  for shot in "${SHOTS[@]}"; do
    file="${shot%%|*}"; rest="${shot#*|}"; wait="${rest%%|*}"; args=(${=rest#*|})
    [[ -n ${SHOTS_ONLY:-} && " $SHOTS_ONLY " != *" $file "* ]] && continue
    # Paths go in after the split: the repo path has spaces.
    args=("${(@)args/@PHOTOS@/$SAMPLES/photos}"); args=("${(@)args/@DOCX@/$SAMPLES/Project Proposal.docx}")
    for attempt in 1 2 3; do
      # The language and region of this store page, whatever the simulator's own settings.
      xcrun simctl launch --terminate-running-process "$u" com.applestan.Mino \
        -AppleLanguages "($LOC)" -AppleLocale "$REGION" \
        -demoSandbox -demoAppearance light "${args[@]}" >/dev/null
      sleep $(( wait + (attempt - 1) * 10 ))
      capture "$folder" "$name" "$u" "$TMP/$file.png"
      if is_blank "$TMP/$file.png"; then
        echo "   $file: blank, trying again"; continue
      fi
      mv "$TMP/$file.png" "$OUT/$folder/$LOC/$file.png"
      echo "   $file"
      break
    done
  done
  xcrun simctl terminate "$u" com.applestan.Mino 2>/dev/null || true
done
rm -rf "$TMP"
echo "done: $OUT"
