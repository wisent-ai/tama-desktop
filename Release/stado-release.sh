#!/bin/bash
set -euo pipefail

UPDATER_SHA256="1f3c919e7e15ef6736a7c9c841ca185cb487e502c0da39be68aa1aa8b487af47"
HOOKS_SHA256="415d6b9824d6fc47a7ebdc4395ed94cb18113c2553251cad50e1f9000d5ab326"
SWIFTPM_SHA256="69afd7557e507caa16f64ac96a723c5daa74091bbe3417e423409634b670ada3"
PRODUCT="Tama"
PRODUCT_SLUG="tama-desktop"
PUBLIC_UPDATE_ROOT="https://updates.wisent.ai"

load_contract() {
  : "${WISENT_VERSION:?WISENT_VERSION is required}"
  : "${WISENT_SOURCE_DIR:?WISENT_SOURCE_DIR is required}"
  : "${WISENT_OUTPUT_DIR:?WISENT_OUTPUT_DIR is required}"
  : "${WISENT_PLATFORM:?WISENT_PLATFORM is required}"
  : "${WISENT_INPUTS_DIR:?WISENT_INPUTS_DIR is required}"
  [ "$WISENT_PLATFORM" = "darwin-arm64" ] || { printf 'unsupported platform: %s\n' "$WISENT_PLATFORM" >&2; exit 1; }
}

