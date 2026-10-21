#!/usr/bin/env bash
set -euo pipefail
# Rote release pipeline: Developer ID build, notarize, staple, VirusTotal, GitHub release, Homebrew tap.
# Run locally on the signing Mac. Secrets come from ./release.env (gitignored); see release.env.example.
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml, then commit and push to origin main
# before releasing: the script builds HEAD and tags that same commit, so it stops on a dirty tree or unpushed HEAD.
#
# A version is released once. A tag or release that already exists for it aborts the run; a re-cut bumps the
# patch version. The release is created as a draft, read back and compared to the local build, and only then
# published, followed by the Homebrew tap. Before building, the files that decide what ships signed (listed in
# RELEASE_CRITICAL) are diffed against the previous release tag and shown for an explicit "y".
#
# Sourcing this file defines its functions without releasing anything (used to dry-run the gate and the notes).

cd "$(dirname "$0")"

APP_NAME="Rote"
SCHEME="Rote"
BUNDLE_ID="com.beyondthecode.rote"
REPO="beyondthecode-bc/Rote"
TAP_REPO="beyondthecode-bc/homebrew-tap"
APP_ENTITLEMENTS="Rote/App/Rote.entitlements"
# The Team ID the shipped signature must carry; the updater only installs bundles signed by this team.
EXPECTED_TEAM_ID="KHCY27H5KH"
# Files that decide what ships signed and notarized, or how it is built, tested and released (mirrors CODEOWNERS).
RELEASE_CRITICAL=(project.yml Config "${APP_ENTITLEMENTS}" Rote/App/Info.plist Rote/Engine/GitHubUpdateChecker.swift .github release.sh scripts)

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "${VERSION}" ] || { echo "ABORT: could not read MARKETING_VERSION from project.yml"; exit 1; }
TAG="v${VERSION}"
ASSET_NAME="${APP_NAME}-v${VERSION}.zip"

# The commit the tag points at on origin (peeled, so a signed tag resolves to its commit), or empty.
remote_tag_commit() { git ls-remote origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}" | awk 'END {print $1}'; }

# Fetches origin's v* tags and prints the highest version tag below TAG, or nothing for a first release.
previous_release_tag() {
  git fetch --quiet origin 'refs/tags/v*:refs/tags/v*'
  local prev
  prev="$({ git tag -l 'v[0-9]*' | grep -v -x -F "${TAG}" || true; printf '%s\n' "${TAG}"; } | sort -V | grep -x -B1 -F "${TAG}" | head -1)"
  [ "${prev}" = "${TAG}" ] || printf '%s\n' "${prev}"
}

# Shows every change to RELEASE_CRITICAL since the previous release tag and waits for an explicit "y".
release_gate() {
  local prev="$1"
  if [ -z "${prev}" ]; then
    echo "    No earlier v* tag on origin: nothing to compare the release-critical files against."
    return 0
  fi
  local stat
  stat="$(git diff --stat "${prev}" HEAD -- "${RELEASE_CRITICAL[@]}")"
  if [ -z "${stat}" ]; then
    echo "    Release-critical files unchanged since ${prev}."
    return 0
  fi
  echo "    Release-critical files changed since ${prev}:"
  printf '%s\n' "${stat}"
  git --no-pager diff "${prev}" HEAD -- "${RELEASE_CRITICAL[@]}"
  echo
  echo "    These files decide what ships signed and notarized. Review the diff above."
  local answer
  printf '    Ship these changes? Type y to continue: '
  read -r answer || answer=""
  [ "${answer}" = "y" ] || { echo "ABORT: release-critical changes not confirmed."; return 1; }
}

# True when git is set up to sign: a signing key is configured (SSH or GPG).
signing_configured() { [ -n "$(git config --get user.signingkey || true)" ]; }

