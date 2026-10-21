#!/usr/bin/env bash
# Bundle PLAY STORE (.aab) de Tratra, signé avec la clé d'UPLOAD (hors Git : ~/.tratra-play/upload.properties), API de production figée au build.
#
#   tool/build_play_aab.sh [--api https://api.tratra.net/handy] [--version 1.0.0] [--build 1] [--skip-tests] [--verify-only]
#
# Refus (code 1) : base non HTTPS ou locale, clé d'upload absente, tests rouges, bundle non signé par la clé d'upload.
# Firebase (push) : android/app/google-services.json (hors Git, client com.tratra) ou mêmes variables que build_pilot_apk.sh
# (FIREBASE_PROJECT_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_API_KEY_ANDROID, FIREBASE_APP_ID_ANDROID) ; sans eux, bundle sans push.
# Le numéro de build (versionCode) doit AUGMENTER à chaque envoi sur Play : --build N.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

API="https://api.tratra.net/handy" VERSION="1.0.0" BUILD="1" TESTS=1 BUILDIT=1
PROPS="${TRATRA_UPLOAD_PROPERTIES:-$HOME/.tratra-play/upload.properties}"
while [ $# -gt 0 ]; do
  case "$1" in
    --api) API="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --skip-tests) TESTS=0; shift ;;
    --verify-only) BUILDIT=0; TESTS=0; shift ;;     # contrôle seul du dernier bundle construit
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done
die() { printf '\033[31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m[ ok ]\033[0m %s\n' "$*"; }

case "$API" in https://*/handy) ;; *) die "La base d'API doit être de la forme https://<hôte>/handy (reçu : $API)." ;; esac
HOST="${API#https://}"; HOST="${HOST%%/*}"
case "$HOST" in localhost|*.localhost|*.local|127.*|10.*|192.168.*|*example*|*.invalid|*.test) die "Hôte « $HOST » refusé pour un bundle de production." ;; esac
[[ "$HOST" =~ ^[0-9.]+$ ]] && die "Une adresse IP est refusée : utilisez le nom d'hôte HTTPS."
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "--build doit être un entier (versionCode)."
ok "API : $API · version $VERSION ($BUILD)"

[ -f "$PROPS" ] || die "Clé d'upload absente : $PROPS"
STORE="$(sed -n 's/^storeFile=//p' "$PROPS" | head -1)"
[ -n "$STORE" ] && [ -f "$STORE" ] || die "Keystore d'upload introuvable (storeFile)."
ok "Clé d'upload présente (valeurs non affichées)"

DEFINES=(--dart-define="TRATRA_API_BASE=$API")
FB=0
for k in FIREBASE_PROJECT_ID FIREBASE_MESSAGING_SENDER_ID FIREBASE_API_KEY_ANDROID FIREBASE_APP_ID_ANDROID; do
  if [ -n "${!k:-}" ]; then FB=$((FB + 1)); DEFINES+=(--dart-define="$k=${!k}"); fi
done
GS="android/app/google-services.json" PUSH=1
if [ "$FB" -eq 4 ]; then ok "Firebase : 4/4 options fournies (push actif)"
elif [ "$FB" -ne 0 ]; then die "Firebase incomplet ($FB/4) : fournir les quatre variables ou aucune."
elif [ -f "$GS" ] && grep -q '"package_name": *"com.tratra"' "$GS"; then ok "Firebase : $GS (client com.tratra, push actif)"
else PUSH=0; printf '\033[33m[warn]\033[0m Firebase non fourni : bundle sans push.\n'; fi

if [ "$TESTS" -eq 1 ]; then
  flutter analyze --no-fatal-infos >/dev/null && ok "flutter analyze" || die "flutter analyze en échec"
  flutter test >/dev/null 2>&1 && ok "flutter test" || die "flutter test en échec"
fi

export TRATRA_SIGNING_PROPERTIES="$PROPS"
[ "$BUILDIT" -eq 0 ] || flutter build appbundle --release --build-name "$VERSION" --build-number "$BUILD" "${DEFINES[@]}"
AAB="build/app/outputs/bundle/release/app-release.aab"
[ -f "$AAB" ] || die "Bundle introuvable : $AAB"

# Le bundle doit être signé par la clé d'upload (et jamais par la clé de débogage).
CERT="$(keytool -printcert -jarfile "$AAB" 2>/dev/null | sed -n -E 's/^[[:space:]]*SHA[ -]?256[[:space:]]*:[[:space:]]*//p' | head -1)"
EXPECT="$(keytool -list -v -keystore "$STORE" -storepass "$(sed -n 's/^storePassword=//p' "$PROPS")" 2>/dev/null | sed -n -E 's/^[[:space:]]*SHA[ -]?256[[:space:]]*:[[:space:]]*//p' | head -1)"
[ -n "$CERT" ] && [ "$CERT" = "$EXPECT" ] || die "Le bundle n'est pas signé par la clé d'upload."
ok "Bundle signé par la clé d'upload — empreinte SHA-256 : $CERT"
if [ "$PUSH" -eq 1 ] && [ "$FB" -eq 0 ]; then
  N="$(unzip -p "$AAB" base/resources.pb 2>/dev/null | grep -ac google_app_id || true)"   # -c lit tout (pas de SIGPIPE avec pipefail)
  [ "${N:-0}" -gt 0 ] && ok "Configuration Firebase présente dans le bundle" \
    || die "google-services.json non appliqué : le bundle n'a pas de configuration Firebase."
fi
ls -l "$AAB" | awk '{printf "[ ok ] %s (%.1f Mo)\n", $NF, $5/1048576}'
