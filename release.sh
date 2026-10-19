#!/usr/bin/env bash
set -euo pipefail
# Rote release pipeline: Developer ID build, notarize, staple, VirusTotal, GitHub release, Homebrew tap.
# Run locally on the signing Mac. Secrets come from ./release.env (gitignored); see release.env.example.
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml before releasing.

cd "$(dirname "$0")"
[ -f release.env ] || { echo "ABORT: release.env missing (copy release.env.example)"; exit 1; }
# shellcheck disable=SC1091
source release.env
: "${IDENTITY:?}" "${TEAM_ID:?}" "${P8:?}" "${KEY_ID:?}" "${ISSUER:?}"
: "${VT_API_KEY:?Set VT_API_KEY in release.env or the environment}"

APP_NAME="Rote"
SCHEME="Rote"
BUNDLE_ID="com.beyondthecode.rote"
REPO="beyondthecode-bc/Rote"
TAP_REPO="beyondthecode-bc/homebrew-tap"
APP_ENTITLEMENTS="Rote/App/Rote.entitlements"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "${VERSION}" ] || { echo "ABORT: could not read MARKETING_VERSION from project.yml"; exit 1; }
TAG="v${VERSION}"
ASSET_NAME="${APP_NAME}-v${VERSION}.zip"
BUILD_DIR="$(mktemp -d)/build"
TEST_DIR="$(mktemp -d)/test"
EXPORT_DIR="$(mktemp -d)/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
ZIP_PATH="${EXPORT_DIR}/${ASSET_NAME}"

echo "==> Releasing ${APP_NAME} ${VERSION} (${TAG}) -> ${ASSET_NAME}"

echo "==> 1/9 Language check + tests (RoteCore, RoteAX, app)"
python3 scripts/check-languages.py
swift test --package-path Packages/RoteCore
swift test --package-path Packages/RoteAX
xcodegen generate
xcodebuild test \
  -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" -destination 'platform=macOS' \
  -derivedDataPath "${TEST_DIR}" CODE_SIGN_IDENTITY="-"

echo "==> 2/9 xcodegen + Release build (Developer ID, hardened runtime)"
xcodegen generate
xcodebuild \
  -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${IDENTITY}" DEVELOPMENT_TEAM="${TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
  clean build
mkdir -p "${EXPORT_DIR}"
cp -R "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" "${APP_PATH}"

echo "==> 3/9 Codesign (never --deep)"
codesign --force --options runtime --timestamp --entitlements "${APP_ENTITLEMENTS}" --sign "${IDENTITY}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo "==> 4/9 Notarize"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
xcrun notarytool submit "${ZIP_PATH}" --key "${P8}" --key-id "${KEY_ID}" --issuer "${ISSUER}" --wait

echo "==> 5/9 Staple + verify"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl -a -vvv -t exec "${APP_PATH}" || true

echo "==> 6/9 Re-zip stapled app + checksum"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
echo "${SHA256}  ${ASSET_NAME}" > "${ZIP_PATH}.sha256"
echo "    SHA-256: ${SHA256}"

echo "==> 7/9 VirusTotal (abort unless 0 malicious)"
VT_UP="$(curl -s -X POST https://www.virustotal.com/api/v3/files -H "x-apikey: ${VT_API_KEY}" --form "file=@${ZIP_PATH}")"
VT_ID="$(printf '%s' "${VT_UP}" | /usr/bin/python3 -c 'import sys,json
d=json.load(sys.stdin)
if "data" not in d: sys.stderr.write("VT upload failed: %s\n"%json.dumps(d)); sys.exit(1)
print(d["data"]["id"])')"
VT_DONE=0
for _ in $(seq 1 30); do
  VT_J="$(curl -s -H "x-apikey: ${VT_API_KEY}" "https://www.virustotal.com/api/v3/analyses/${VT_ID}")"
  VT_ST="$(printf '%s' "${VT_J}" | /usr/bin/python3 -c 'import sys,json
try: print(json.load(sys.stdin)["data"]["attributes"]["status"])
except Exception: print("pending")')"
  if [ "${VT_ST}" = "completed" ]; then
    VT_MAL="$(printf '%s' "${VT_J}" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["attributes"]["stats"]["malicious"])')"
    echo "    VirusTotal malicious: ${VT_MAL}"
    [ "${VT_MAL}" = "0" ] || { echo "ABORT: VirusTotal flagged ${VT_MAL} engines."; exit 1; }
    VT_DONE=1; break
  fi
  echo "    VT status=${VT_ST}; waiting 10s…"; sleep 10
done
[ "${VT_DONE}" = "1" ] || { echo "ABORT: VirusTotal did not complete — not publishing."; exit 1; }
VT_LINK="https://www.virustotal.com/gui/file/${SHA256}"

echo "==> 8/9 GitHub release"
NOTES="## Rote ${VERSION}

**Existing users — update in app:** click the Rote menu bar icon → **About** → **Check Now** → **Download** → **Install and Relaunch** (macOS asks for an administrator password to replace the app). Homebrew: \`brew upgrade --cask rote\`.

**New install:** download \`${ASSET_NAME}\` below, unzip, move **Rote.app** to Applications, launch, and grant Accessibility when asked. Or \`brew install --cask beyondthecode-bc/tap/rote\`.

**Manual fallback:** if the in-app installer is unavailable or fails, quit Rote, replace \`/Applications/Rote.app\` with the unzipped app, and relaunch.

**Requirements:** macOS 14 or later, Apple Silicon or Intel, Accessibility permission.

**Security:** Developer ID signed, hardened runtime, Apple notarized and stapled. VirusTotal: 0 malicious — ${VT_LINK}

**SHA-256** (\`${ASSET_NAME}\`):
\`\`\`
${SHA256}
\`\`\`"
if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  echo "    Release ${TAG} exists — replacing assets; update the body's SHA-256 to ${SHA256} by hand."
  gh release upload "${TAG}" --repo "${REPO}" --clobber "${ZIP_PATH}" "${ZIP_PATH}.sha256"
else
  gh release create "${TAG}" --repo "${REPO}" --title "${APP_NAME} ${VERSION}" --notes "${NOTES}" "${ZIP_PATH}" "${ZIP_PATH}.sha256"
fi

echo "==> 9/9 Homebrew tap"
TAP_DIR="$(mktemp -d)/homebrew-tap"
git clone --depth 1 "https://github.com/${TAP_REPO}.git" "${TAP_DIR}"
mkdir -p "${TAP_DIR}/Casks"
cat > "${TAP_DIR}/Casks/rote.rb" <<EOF
cask "rote" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${REPO}/releases/download/v#{version}/Rote-v#{version}.zip"
  name "Rote"
  desc "Keyboard shortcut coach that teaches you the shortcuts you keep skipping"
  homepage "https://github.com/${REPO}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Rote.app"

  zap trash: [
    "~/Library/Application Support/Rote",
    "~/Library/Preferences/com.beyondthecode.rote.plist",
  ]
end
EOF
git -C "${TAP_DIR}" add Casks/rote.rb
git -C "${TAP_DIR}" -c user.name="Vlad" -c user.email="62696158+beyondthecode-bc@users.noreply.github.com" commit -m "rote ${VERSION}"
git -C "${TAP_DIR}" push
echo "==> Done. ${APP_NAME} ${VERSION}  SHA256=${SHA256}  VT=${VT_LINK}"
echo "    Now read the live release body back and verify the update paths, asset name, VT result and checksum."