signing_setup_hint() {
  echo "    No signing key is configured (git config user.signingkey is empty), so the tag and the tap commit are unsigned."
  echo "    To sign with the SSH key this Mac already has:"
  echo "      git config --global gpg.format ssh"
  echo "      git config --global user.signingkey ~/.ssh/id_ed25519.pub"
  echo "      git config --global commit.gpgsign true"
  echo "      git config --global tag.gpgsign true"
  echo "    and add the public key on GitHub as a *signing* key (Settings → SSH and GPG keys → New SSH key → Signing Key)."
}

# After codesign: the shipped entitlements equal the committed plist, hardened runtime is on, the Team ID is ours.
assert_signature() {
  local app="$1"
  local shipped expected
  shipped="$(codesign -d --entitlements - --xml "${app}" 2>/dev/null | plutil -convert xml1 -o - -)"
  expected="$(plutil -convert xml1 -o - "${APP_ENTITLEMENTS}")"
  if [ "${shipped}" != "${expected}" ]; then
    echo "ABORT: shipped entitlements differ from ${APP_ENTITLEMENTS}:"
    diff <(printf '%s\n' "${expected}") <(printf '%s\n' "${shipped}") || true
    return 1
  fi
  local info
  info="$(codesign -dvvv "${app}" 2>&1)"
  printf '%s\n' "${info}" | grep -q -F 'flags=0x10000(runtime)' || { echo "ABORT: hardened runtime flag missing or extra flags set:"; printf '%s\n' "${info}" | grep -F 'flags=' || true; return 1; }
  printf '%s\n' "${info}" | grep -q -x -F "TeamIdentifier=${EXPECTED_TEAM_ID}" || { echo "ABORT: TeamIdentifier is not ${EXPECTED_TEAM_ID}:"; printf '%s\n' "${info}" | grep -F 'TeamIdentifier=' || true; return 1; }
  echo "    Entitlements match ${APP_ENTITLEMENTS}; flags=0x10000(runtime); TeamIdentifier=${EXPECTED_TEAM_ID}."
}

