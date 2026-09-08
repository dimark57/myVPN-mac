# Security

## Secrets

- Never commit WireGuard `.conf` files with real keys. `*.conf` is gitignored except `tests/fixtures/` (TEST-NET only).
- Live profiles: `~/.config/wireguard/{macbook,home}.conf` (mode `0600`).
- Routing/NAS prefs (no keys): `~/.config/myvpn/settings.json`.
- NAS password: macOS Keychain service `local.myvpn.mac.nas`.

## Reporting

If you find a vulnerability in the privileged helper or update path, open a private report via GitHub Security Advisories on [dimark57/myVPN-mac](https://github.com/dimark57/myVPN-mac) or file an issue without pasting keys/configs.

## Updates

In-app updates download `myVPN.app.zip` from GitHub Releases. Prefer verifying the release tag matches what you expect. Ad-hoc code signing is used until Developer ID / notarization is available — Gatekeeper warnings are expected.
