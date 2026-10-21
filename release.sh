#!/usr/bin/env bash
set -euo pipefail
# Rote release pipeline: Developer ID build, notarize, staple, VirusTotal, GitHub release, Homebrew tap.
# Run locally on the signing Mac. Secrets come from ./release.env (gitignored); see release.env.example.
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml, then commit and push to origin main
# before releasing: the script builds HEAD and tags that same commit, so it stops on a dirty tree or unpushed HEAD.

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

# The tag and its source archives must be the commit that is built: a clean tree, pushed to origin main.
# Untracked files count, because XcodeGen and SwiftPM compile every file in their source folders.
[ -z "$(git status --porcelain)" ] || { echo "ABORT: uncommitted or untracked files; commit and push the release changes first"; git status --short; exit 1; }
git fetch --quiet origin main
COMMIT="$(git rev-parse HEAD)"
[ "${COMMIT}" = "$(git rev-parse origin/main)" ] || { echo "ABORT: HEAD is not origin/main; push the release commit to origin main first"; exit 1; }
remote_tag_commit() { git ls-remote origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}" | awk 'END {print $1}'; }
TAG_COMMIT="$(remote_tag_commit)"
[ -z "${TAG_COMMIT}" ] || [ "${TAG_COMMIT}" = "${COMMIT}" ] || { echo "ABORT: ${TAG} already points at ${TAG_COMMIT}, not HEAD ${COMMIT}; bump the version"; exit 1; }

# One work folder; the build, test and tap trees are removed on exit, the export folder (app, zip, .sha256) is kept.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}/build" "${WORK}/test" "${WORK}/homebrew-tap"' EXIT
BUILD_DIR="${WORK}/build"
TEST_DIR="${WORK}/test"
EXPORT_DIR="${WORK}/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
ZIP_PATH="${EXPORT_DIR}/${ASSET_NAME}"

echo "==> Releasing ${APP_NAME} ${VERSION} (${TAG} at ${COMMIT}) -> ${ASSET_NAME}"

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
# The first public release has nobody to update yet: say so, and present the update path for later versions.
EARLIER_TAGS="$(git ls-remote --tags origin 'refs/tags/v*' | awk '{print $2}' | grep -v -x -F -e "refs/tags/${TAG}" -e "refs/tags/${TAG}^{}" || true)"
# Optional per-release notes, shown after the heading: release-notes/<tag>.md (committed with the release).
WHATS_NEW=""
if [ -f "release-notes/${TAG}.md" ]; then
  WHATS_NEW="$(cat "release-notes/${TAG}.md")

"
fi
if [ -z "${EARLIER_TAGS}" ]; then
  LEAD="First public release of Rote, the keyboard shortcut coach for your Mac.

"
  UPDATE_LABEL="Updating, from this version on"
else
  LEAD=""
  UPDATE_LABEL="Existing users — update in app"
fi

echo "==> 8/9 GitHub release"
NOTES="## Rote ${VERSION}

${LEAD}${WHATS_NEW}**${UPDATE_LABEL}:** click the Rote menu bar icon → **About** → **Download** → **Install and Relaunch** (if no update is listed yet, click **Check Now** first). Rote checks the download against the SHA-256 published here and verifies the app's Developer ID signature before installing it. When \`Rote.app\` belongs to your user (a Homebrew install, or an app you dragged to Applications) it is replaced without a password; an app owned by another account asks for an administrator password. Homebrew: \`brew upgrade --cask rote\`.

**New install:** download \`${ASSET_NAME}\` below, unzip, move **Rote.app** to Applications, launch, and grant Accessibility when asked. Or \`brew install --cask beyondthecode-bc/tap/rote\`.

**Manual fallback:** if the in-app installer is unavailable or fails, quit Rote, replace \`/Applications/Rote.app\` with the unzipped app, and relaunch.

**Requirements:** macOS 14 or later, Apple Silicon or Intel, Accessibility permission.

**Security:** Developer ID signed, hardened runtime, Apple notarized and stapled. VirusTotal: 0 malicious — ${VT_LINK}

**SHA-256** (\`${ASSET_NAME}\`):
\`\`\`
${SHA256}
\`\`\`"
if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  [ "$(remote_tag_commit)" = "${COMMIT}" ] || { echo "ABORT: release ${TAG} exists but its tag is not HEAD ${COMMIT}; not replacing its assets"; exit 1; }
  echo "    Release ${TAG} exists — replacing assets; update the body's SHA-256 to ${SHA256} by hand."
  gh release upload "${TAG}" --repo "${REPO}" --clobber "${ZIP_PATH}" "${ZIP_PATH}.sha256"
else
  gh release create "${TAG}" --repo "${REPO}" --target "${COMMIT}" --title "${APP_NAME} ${VERSION}" --notes "${NOTES}" "${ZIP_PATH}" "${ZIP_PATH}.sha256"
fi

echo "==> 9/9 Homebrew tap"
TAP_DIR="${WORK}/homebrew-tap"
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

  uninstall quit: "com.beyondthecode.rote"

  zap trash: [
    "~/Library/Application Support/Rote",
    "~/Library/Caches/com.beyondthecode.rote",
    "~/Library/HTTPStorages/com.beyondthecode.rote",
    "~/Library/Preferences/com.beyondthecode.rote.plist",
  ]
end
EOF
git -C "${TAP_DIR}" add Casks/rote.rb
git -C "${TAP_DIR}" -c user.name="Vlad" -c user.email="62696158+beyondthecode-bc@users.noreply.github.com" commit -m "rote ${VERSION}"
git -C "${TAP_DIR}" push
echo "==> Done. ${APP_NAME} ${VERSION}  SHA256=${SHA256}  VT=${VT_LINK}"
echo "    Release files: ${EXPORT_DIR}"
echo "    Now read the live release body back and verify the update paths, asset name, VT result and checksum."