# The GitHub release body. Uses VERSION, TAG, ASSET_NAME, SHA256 and VT_LINK; reads release-notes/<tag>.md when present.
render_notes() {
  # The first public release has nobody to update yet: say so, and present the update path for later versions.
  local earlier_tags whats_new="" lead update_label
  earlier_tags="$(git ls-remote --tags origin 'refs/tags/v*' | awk '{print $2}' | grep -v -x -F -e "refs/tags/${TAG}" -e "refs/tags/${TAG}^{}" || true)"
  # Optional per-release notes, shown after the heading: release-notes/<tag>.md (committed with the release).
  if [ -f "release-notes/${TAG}.md" ]; then
    whats_new="$(cat "release-notes/${TAG}.md")

"
  fi
  if [ -z "${earlier_tags}" ]; then
    lead="First public release of Rote, the keyboard shortcut coach for your Mac.

"
    update_label="Updating, from this version on"
  else
    lead=""
    update_label="Existing users — update in app"
  fi
  cat <<EOF
## Rote ${VERSION}

${lead}${whats_new}**${update_label}:** click the Rote menu bar icon → **About** → **Download** → **Install and Relaunch** (if no update is listed yet, click **Check Now** first). Rote checks the download against the SHA-256 published here and verifies the app's Developer ID signature before installing it. When \`Rote.app\` belongs to your user (a Homebrew install, or an app you dragged to Applications) it is replaced without a password; an app owned by another account asks for an administrator password. Homebrew: \`brew upgrade --cask rote\`.

**New install:** download \`${ASSET_NAME}\` below, unzip, move **Rote.app** to Applications, launch, and grant Accessibility when asked. Or \`brew install --cask beyondthecode-bc/tap/rote\`.

**Manual fallback:** if the in-app installer is unavailable or fails, quit Rote, replace \`/Applications/Rote.app\` with the unzipped app, and relaunch.

**Requirements:** macOS 14 or later, Apple Silicon or Intel, Accessibility permission.

**Security:** Developer ID signed, hardened runtime, Apple notarized and stapled. VirusTotal: 0 malicious — ${VT_LINK}

**SHA-256** (\`${ASSET_NAME}\`):
\`\`\`
${SHA256}
\`\`\`
EOF
}

# Prints the digest GitHub computed for an asset of the release (sha256:<hex>), or nothing.
release_asset_digest() { gh release view "${TAG}" --repo "${REPO}" --json assets --jq ".assets[] | select(.name == \"$1\" and .state == \"uploaded\") | .digest"; }

main() {
  [ -f release.env ] || { echo "ABORT: release.env missing (copy release.env.example)"; exit 1; }
  # shellcheck disable=SC1091
  source release.env
  : "${IDENTITY:?}" "${TEAM_ID:?}" "${P8:?}" "${KEY_ID:?}" "${ISSUER:?}"
  : "${VT_API_KEY:?Set VT_API_KEY in release.env or the environment}"
  [ "${TEAM_ID}" = "${EXPECTED_TEAM_ID}" ] || { echo "ABORT: TEAM_ID in release.env is ${TEAM_ID}, expected ${EXPECTED_TEAM_ID}"; exit 1; }

  # The tag and its source archives must be the commit that is built: a clean tree, pushed to origin main.
  # Untracked files count, because XcodeGen and SwiftPM compile every file in their source folders.
  [ -z "$(git status --porcelain)" ] || { echo "ABORT: uncommitted or untracked files; commit and push the release changes first"; git status --short; exit 1; }
  git fetch --quiet origin main
  local commit
  commit="$(git rev-parse HEAD)"
  [ "${commit}" = "$(git rev-parse origin/main)" ] || { echo "ABORT: HEAD is not origin/main; push the release commit to origin main first"; exit 1; }
  # A version is released once. A tag left by a run that failed after tagging may be reused only at this same commit.
  local tag_commit
  tag_commit="$(remote_tag_commit)"
  [ -z "${tag_commit}" ] || [ "${tag_commit}" = "${commit}" ] || { echo "ABORT: ${TAG} already points at ${tag_commit}, not HEAD ${commit}; bump the version"; exit 1; }
  if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "ABORT: release ${TAG} already exists on ${REPO}; a release is never replaced. Bump the patch version and release again."
    echo "       (A draft left by a failed run can be removed with: gh release delete ${TAG} --repo ${REPO})"
    exit 1
  fi

  # One work folder; the build, test and tap trees are removed on exit, the export folder (app, zip, .sha256) is kept.
  local work build_dir test_dir export_dir app_path zip_path
  work="$(mktemp -d)"
  trap "rm -rf '${work}/build' '${work}/test' '${work}/homebrew-tap'" EXIT
  build_dir="${work}/build"
  test_dir="${work}/test"
  export_dir="${work}/export"
  app_path="${export_dir}/${APP_NAME}.app"
  zip_path="${export_dir}/${ASSET_NAME}"

  echo "==> Releasing ${APP_NAME} ${VERSION} (${TAG} at ${commit}) -> ${ASSET_NAME}"

  echo "==> 1/11 Release-critical files since the previous release"
  local prev
  prev="$(previous_release_tag)"
  release_gate "${prev}"
  signing_configured || signing_setup_hint

  echo "==> 2/11 Language check + tests (RoteCore, RoteAX, app)"
  python3 scripts/check-languages.py
  swift test --package-path Packages/RoteCore
  swift test --package-path Packages/RoteAX
  xcodegen generate
  xcodebuild test \
    -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" -destination 'platform=macOS' \
    -derivedDataPath "${test_dir}" CODE_SIGN_IDENTITY="-"

  echo "==> 3/11 xcodegen + Release build (Developer ID, hardened runtime)"
  xcodegen generate
  xcodebuild \
    -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" -configuration Release \
    -derivedDataPath "${build_dir}" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${IDENTITY}" DEVELOPMENT_TEAM="${TEAM_ID}" \
    ENABLE_HARDENED_RUNTIME=YES PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    clean build
  mkdir -p "${export_dir}"
  cp -R "${build_dir}/Build/Products/Release/${APP_NAME}.app" "${app_path}"

  echo "==> 4/11 Codesign (never --deep) + check the shipped signature"
  codesign --force --options runtime --timestamp --entitlements "${APP_ENTITLEMENTS}" --sign "${IDENTITY}" "${app_path}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"
  assert_signature "${app_path}"

  echo "==> 5/11 Notarize"
  ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"
  xcrun notarytool submit "${zip_path}" --key "${P8}" --key-id "${KEY_ID}" --issuer "${ISSUER}" --wait

  echo "==> 6/11 Staple + verify"
  xcrun stapler staple "${app_path}"
  xcrun stapler validate "${app_path}"
  spctl -a -vvv -t exec "${app_path}" || true

  echo "==> 7/11 Re-zip stapled app + checksum"
  rm -f "${zip_path}"
  ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"
  SHA256="$(shasum -a 256 "${zip_path}" | awk '{print $1}')"
  echo "${SHA256}  ${ASSET_NAME}" > "${zip_path}.sha256"
  local sha256_file_digest
  sha256_file_digest="$(shasum -a 256 "${zip_path}.sha256" | awk '{print $1}')"
  echo "    SHA-256: ${SHA256}"

  echo "==> 8/11 VirusTotal (abort unless 0 malicious)"
  # The key travels in a header read from a file descriptor, never on the command line (visible in ps).
  local vt_up vt_id vt_done vt_j vt_st vt_mal
  vt_up="$(curl -s -X POST https://www.virustotal.com/api/v3/files -H @<(printf 'x-apikey: %s' "${VT_API_KEY}") --form "file=@${zip_path}")"
  vt_id="$(printf '%s' "${vt_up}" | /usr/bin/python3 -c 'import sys,json
d=json.load(sys.stdin)
if "data" not in d: sys.stderr.write("VT upload failed: %s\n"%json.dumps(d)); sys.exit(1)
print(d["data"]["id"])')"
  vt_done=0
  for _ in $(seq 1 30); do
    vt_j="$(curl -s -H @<(printf 'x-apikey: %s' "${VT_API_KEY}") "https://www.virustotal.com/api/v3/analyses/${vt_id}")"
    vt_st="$(printf '%s' "${vt_j}" | /usr/bin/python3 -c 'import sys,json
try: print(json.load(sys.stdin)["data"]["attributes"]["status"])
except Exception: print("pending")')"
    if [ "${vt_st}" = "completed" ]; then
      vt_mal="$(printf '%s' "${vt_j}" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["attributes"]["stats"]["malicious"])')"
      echo "    VirusTotal malicious: ${vt_mal}"
      [ "${vt_mal}" = "0" ] || { echo "ABORT: VirusTotal flagged ${vt_mal} engines."; exit 1; }
      vt_done=1; break
    fi
    echo "    VT status=${vt_st}; waiting 10s…"; sleep 10
  done
  [ "${vt_done}" = "1" ] || { echo "ABORT: VirusTotal did not complete — not publishing."; exit 1; }
  VT_LINK="https://www.virustotal.com/gui/file/${SHA256}"

  echo "==> 9/11 Tag ${TAG}"
  if [ -z "$(remote_tag_commit)" ]; then
    if signing_configured; then
      git tag -s "${TAG}" -m "${APP_NAME} ${VERSION}" "${commit}"
    else
      git tag -a "${TAG}" -m "${APP_NAME} ${VERSION}" "${commit}"
    fi
    git push origin "refs/tags/${TAG}"
  else
    echo "    ${TAG} already on origin at ${commit} (left by an earlier run); reusing it."
  fi
  [ "$(remote_tag_commit)" = "${commit}" ] || { echo "ABORT: ${TAG} on origin does not point at ${commit}"; exit 1; }

  echo "==> 10/11 GitHub release: draft, read back, publish"
  render_notes | gh release create "${TAG}" --repo "${REPO}" --draft --verify-tag \
    --title "${APP_NAME} ${VERSION}" --notes-file - "${zip_path}" "${zip_path}.sha256"
  # Read the draft back: both assets uploaded, with the digest GitHub computed equal to the local checksum.
  local remote_digest remote_sha256_digest
  remote_digest="$(release_asset_digest "${ASSET_NAME}")"
  remote_sha256_digest="$(release_asset_digest "${ASSET_NAME}.sha256")"
  if [ "${remote_digest}" != "sha256:${SHA256}" ] || [ "${remote_sha256_digest}" != "sha256:${sha256_file_digest}" ]; then
    echo "ABORT: the draft's assets do not match the local files; deleting the draft."
    echo "       ${ASSET_NAME}: GitHub ${remote_digest:-missing}, local sha256:${SHA256}"
    echo "       ${ASSET_NAME}.sha256: GitHub ${remote_sha256_digest:-missing}, local sha256:${sha256_file_digest}"
    gh release delete "${TAG}" --repo "${REPO}" --yes
    exit 1
  fi
  # And download it the way a user will, then hash it.
  local readback
  readback="${work}/readback"
  mkdir -p "${readback}"
  gh release download "${TAG}" --repo "${REPO}" --pattern "${ASSET_NAME}" --dir "${readback}"
  [ "$(shasum -a 256 "${readback}/${ASSET_NAME}" | awk '{print $1}')" = "${SHA256}" ] || { echo "ABORT: downloaded ${ASSET_NAME} does not hash to ${SHA256}; deleting the draft."; gh release delete "${TAG}" --repo "${REPO}" --yes; exit 1; }
  rm -rf "${readback}"
  echo "    Draft verified: ${ASSET_NAME} sha256:${SHA256}"
  gh release edit "${TAG}" --repo "${REPO}" --draft=false --latest
  # Read the published release back: not a draft, tag at the released commit, digest unchanged. Immutable from here on.
  local published
  published="$(gh release view "${TAG}" --repo "${REPO}" --json isDraft,tagName,url --jq '[.isDraft, .tagName, .url] | @tsv')"
  [ "$(printf '%s' "${published}" | cut -f1)" = "false" ] || { echo "ABORT: ${TAG} is still a draft after publishing: ${published}"; exit 1; }
  [ "$(remote_tag_commit)" = "${commit}" ] || { echo "ABORT: ${TAG} on origin no longer points at ${commit}"; exit 1; }
  [ "$(release_asset_digest "${ASSET_NAME}")" = "sha256:${SHA256}" ] || { echo "ABORT: ${ASSET_NAME} digest changed between draft and publish"; exit 1; }
  echo "    Published: $(printf '%s' "${published}" | cut -f3)"

  echo "==> 11/11 Homebrew tap"
  local tap_dir
  tap_dir="${work}/homebrew-tap"
  git clone --depth 1 "https://github.com/${TAP_REPO}.git" "${tap_dir}"
  mkdir -p "${tap_dir}/Casks"
  cat > "${tap_dir}/Casks/rote.rb" <<EOF
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
  git -C "${tap_dir}" add Casks/rote.rb
  local sign_flag=()
  signing_configured && sign_flag=(-S)
  git -C "${tap_dir}" -c user.name="Vlad" -c user.email="62696158+beyondthecode-bc@users.noreply.github.com" commit ${sign_flag[@]+"${sign_flag[@]}"} -m "rote ${VERSION}"
  git -C "${tap_dir}" push
  echo "==> Done. ${APP_NAME} ${VERSION}  SHA256=${SHA256}  VT=${VT_LINK}"
  echo "    Release files: ${export_dir}"
  echo "    Now read the live release body back and verify the update paths, asset name, VT result and checksum."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
