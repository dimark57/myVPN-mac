#!/bin/zsh
# Local patch: auto-up on launch + NAS status + loading UX in menu bar.
# Works without /Volumes/Nas — builds from ~/.local/share/myvpn/macos-src.
set -euo pipefail

PATCH_ROOT="${0:A:h}"
FILES="${PATCH_ROOT}/files"
SRC_TREE="${HOME}/.local/share/myvpn/macos-src"
NAS_REPO="/Volumes/Nas/Project/myVPN-mac"
DEST="${HOME}/Applications/myVPN.app"

[[ -f "${FILES}/AppDelegate.swift" && -f "${FILES}/StatusSnapshot.swift" ]] || {
  print -r -- "missing patch files in ${FILES}" >&2
  exit 1
}
[[ -d "${SRC_TREE}/MyVPN" ]] || {
  print -r -- "missing local tree ${SRC_TREE} — re-seed from agent recover" >&2
  exit 1
}

print -r -- "== apply Swift patch =="
/bin/cp -f "${FILES}/AppDelegate.swift" "${SRC_TREE}/MyVPN/AppDelegate.swift"
/bin/cp -f "${FILES}/StatusSnapshot.swift" "${SRC_TREE}/MyVPN/StatusSnapshot.swift"
[[ -f "${FILES}/MyVPNCLI.swift" ]] && /bin/cp -f "${FILES}/MyVPNCLI.swift" "${SRC_TREE}/MyVPN/MyVPNCLI.swift"
[[ -f "${FILES}/RulesStatus.swift" ]] && /bin/cp -f "${FILES}/RulesStatus.swift" "${SRC_TREE}/MyVPN/RulesStatus.swift"
[[ -f "${FILES}/generate-xcodeproj.py" ]] && /bin/cp -f "${FILES}/generate-xcodeproj.py" "${SRC_TREE}/generate-xcodeproj.py"

# Bump build so Launch Services notices the new binary.
python3 - <<'PY'
from pathlib import Path
import re
p = Path.home() / ".local/share/myvpn/macos-src/MyVPN/Info.plist"
t = p.read_text()
m = re.search(r"<key>CFBundleVersion</key>\s*<string>(\d+)</string>", t)
if m:
    n = int(m.group(1)) + 1
    t = t[: m.start(1)] + str(n) + t[m.end(1) :]
    p.write_text(t)
    print(f"CFBundleVersion → {n}")
PY

print -r -- "== assets =="
ICON="${SRC_TREE}/MyVPN/Assets.xcassets"
OUT=/tmp/myvpn-icons-patch
rm -rf "${OUT}"
mkdir -p "${OUT}" \
  "${ICON}/AppIcon.appiconset" \
  "${ICON}/MenuBarIcon.imageset"

swift "${SRC_TREE}/tools/generate-icons.swift" "${OUT}"
sips -z 64 64 "${OUT}/icon_128.png" --out "${ICON}/AppIcon.appiconset/icon_32@2x.png" >/dev/null
cp "${OUT}/icon_16.png"   "${ICON}/AppIcon.appiconset/icon_16.png"
cp "${OUT}/icon_32.png"   "${ICON}/AppIcon.appiconset/icon_32.png"
cp "${OUT}/icon_128.png"  "${ICON}/AppIcon.appiconset/icon_128.png"
cp "${OUT}/icon_256.png"  "${ICON}/AppIcon.appiconset/icon_256.png"
cp "${OUT}/icon_256.png"  "${ICON}/AppIcon.appiconset/icon_256@2x.png"
cp "${OUT}/icon_512.png"  "${ICON}/AppIcon.appiconset/icon_512.png"
cp "${OUT}/icon_512.png"  "${ICON}/AppIcon.appiconset/icon_512@2x.png"
cp "${OUT}/icon_1024.png" "${ICON}/AppIcon.appiconset/icon_1024.png"
cp "${OUT}/menubar.png"   "${ICON}/MenuBarIcon.imageset/menubar.png"
cp "${OUT}/menubar@2x.png" "${ICON}/MenuBarIcon.imageset/menubar@2x.png"

cat > "${ICON}/Contents.json" <<'EOF'
{"info":{"author":"xcode","version":1}}
EOF
cat > "${ICON}/AppIcon.appiconset/Contents.json" <<'EOF'
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_32.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_256.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512@2x.png", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
cat > "${ICON}/MenuBarIcon.imageset/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

print -r -- "== build + install =="
pkill -x myVPN 2>/dev/null || true
sleep 0.5
# So loading UX is visible: start from down if helper works.
if [[ -S /var/run/myvpn-helper.sock ]]; then
  "${HOME}/.local/bin/myvpn" down >/dev/null 2>&1 || true
fi

/bin/zsh "${SRC_TREE}/install-app.zsh"

# Best-effort sync patched Swift back to NAS repo when mounted.
if [[ -d "${NAS_REPO}/macos/MyVPN/MyVPN" ]]; then
  print -r -- "== sync → NAS repo =="
  /bin/cp -f "${FILES}/AppDelegate.swift" "${NAS_REPO}/macos/MyVPN/MyVPN/AppDelegate.swift" || true
  /bin/cp -f "${FILES}/StatusSnapshot.swift" "${NAS_REPO}/macos/MyVPN/MyVPN/StatusSnapshot.swift" || true
else
  print -r -- "(NAS repo not mounted — skip sync; local tree is SoT until remount)"
fi

print -r -- "== launch =="
open "${DEST}"
sleep 1
pgrep -lf 'Applications/myVPN.app/Contents/MacOS/myVPN' || print -r -- "WARN: app not running"
print -r -- "done. Open menu quickly → should see «включаю…» / NAS ожидание|монтирую…"