verify_input() {
  [ -f "$1" ] || { printf 'missing immutable input: %s\n' "$1" >&2; exit 1; }
  [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$2" ] || { printf 'immutable input digest mismatch: %s\n' "$1" >&2; exit 1; }
}

prepare_source() {
  updater="$WISENT_INPUTS_DIR/wisent-desktop-update.tar.gz"
  hooks="$WISENT_INPUTS_DIR/tama.tar.gz"
  swiftpm="$WISENT_INPUTS_DIR/swiftpm-cache.tar.gz"
  verify_input "$updater" "$UPDATER_SHA256"
  verify_input "$hooks" "$HOOKS_SHA256"
  verify_input "$swiftpm" "$SWIFTPM_SHA256"
  source="$WISENT_SOURCE_DIR"
  work="$WISENT_OUTPUT_DIR/work"
  rm -rf "$work"
  mkdir -p "$work"
  tar -xzf "$hooks" -C "$work"
  tar -xzf "$swiftpm" -C "$source"
  hooks_root="$work/tama"
  [ -f "$hooks_root/package.json" ] || { printf 'immutable hook source is incomplete\n' >&2; exit 1; }
}

compile_source() {
  load_contract
  prepare_source
  swift build --package-path "$source" --configuration release --product Tama --disable-automatic-resolution
}

build_release() {
  load_contract
  : "${MACOS_CERT_P12:?MACOS_CERT_P12 is required}"
  : "${MACOS_CERT_PASSWORD:?MACOS_CERT_PASSWORD is required}"
  : "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY is required}"
  : "${AC_API_KEY_ID:?AC_API_KEY_ID is required}"
  : "${AC_API_ISSUER_ID:?AC_API_ISSUER_ID is required}"
  : "${AC_API_KEY_P8:?AC_API_KEY_P8 is required}"
  : "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"
  : "${TAMA_APP_PROFILE_B64:?TAMA_APP_PROFILE_B64 is required}"
  : "${TAMA_NETWORK_FILTER_PROFILE_B64:?TAMA_NETWORK_FILTER_PROFILE_B64 is required}"
  case "$MACOS_SIGN_IDENTITY" in 'Developer ID Application:'*) ;; *) printf 'Developer ID Application identity required\n' >&2; exit 1 ;; esac
  prepare_source
  release="$WISENT_OUTPUT_DIR/release"
  evidence="$WISENT_OUTPUT_DIR/evidence"
  mkdir -p "$release" "$evidence"
  keychain="$work/release.keychain-db"
  cert="$work/developer-id.p12"
  notary_key="$work/notary-key.p8"
  sparkle_key="$work/sparkle-private-key"
  app_profile="$work/tama-app.provisionprofile"
  network_profile="$work/tama-network-filter.provisionprofile"
  keychain_password="$(uuidgen)"
  cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -f "$cert" "$notary_key" "$sparkle_key" "$app_profile" "$network_profile"
  }
  trap cleanup EXIT
  printf '%s' "$MACOS_CERT_P12" | base64 -D > "$cert"
  printf '%s' "$AC_API_KEY_P8" | base64 -D > "$notary_key"
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$sparkle_key"
  printf '%s' "$TAMA_APP_PROFILE_B64" | base64 -D > "$app_profile"
  printf '%s' "$TAMA_NETWORK_FILTER_PROFILE_B64" | base64 -D > "$network_profile"
  chmod 600 "$notary_key" "$sparkle_key" "$app_profile" "$network_profile"
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$cert" -k "$keychain" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
  security list-keychains -d user -s "$keychain"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null

  TAMA_HOOK_ROOT="$hooks_root" \
  TAMA_RELEASE_VERSION="$WISENT_VERSION" \
  TAMA_BUILD_CHANNEL=stable \
  TAMA_CODESIGN_TIMESTAMP=--timestamp \
  TAMA_INSTALL_AFTER_BUILD=no \
  WISENT_RELEASE_VERSION="$WISENT_VERSION" \
  WISENT_BUILD_NUMBER="$WISENT_VERSION" \
  WISENT_UPDATE_FEED_URL="$PUBLIC_UPDATE_ROOT/$PRODUCT_SLUG/appcast.xml" \
  WISENT_CODESIGN_IDENTITY="$MACOS_SIGN_IDENTITY" \
  WISENT_APP_PROVISIONING_PROFILE="$app_profile" \
  WISENT_NETWORK_FILTER_PROVISIONING_PROFILE="$network_profile" \
    "$source/Scripts/build-app.sh"

  app="$source/.build/$PRODUCT.app"
  [ -d "$app" ] || { printf 'release bundle was not produced: %s\n' "$app" >&2; exit 1; }
  ditto -c -k --keepParent "$app" "$work/notarize.zip"
  xcrun notarytool submit "$work/notarize.zip" --key "$notary_key" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID" --wait --output-format json > "$evidence/notary.json"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"

  staged_app="$release/$PRODUCT.app"
  archive="$release/$PRODUCT.zip"
  ditto "$app" "$staged_app"
  find "$staged_app" -exec touch -h -t 200001010000 {} +
  COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$archive"
  signer="$(find "$source/.build" -type f -path '*/Sparkle/bin/sign_update' -print -quit)"
  [ -x "$signer" ] || { printf 'Sparkle sign_update was not resolved\n' >&2; exit 1; }
  signature_line="$("$signer" --ed-key-file "$sparkle_key" "$archive")"
  case "$signature_line" in *'sparkle:edSignature='*) ;; *) printf 'Sparkle signature was not produced\n' >&2; exit 1 ;; esac
  printf '%s\n' "$signature_line" > "$archive.sparkle-signature"
  archive_name="$PRODUCT-$WISENT_VERSION.zip"
  archive_url="$PUBLIC_UPDATE_ROOT/$PRODUCT_SLUG/$archive_name"
  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' "<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><title>$PRODUCT updates</title><item><title>$PRODUCT $WISENT_VERSION</title><sparkle:version>$WISENT_VERSION</sparkle:version><sparkle:shortVersionString>$WISENT_VERSION</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url=\"$archive_url\" $signature_line type=\"application/octet-stream\"/></item></channel></rss>" > "$release/appcast.xml"
  archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  appcast_sha="$(shasum -a 256 "$release/appcast.xml" | awk '{print $1}')"
  signature_sha="$(shasum -a 256 "$archive.sparkle-signature" | awk '{print $1}')"
  printf '{"schema_version":1,"product":"%s","version":"%s","platform":"%s","archive_sha256":"%s","appcast_sha256":"%s","signature_sha256":"%s","updater_source_sha256":"%s","hooks_source_sha256":"%s","swiftpm_cache_sha256":"%s","notarized":true}\n' "$PRODUCT_SLUG" "$WISENT_VERSION" "$WISENT_PLATFORM" "$archive_sha" "$appcast_sha" "$signature_sha" "$UPDATER_SHA256" "$HOOKS_SHA256" "$SWIFTPM_SHA256" > "$evidence/release.json"
  shasum -a 256 "$archive" "$archive.sparkle-signature" "$release/appcast.xml" > "$evidence/DIGESTS"
}

case "${1:-}" in
  compile) compile_source ;;
  build) build_release ;;
  *) printf 'usage: %s {compile|build}\n' "$0" >&2; exit 64 ;;
esac
