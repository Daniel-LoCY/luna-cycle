#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUBLISH_RELEASE=false
case "${1:-}" in
  ""|--draft) ;;
  --publish) PUBLISH_RELEASE=true ;;
  --help|-h)
    echo "Usage: scripts/publish_github_release.sh [--draft|--publish]"
    echo "Default: build and validate the APK, then create a GitHub Draft Release."
    echo "--publish: build and validate the APK, then publish the GitHub Release immediately."
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Usage: scripts/publish_github_release.sh [--draft|--publish]" >&2
    exit 2
    ;;
esac
if [[ "$#" -gt 1 ]]; then
  echo "Pass at most one release mode option." >&2
  exit 2
fi

OWNER="${LUNA_GITHUB_OWNER:-Daniel-LoCY}"
REPOSITORY="${LUNA_GITHUB_REPOSITORY:-luna-cycle}"
REMOTE_REPOSITORY="$OWNER/$REPOSITORY"
EXPECTED_APPLICATION_ID="app.lunacycle.personal"
EXPECTED_CERTIFICATE="909ab7d2ac94094284335763e26246acf716376b1b2844867dbcf1b0cfb0b1d5"
SIGNING_PROPERTIES="$ROOT/android/key.properties"

if [[ ! -f "$SIGNING_PROPERTIES" ]]; then
  echo "Missing android/key.properties; configure the existing local release signing key first." >&2
  exit 1
fi
if ! git check-ignore -q android/key.properties; then
  echo "android/key.properties must be ignored by Git before publishing." >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Commit the release source and require a clean working tree before creating a draft." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "Sign in to GitHub CLI first with: gh auth login" >&2
  exit 1
fi
if ! gh repo view "$REMOTE_REPOSITORY" --json isPrivate --jq '.isPrivate == false' | grep -qx true; then
  echo "The public repository $REMOTE_REPOSITORY must exist before creating OTA releases." >&2
  exit 1
fi

if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
  SDK_ROOT="$ANDROID_SDK_ROOT"
elif [[ -n "${ANDROID_HOME:-}" ]]; then
  SDK_ROOT="$ANDROID_HOME"
elif [[ -f android/local.properties ]]; then
  SDK_ROOT="$(sed -n 's/^sdk\.dir=//p' android/local.properties | head -n 1)"
else
  echo "Set ANDROID_SDK_ROOT or ANDROID_HOME to the Android SDK." >&2
  exit 1
fi

APKSIGNER="$(python3 - "$SDK_ROOT/build-tools" apksigner <<'PY'
import pathlib
import sys

root, executable = pathlib.Path(sys.argv[1]), sys.argv[2]
matches = list(root.glob(f"*/{executable}"))
def version(path):
    try:
        return tuple(int(part) for part in path.parent.name.split("."))
    except ValueError:
        return ()
print(max(matches, key=version) if matches else "")
PY
)"
APKANALYZER="$(python3 - "$SDK_ROOT/cmdline-tools" apkanalyzer <<'PY'
import pathlib
import sys

root, executable = pathlib.Path(sys.argv[1]), sys.argv[2]
matches = list(root.glob(f"*/bin/{executable}"))
def version(path):
    try:
        return tuple(int(part) for part in path.parent.parent.name.split("."))
    except ValueError:
        return ()
if any(path.parent.parent.name == "latest" for path in matches):
    print(next(path for path in matches if path.parent.parent.name == "latest"))
else:
    print(max(matches, key=version) if matches else "")
PY
)"
if [[ -z "$APKSIGNER" || -z "$APKANALYZER" ]]; then
  echo "Android SDK build-tools/apksigner and cmdline-tools/apkanalyzer are required." >&2
  exit 1
fi

