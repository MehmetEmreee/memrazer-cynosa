#!/bin/zsh
# SPDX-License-Identifier: GPL-2.0-or-later
# Packages build/memrazer-cynosa.app into a DMG; signs and notarizes it when credentials are set.
#
#   SIGN_IDENTITY   "Developer ID Application: …" (omit for an unsigned local DMG)
#   Notarization, either:
#     NOTARY_PROFILE                              keychain profile from `xcrun notarytool store-credentials`
#     NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   App Store Connect API key
set -euo pipefail
cd "${0:A:h}/.."

NAME=memrazer-cynosa
VERSION=${VERSION:-1.2.0}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
APP=build/$NAME.app
DMG=build/$NAME-$VERSION.dmg
STAGE=build/dmg

[[ -d "$APP" ]] || { echo "missing $APP, run scripts/build-app.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  else
    echo "warning: signed but not notarized (no notary credentials)" >&2
  fi
  [[ -n "${NOTARY_PROFILE:-}${NOTARY_KEY_PATH:-}" ]] && xcrun stapler staple "$DMG"
fi

(cd build && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
echo "$DMG"
