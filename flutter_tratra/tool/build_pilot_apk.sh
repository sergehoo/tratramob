#!/usr/bin/env bash
# APK PILOTE de Tratra pointant vers un backend (staging) — signé avec la clé pilote HORS Git, base d'API figée au build.
#
#   tool/build_pilot_apk.sh --api https://api-staging.exemple.ci/handy [--version 1.0.0-pilot.2] [--build 102] [--skip-tests]
#   tool/build_pilot_apk.sh --api https://api-staging.exemple.ci/handy --check build/pilot/<apk>     # contrôle seul d'un APK existant
#
# Firebase (push) : variables d'environnement FIREBASE_PROJECT_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_API_KEY_ANDROID,
# FIREBASE_APP_ID_ANDROID (valeurs « Paramètres du projet » de la console Firebase de TRATRA — jamais celles d'une autre application).
# Sans elles : l'APK fonctionne, sans push (la notification in-app reste fiable).
#
# Refus (code 1) : base non HTTPS, hôte local / IP / « example », clé de signature absente (jamais de signature « debug »), tests rouges.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

API="" VERSION="1.0.0-pilot.1" BUILD="101" TESTS=1 CHECK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --api) API="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --skip-tests) TESTS=0; shift ;;
    --check) CHECK="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

die() { printf '\033[31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m[ ok ]\033[0m %s\n' "$*"; }

[ -z "$CHECK" ] || TESTS=0     # contrôle seul : ni analyse ni tests

# 1. Base d'API : HTTPS obligatoire (le build release interdit le HTTP en clair), hôte public explicite.
[ -n "$API" ] || die "--api est obligatoire (ex. --api https://api-staging.exemple.ci/handy)."
case "$API" in https://*/handy) ;; *) die "La base doit être de la forme https://<hôte>/handy (reçu : $API)." ;; esac
HOST="${API#https://}"; HOST="${HOST%%/*}"
case "$HOST" in
  localhost|*.localhost|*.local|127.*|10.*|192.168.*|*example*|*.invalid|*.test) die "Hôte « $HOST » refusé : un téléphone ne peut pas joindre une adresse locale ou fictive." ;;
esac
[[ "$HOST" =~ ^[0-9.]+$ ]] && die "Une adresse IP est refusée : utilisez le nom d'hôte HTTPS du staging."
ok "Base d'API : $API"

# 2. Signature : clé pilote hors Git (android/key.properties → ~/.tratra-pilot/tratra-pilot.jks). Jamais de clé debug.
[ -f android/key.properties ] || die "android/key.properties absent : l'APK ne serait pas signé avec la clé pilote."
STORE="$(sed -n 's/^storeFile=//p' android/key.properties | head -1)"
[ -n "$STORE" ] && [ -f "$STORE" ] || die "Keystore introuvable (storeFile dans android/key.properties)."
ok "Clé de signature pilote présente (valeurs non affichées)"

# 3. Firebase : options injectées au build (aucun fichier google-services.json ni identifiant dans Git).
DEFINES=(--dart-define="TRATRA_API_BASE=$API")
FB=0
for k in FIREBASE_PROJECT_ID FIREBASE_MESSAGING_SENDER_ID FIREBASE_API_KEY_ANDROID FIREBASE_APP_ID_ANDROID; do
  if [ -n "${!k:-}" ]; then FB=$((FB + 1)); DEFINES+=(--dart-define="$k=${!k}"); fi
done
if [ "$FB" -eq 4 ]; then ok "Firebase : 4/4 options fournies (push actif)"
elif [ "$FB" -eq 0 ]; then printf '\033[33m[warn]\033[0m Firebase non fourni : APK sans push (voir docs/push-fcm.md).\n'
else die "Firebase incomplet ($FB/4) : fournir les quatre variables ou aucune."; fi

# 4. Qualité : analyse + tests (désactivable pour une reconstruction rapide).
if [ "$TESTS" -eq 1 ]; then
  flutter analyze --no-fatal-infos --no-fatal-warnings lib >/dev/null && ok "flutter analyze : aucune erreur" || die "flutter analyze en erreur."
  flutter test >/dev/null 2>&1 && ok "flutter test : vert" || die "flutter test en échec (relancer sans >/dev/null : flutter test)."
fi

# 6. Contrôles de l'artefact : signature, paquet, base d'API embarquée, absence de HTTP en clair.
verify_artifact() {
  local OUT="$1"
  [ -f "$OUT" ] || die "APK introuvable : $OUT"
  local SDK BT TMP n
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  BT="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$BT" ] && [ -x "$BT/apksigner" ]; then
    "$BT/apksigner" verify --print-certs "$OUT" | grep -E "Signer #1 certificate (DN|SHA-256)" | sed 's/^/        /' && ok "apksigner : signature valide"
  else printf '\033[33m[warn]\033[0m apksigner introuvable : signature non vérifiée automatiquement.\n'; fi
  if [ -n "$BT" ] && [ -x "$BT/aapt2" ]; then
    "$BT/aapt2" dump badging "$OUT" | grep -E "^package:" | sed 's/^/        /'
  fi
  TMP="$(mktemp -d)"
  unzip -q -o "$OUT" 'lib/arm64-v8a/libapp.so' -d "$TMP" 2>/dev/null || true
  if [ -f "$TMP/lib/arm64-v8a/libapp.so" ]; then
    # `grep -c` (jamais `grep -q` derrière un tube : SIGPIPE + pipefail donnerait un faux échec).
    n="$(strings "$TMP/lib/arm64-v8a/libapp.so" | grep -c "https://${HOST}/handy" || true)"
    [ "${n:-0}" -gt 0 ] && ok "Base d'API https://${HOST}/handy figée dans l'application (${n} occurrences)" || { rm -rf "$TMP"; die "L'hôte ${HOST} est absent de l'APK : la base d'API n'a pas été figée."; }
    # Aucune URL d'API en HTTP clair (hors localhost) n'a le droit d'être figée dans un APK pilote.
    n="$(strings "$TMP/lib/arm64-v8a/libapp.so" | grep -cE "http://(api|[a-z0-9.-]+\.(net|ci|com))/handy" || true)"
    [ "${n:-0}" -eq 0 ] && ok "Aucune base d'API en HTTP clair dans l'application" || { rm -rf "$TMP"; die "Une base d'API HTTP en clair est présente dans l'APK."; }
  fi
  rm -rf "$TMP"
}

if [ -n "$CHECK" ]; then verify_artifact "$CHECK"; exit 0; fi

# 5. Construction.
flutter build apk --release --build-name="$VERSION" --build-number="$BUILD" "${DEFINES[@]}"
SRC=build/app/outputs/flutter-apk/app-release.apk
[ -f "$SRC" ] || die "APK introuvable après construction."
mkdir -p build/pilot
OUT="build/pilot/tratra-pilot-${VERSION}-${HOST}.apk"
cp "$SRC" "$OUT"
shasum -a 256 "$OUT" | tee "$OUT.sha256"

verify_artifact "$OUT"
echo
ok "APK pilote : $OUT"
echo "Installation : adb install -r \"$OUT\"   (un com.tratra signé autrement doit d'abord être désinstallé)"
