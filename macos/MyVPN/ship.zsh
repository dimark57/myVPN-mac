#!/bin/zsh
# Atomic ship for myVPN-mac (cd recipe macos-gh-app).
# One CFBundleVersion bump → optional fdir → one commit → build/zip → tag HEAD → gh release → push.
# Never opens stage/DerivedData; never installs to ~/Applications.
#
# Usage:
#   macos/MyVPN/ship.zsh <version> --confirm [--message "..."] [--notes "..."] [--skip-fdir] [--no-push]
#   macos/MyVPN/ship.zsh --confirm --bump patch|minor|major   # version from current ShortVersion
#
# Agent / cd-skill: always pass --confirm after user asked to ship/катим.
set -euo pipefail

ROOT="$(cd "${0:A:h}/../.." && pwd)"
APP_DIR="${ROOT}/macos/MyVPN"
PLIST="${APP_DIR}/MyVPN/Info.plist"
REPO="${MYVPN_GH_REPO:-dimark57/myVPN-mac}"
export TMPDIR="${TMPDIR:-/tmp}"

VERSION=""
BUMP=""
CONFIRM=0
SKIP_FDIR=0
NO_PUSH=0
MSG=""
NOTES=""

usage() {
  print -r -- "usage: ship.zsh <X.Y.Z> --confirm [--message t] [--notes t] [--skip-fdir] [--no-push]" >&2
  print -r -- "       ship.zsh --confirm --bump patch|minor|major [...]" >&2
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --confirm) CONFIRM=1; shift ;;
    --skip-fdir) SKIP_FDIR=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --message|--msg)
      MSG="${2:-}"; shift 2 ;;
    --notes)
      NOTES="${2:-}"; shift 2 ;;
    --bump)
      BUMP="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*)
      print -r -- "unknown flag: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$VERSION" && "$1" == [0-9]* ]]; then
        VERSION="$1"; shift
      else
        print -r -- "unexpected arg: $1" >&2
        usage
      fi
      ;;
  esac
done

(( CONFIRM == 1 )) || {
  print -r -- "ship: нужен --confirm (явное согласие в чате / cd-skill)" >&2
  exit 1
}

bump_semver() {
  local ver="$1" kind="$2"
  local major minor patch
  IFS=. read -r major minor patch <<<"$ver"
  case "$kind" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) print -r -- "bad --bump $kind" >&2; exit 2 ;;
  esac
  print -r -- "${major}.${minor}.${patch}"
}

cur="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")"
if [[ -n "$BUMP" ]]; then
  VERSION="$(bump_semver "$cur" "$BUMP")"
fi
[[ -n "$VERSION" ]] || usage
[[ "$VERSION" == v* ]] && VERSION="${VERSION#v}"

TAG="v${VERSION}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  print -r -- "ship: version must be X.Y.Z (got ${VERSION})" >&2
  exit 2
fi
[[ -n "$MSG" ]] || MSG="Ship ${VERSION}"
[[ -n "$NOTES" ]] || NOTES="$(cat <<EOF
## myVPN ${VERSION}

In-app: **Настройки → Update** (or auto).

One concern per release. See commit: ${MSG}
EOF
)"

cd "${ROOT}"

if git rev-parse "${TAG}" >/dev/null 2>&1; then
  print -r -- "ship: tag ${TAG} already exists locally — abort (no retag ritual)" >&2
  exit 1
fi
if git ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null | /usr/bin/grep -q .; then
  print -r -- "ship: tag ${TAG} already on origin — abort" >&2
  exit 1
fi

print -r -- "ship: bump Info.plist → ${VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}" 2>/dev/null || echo 0)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "${PLIST}"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}")"

if (( SKIP_FDIR == 0 )); then
  print -r -- "ship: fdir-policy…"
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout 120 "${ROOT}/tests/fdir-policy.zsh"
  else
    "${ROOT}/tests/fdir-policy.zsh"
  fi
fi

print -r -- "ship: commit (single SHA for tag)…"
git add -A
if git diff --cached --quiet; then
  print -r -- "ship: nothing to commit — working tree clean after bump? unexpected" >&2
  exit 1
fi
git commit -m "$(cat <<EOF
${MSG}

EOF
)"

HEAD="$(git rev-parse HEAD)"
print -r -- "ship: HEAD ${HEAD} build ${BUILD}"

print -r -- "ship: tag ${TAG} → ${HEAD} (before gh — no retag)"
git tag -a "${TAG}" -m "myVPN ${VERSION}" "${HEAD}"

if (( NO_PUSH == 0 )); then
  # Push tag BEFORE gh release create — otherwise gh may mint a remote tag on the wrong tip.
  print -r -- "ship: push main + ${TAG} (before assets)"
  git push -u origin HEAD
  git push origin "${TAG}"
else
  print -r -- "ship: --no-push set; will not push before gh"
fi

print -r -- "ship: package + gh release (no second plist bump)…"
MYVPN_RELEASE_NO_BUMP=1 \
MYVPN_RELEASE_NOTES="$NOTES" \
MYVPN_GH_REPO="$REPO" \
  "${APP_DIR}/release.zsh" "${VERSION}"

if (( NO_PUSH == 1 )); then
  print -r -- "ship: --no-push set; push manually: git push origin HEAD && git push origin ${TAG}"
fi

print -r -- "OK ${TAG} build=${BUILD} https://github.com/${REPO}/releases/tag/${TAG}"
print -r -- "На этом Mac: Настройки → Update. Не копируй stage/DerivedData."