VERSION_LINE="$(sed -n 's/^version: *//p' pubspec.yaml | head -n 1)"
if [[ ! "$VERSION_LINE" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
  echo "Expected pubspec.yaml version in name+build form, got: $VERSION_LINE" >&2
  exit 1
fi
VERSION_NAME="${BASH_REMATCH[1]}"
VERSION_CODE="${BASH_REMATCH[2]}"
TAG="v$VERSION_NAME"
APK="build/app/outputs/flutter-apk/app-release.apk"
APK_NAME="luna-cycle-${VERSION_NAME}+${VERSION_CODE}.apk"
NOTES_FILE="${LUNA_RELEASE_NOTES_FILE:-CHANGELOG.md}"
MANIFEST="build/update.json"

if gh release view "$TAG" --repo "$REMOTE_REPOSITORY" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Review its draft and publish it with:" >&2
  echo "  gh release edit $TAG --repo $REMOTE_REPOSITORY --draft=false" >&2
  exit 1
fi

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  "$FLUTTER_BIN" --no-version-check build apk --release \
    --dart-define="LUNA_GITHUB_OWNER=$OWNER" \
    --dart-define="LUNA_GITHUB_REPOSITORY=$REPOSITORY"
else
  flutter --no-version-check build apk --release \
    --dart-define="LUNA_GITHUB_OWNER=$OWNER" \
    --dart-define="LUNA_GITHUB_REPOSITORY=$REPOSITORY"
fi
[[ -f "$APK" ]] || { echo "Release APK was not produced: $APK" >&2; exit 1; }
[[ -f "$NOTES_FILE" ]] || { echo "Release notes file not found: $NOTES_FILE" >&2; exit 1; }

APK_PACKAGE="$($APKANALYZER manifest application-id "$APK")"
APK_VERSION="$($APKANALYZER manifest version-name "$APK")"
APK_CODE="$($APKANALYZER manifest version-code "$APK")"
APK_MIN_API="$($APKANALYZER manifest min-sdk "$APK")"
if [[ "$APK_PACKAGE" != "$EXPECTED_APPLICATION_ID" ||
      "$APK_VERSION" != "$VERSION_NAME" ||
      "$APK_CODE" != "$VERSION_CODE" ]]; then
  echo "APK package/version metadata does not match pubspec.yaml." >&2
  exit 1
fi

CERTIFICATE="$("$APKSIGNER" verify --print-certs "$APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: *//p' | head -n 1 | tr '[:upper:]' '[:lower:]' | tr -d ':')"
if [[ "$CERTIFICATE" != "$EXPECTED_CERTIFICATE" ]]; then
  echo "APK is not signed by the pinned Luna Cycle release certificate." >&2
  exit 1
fi
APK_SHA256="$(shasum -a 256 "$APK" | awk '{print $1}')"
RELEASE_APK="build/$APK_NAME"
cp "$APK" "$RELEASE_APK"
mkdir -p "$(dirname "$MANIFEST")"

python3 - "$MANIFEST" "$VERSION_NAME" "$VERSION_CODE" "$APK_MIN_API" "$APK_NAME" "$APK_SHA256" "$NOTES_FILE" <<'PY'
import json
import pathlib
import sys

manifest_path, version_name, version_code, min_api, apk_name, digest, notes_path = sys.argv[1:]
notes = pathlib.Path(notes_path).read_text(encoding="utf-8")
payload = {
    "formatVersion": 1,
    "applicationId": "app.lunacycle.personal",
    "versionName": version_name,
    "versionCode": int(version_code),
    "minAndroidApi": int(min_api),
    "apkAssetName": apk_name,
    "apkSha256": digest,
    "releaseNotes": notes,
}
pathlib.Path(manifest_path).write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

COMMIT="$(git rev-parse HEAD)"
if [[ "$PUBLISH_RELEASE" == true ]]; then
  gh release create "$TAG" \
    --repo "$REMOTE_REPOSITORY" \
    --target "$COMMIT" \
    --title "Luna Cycle $VERSION_NAME" \
    --notes-file "$NOTES_FILE" \
    "$RELEASE_APK" \
    "$MANIFEST"
  echo "Published release: $REMOTE_REPOSITORY $TAG"
else
  gh release create "$TAG" \
    --repo "$REMOTE_REPOSITORY" \
    --draft \
    --target "$COMMIT" \
    --title "Luna Cycle $VERSION_NAME" \
    --notes-file "$NOTES_FILE" \
    "$RELEASE_APK" \
    "$MANIFEST"
  echo "Draft release created: $REMOTE_REPOSITORY $TAG"
fi
echo "APK SHA-256: $APK_SHA256"
if [[ "$PUBLISH_RELEASE" != true ]]; then
  echo "Review the draft in GitHub and publish it only after verifying the release notes and APK."
fi
