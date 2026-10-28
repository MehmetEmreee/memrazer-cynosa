# Changelog

## 1.2.0 – 2026-10-29

- App renamed to memrazer-cynosa (bundle id io.github.mehmetemreee.memrazer-cynosa); settings and GIF library migrate automatically
- DMG packaging with optional Developer ID signing and notarization; GitHub release workflow
- README preview GIFs rendered from the effect engine (`swift run render-previews`)
- Amber sun near the horizon so it stays visible at sunset

## 1.1.0 – 2026-10-29

- Background menu bar agent (no Dock icon), starts at login by default
- Status item: left-click opens the quick panel, right-click opens a menu (settings, effect, login, quit)
- Airliners fly straight and level with nose and tail on the same row

## 1.0.0 – 2026-10-29

- Razer Cynosa V2 driver over USB control transfers (no kernel extension, no TCC prompt)
- Hot-plug detection, busy-response polling, delta row updates, adaptive frame rate
- On-device effects, brightness, game mode
- Live effects: sky (sun, moon, stars, clouds, airliners), fire, rainbow, GIF/APNG/WebP
- SwiftUI app with menu bar and live preview
- `cynosa` command-line tool
